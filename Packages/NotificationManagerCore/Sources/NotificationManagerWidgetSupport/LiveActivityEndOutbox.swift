import Foundation

public struct LiveActivityEndObservation: Sendable {
    public let activityID: String
    public let event: ReminderLiveActivityEvent
    public let pushToken: String?
    public let cloudCommitted: Bool

    public init(
        activityID: String, event: ReminderLiveActivityEvent,
        pushToken: String?, cloudCommitted: Bool
    ) {
        self.activityID = activityID
        self.event = event
        self.pushToken = pushToken
        self.cloudCommitted = cloudCommitted
    }
}

public struct LiveActivityEndOutboxSummary: Sendable {
    public let isConfigured: Bool
    public let pendingCount: Int
    public let lastFailure: String?
}

/// Shared by foreground reconciliation and LiveActivityIntent in the app process.
/// Tokens, job identities and revisions are local, excluded from device backup.
public actor LiveActivityEndOutbox {
    public static let reconciliationNeeded = Notification.Name("PunctualEndAPIReconciliationNeeded")

    private struct Pending: Codable, Equatable {
        let request: LiveActivityEndAPIRequest
        let timing: LiveActivityEndTiming?
        let token: String?
    }

    private enum DispatchState: String, Codable { case scheduled, started }
    private enum FlushRequest { case all, cancellations }

    private struct Record: Codable {
        let jobID: UUID
        let eventID: String
        var revision: UInt64 = 0
        var observedTiming: LiveActivityEndTiming
        var desiredTiming: LiveActivityEndTiming?
        var desiredToken: String?
        var remoteTiming: LiveActivityEndTiming?
        var remoteToken: String?
        var remoteKnown = false
        var dispatchState: DispatchState? = .scheduled
        var cancelled = false
        var remoteClosed = false
        var pending: Pending?
        var needsValidation = true
    }

    private struct State: Codable {
        var records: [String: Record] = [:]
        var dismissals: [String: Date] = [:]
    }

    private let url: URL
    private let sender: (any LiveActivityEndJobSending)?
    private let now: @Sendable () -> Date
    private let persistData: (@Sendable (Data, URL) throws -> Void)?
    private var state: State
    private var draining = false
    private var requestedFlush: FlushRequest?
    private var retryTask: Task<Void, Never>?
    private var retryAt: Date?
    private var retryCount = 0
    private var lastFailure: String?
    // Never publish a restored PUT before this process has revalidated its snapshot.
    private var validatedActivities: Set<String> = []

    public init(
        url: URL, sender: (any LiveActivityEndJobSending)?,
        now: @escaping @Sendable () -> Date = { Date() },
        persistData: (@Sendable (Data, URL) throws -> Void)? = nil
    ) throws {
        self.url = url
        self.sender = sender
        self.now = now
        self.persistData = persistData
        if FileManager.default.fileExists(atPath: url.path) {
            state = try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
        } else {
            state = State()
        }
    }

    deinit { retryTask?.cancel() }

    public func reconcile(_ observations: [LiveActivityEndObservation]) throws {
        var nextState = state
        var nextValidated = validatedActivities
        let current = Set(observations.map(\.activityID))
        for id in Array(nextState.records.keys) where !current.contains(id) {
            guard var record = nextState.records[id], !record.cancelled, !record.remoteClosed else {
                continue
            }
            record.cancelled = true
            try selectPending(&record)
            nextState.records[id] = record
            nextValidated.remove(id)
        }
        for observation in observations {
            let timing = LiveActivityEndTiming(event: observation.event)
            var record =
                nextState.records[observation.activityID]
                ?? Record(jobID: UUID(), eventID: observation.event.id, observedTiming: timing)
            record.observedTiming = timing
            record.desiredToken = observation.pushToken ?? record.desiredToken
            if nextState.dismissals[observation.event.id].map({ $0 > now() }) == true {
                record.cancelled = true
            }
            if observation.cloudCommitted {
                record.desiredTiming = timing
                record.needsValidation = false
                nextValidated.insert(observation.activityID)
            } else {
                record.needsValidation = true
                nextValidated.remove(observation.activityID)
            }
            try selectPending(&record)
            nextState.records[observation.activityID] = record
        }
        pruneExpiredLocalState(&nextState)
        do {
            try persist(nextState)
        } catch {
            // A failed write must not leave an older PUT authorized after a newer
            // desired snapshot was observed. Revocation itself needs no new bytes.
            validatedActivities.removeAll()
            throw error
        }
        state = nextState
        validatedActivities = nextValidated
    }

    public func dismiss(eventID: String, notificationDate: Date) throws {
        var nextState = state
        // Covers any subsequent edit to this occurrence's permitted display window.
        let expiry = notificationDate.addingTimeInterval(8 * 60 * 60)
        nextState.dismissals[eventID] = max(nextState.dismissals[eventID] ?? .distantPast, expiry)
        for id in Array(nextState.records.keys) {
            guard var record = nextState.records[id], record.eventID == eventID else { continue }
            record.cancelled = true
            try selectPending(&record)
            nextState.records[id] = record
        }
        do {
            try persist(nextState)
        } catch {
            validatedActivities.subtract(state.records.filter { $0.value.eventID == eventID }.keys)
            throw error
        }
        state = nextState
    }

    public func dismissedEventIDs() -> Set<String> {
        Set(state.dismissals.filter { $0.value > now() }.keys)
    }

    public func summary() -> LiveActivityEndOutboxSummary {
        LiveActivityEndOutboxSummary(
            isConfigured: sender != nil,
            pendingCount: state.records.values.filter { $0.pending != nil }.count,
            lastFailure: lastFailure)
    }

    public func flush(cancellationsOnly: Bool = false) async {
        guard let sender else { return }
        if draining {
            if requestedFlush != .all { requestedFlush = cancellationsOnly ? .cancellations : .all }
            return
        }
        draining = true
        retryTask?.cancel()
        retryTask = nil
        if !cancellationsOnly { retryAt = nil }
        defer {
            draining = false
            if let request = requestedFlush {
                requestedFlush = nil
                Task { await self.flush(cancellationsOnly: request == .cancellations) }
            } else {
                armRetry()
            }
        }
        var skipped: Set<String> = []
        while !Task.isCancelled {
            let candidate = nextPendingID(skipping: skipped, cancellationsOnly: cancellationsOnly)
            guard let id = candidate, let pending = state.records[id]?.pending else { break }
            do {
                let response = try await sender.send(pending.request)
                try apply(response, to: id, sent: pending)
                lastFailure = nil
                retryCount = 0
            } catch {
                do {
                    let shouldRetry = try handle(error, activityID: id, pending: pending)
                    if shouldRetry { scheduleRetry(after: retryDelay(for: error)) }
                } catch {
                    lastFailure = "LOCAL_STORAGE_UNAVAILABLE"
                }
                skipped.insert(id)
            }
        }
    }

    private func nextPendingID(skipping skipped: Set<String>, cancellationsOnly: Bool) -> String? {
        state.records.keys.sorted().first { id in
            guard !skipped.contains(id), let record = state.records[id],
                let pending = record.pending
            else {
                return false
            }
            if cancellationsOnly { return pending.request.operation == .cancel }
            if pending.request.operation == .put {
                return validatedActivities.contains(id) && !record.needsValidation
            }
            return true
        }
    }

    private func apply(_ response: LiveActivityEndJobResponse, to id: String, sent pending: Pending)
        throws
    {
        guard var record = state.records[id] else { return }
        record.revision = max(record.revision, UInt64(response.revision) ?? record.revision)
        record.remoteKnown = true
        if ["dispatching", "retrying", "awaiting_token"].contains(response.status) {
            record.dispatchState = .started
        }
        if pending.request.operation == .put {
            record.remoteTiming = pending.timing
            record.remoteToken = pending.token
        } else if pending.request.operation == .token {
            record.remoteToken = pending.token
        }
        if record.pending == pending { record.pending = nil }
        if response.isTerminal {
            record.remoteClosed = true
            if record.pending?.request.operation != .cancel { record.pending = nil }
        }
        try selectPending(&record)
        var nextState = state
        nextState.records[id] = record
        try persist(nextState)
        state = nextState
    }

    private func selectPending(_ record: inout Record) throws {
        if record.cancelled {
            if record.pending?.request.operation == .cancel { return }
            if record.remoteClosed {
                record.pending = nil
                return
            }
            let revision = try nextRevision(record.revision)
            record.pending = Pending(
                request: try .cancel(jobID: record.jobID, revision: revision), timing: nil,
                token: nil)
            record.revision = revision
            return
        }
        guard !record.remoteClosed, let token = record.desiredToken else { return }
        let operation: LiveActivityEndAPIRequest.Operation
        let timing: LiveActivityEndTiming?
        if record.dispatchState != .started, !record.needsValidation,
            let desired = record.desiredTiming,
            !record.remoteKnown || desired != record.remoteTiming
        {
            operation = .put
            timing = desired
        } else if record.remoteKnown, token != record.remoteToken {
            operation = .token
            timing = nil
        } else {
            // Keep a previously authorized PUT durable while awaiting a newer cloud edit.
            return
        }
        if let pending = record.pending, pending.request.operation == operation,
            pending.token == token, pending.timing == timing
        {
            return
        }
        let revision = try nextRevision(record.revision)
        let request: LiveActivityEndAPIRequest
        if let timing {
            request = try .put(
                jobID: record.jobID, revision: revision, token: token, timing: timing)
        } else {
            request = try .token(jobID: record.jobID, revision: revision, token: token)
        }
        record.revision = revision
        record.pending = Pending(request: request, timing: timing, token: token)
    }

    private func handle(
        _ error: any Error, activityID: String, pending: Pending
    ) throws -> Bool {
        guard var record = state.records[activityID] else { return false }
        var nextValidated = validatedActivities
        var needsReconciliation = false
        if let apiError = error as? LiveActivityEndAPIError {
            switch apiError {
            case .server(let status, let code, let serverRevision, _):
                lastFailure = code
                if let serverRevision { record.revision = max(record.revision, serverRevision) }
                if status == 410 {
                    record.remoteClosed = true
                    record.pending = nil
                } else if status == 409 {
                    if record.pending == pending { record.pending = nil }
                    if code == "DISPATCH_STARTED" {
                        // Timing is immutable, but the existing job still accepts token updates.
                        record.dispatchState = .started
                        record.remoteKnown = true
                        try selectPending(&record)
                    } else if record.cancelled {
                        try selectPending(&record)
                    } else {
                        record.needsValidation = true
                        nextValidated.remove(activityID)
                        needsReconciliation = true
                    }
                } else if status == 400 || status == 413 {
                    if record.pending == pending { record.pending = nil }
                    record.needsValidation = true
                    nextValidated.remove(activityID)
                }
                var nextState = state
                nextState.records[activityID] = record
                try persist(nextState)
                state = nextState
                validatedActivities = nextValidated
                if needsReconciliation {
                    NotificationCenter.default.post(name: Self.reconciliationNeeded, object: nil)
                }
                return status == 401
                    || status == 409
                        && (record.cancelled || code == "DISPATCH_STARTED" && record.pending != nil)
                    || status == 429 || status >= 500
            case .unsupportedAttestation, .invalidConfiguration:
                lastFailure = "REMOTE_END_UNAVAILABLE"
                return false
            case .invalidRevision:
                lastFailure = "REVISION_EXHAUSTED"
                return false
            case .challengeExpired, .invalidResponse, .invalidAttestationKey:
                lastFailure = "REMOTE_END_RETRY_PENDING"
                return true
            }
        }
        lastFailure = "REMOTE_END_RETRY_PENDING"
        return true
    }

    private func nextRevision(_ current: UInt64) throws -> UInt64 {
        guard current < UInt64.max else { throw LiveActivityEndAPIError.invalidRevision }
        return current + 1
    }

    private func retryDelay(for error: any Error) -> TimeInterval {
        retryCount = min(retryCount + 1, 9)
        let delay = min(pow(2, Double(retryCount - 1)), 300)
        if case LiveActivityEndAPIError.server(_, _, _, let retryAfter) = error,
            let retryAfter
        {
            return max(delay, retryAfter)
        }
        return delay
    }

    private func scheduleRetry(after delay: TimeInterval) {
        let deadline = now().addingTimeInterval(delay)
        retryAt = min(retryAt ?? deadline, deadline)
        if !draining { armRetry() }
    }

    private func armRetry() {
        guard retryTask == nil, let retryAt else { return }
        let delay = max(0, retryAt.timeIntervalSince(now()))
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            await self?.retry()
        }
    }

    private func retry() async {
        retryTask = nil
        retryAt = nil
        await flush()
    }

    private func pruneExpiredLocalState(_ state: inout State) {
        let current = now()
        state.dismissals = state.dismissals.filter { $0.value > current }
        state.records = state.records.filter { _, record in
            record.observedTiming.startsAt.addingTimeInterval(36 * 60 * 60) > current
        }
    }

    private func persist(_ state: State) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        if let persistData {
            try persistData(data, url)
            return
        }
        #if os(iOS)
            try data.write(
                to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
            try data.write(to: url, options: .atomic)
        #endif
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var location = url
        try location.setResourceValues(values)
    }
}
