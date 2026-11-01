import Foundation
import NotificationManagerWidgetSupport
import OSLog
import UIKit

@MainActor
final class ReminderLiveActivityService {
    private static let knownActivitiesKey = "reminder-live-activities.known"
    private static let suppressedActivitiesKey = "reminder-live-activities.suppressed"
    private let client: any ReminderLiveActivityClient
    private let defaults: UserDefaults
    private let schedulesExpiration: Bool
    private let canStart: @MainActor () -> Bool
    private let currentDate: @MainActor () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let logger = Logger(subsystem: "org.tknw.punctual", category: "LiveActivities")
    private var expirationTask: Task<Void, Never>?
    private var revision: UInt64 = 0
    private var pendingRequest: ReconciliationRequest?
    private var isReconciling = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var knownActivities: [String: String]
    private var suppressedUntil: [String: Double]

    init(
        defaults: UserDefaults = .standard,
        client: any ReminderLiveActivityClient = SystemReminderLiveActivityClient(),
        schedulesExpiration: Bool = true,
        canStart: @escaping @MainActor () -> Bool = {
            UIApplication.shared.applicationState == .active
        },
        currentDate: @escaping @MainActor () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
            try await Task.sleep(for: .seconds($0))
        }
    ) {
        self.defaults = defaults
        self.client = client
        self.schedulesExpiration = schedulesExpiration
        self.canStart = canStart
        self.currentDate = currentDate
        self.sleep = sleep
        knownActivities =
            defaults.dictionary(forKey: Self.knownActivitiesKey) as? [String: String] ?? [:]
        suppressedUntil =
            defaults.dictionary(forKey: Self.suppressedActivitiesKey) as? [String: Double] ?? [:]
    }

    deinit {
        expirationTask?.cancel()
    }

    /// Starts require foreground execution. Cleanup can also run during system-granted background time.
    func reconcile(
        events: [ReminderLiveActivityEvent],
        now: Date = Date(),
        allowStarts: Bool = true
    ) async {
        revision &+= 1
        expirationTask?.cancel()
        expirationTask = nil
        pendingRequest = ReconciliationRequest(
            events: events, now: now, allowStarts: allowStarts, revision: revision)
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            guard !isReconciling else { return }
            isReconciling = true
            Task { await drainReconciliations() }
        }
    }

    private func drainReconciliations() async {
        while let request = pendingRequest {
            pendingRequest = nil
            await apply(request)
        }
        isReconciling = false
        let completedWaiters = waiters
        waiters.removeAll()
        for continuation in completedWaiters { continuation.resume() }
    }

    private func apply(_ request: ReconciliationRequest) async {
        guard revision == request.revision else { return }
        let events = request.events
        let now = request.now
        let allowStarts = request.allowStarts
        let currentRevision = request.revision
        let records = client.currentActivities()
        let recordIDs = Set(records.map(\.id))
        let eventByID = Dictionary(
            events.filter(\.isValid).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        suppressedUntil = suppressedUntil.filter { $0.value > now.timeIntervalSince1970 }

        // Missing activities that this app previously created were dismissed by the person or system.
        // Remember that decision for the occurrence, including across an app relaunch.
        for (eventID, activityID) in knownActivities where !recordIDs.contains(activityID) {
            if let event = eventByID[eventID], event.activityEndDate > now {
                suppressedUntil[eventID] = event.activityEndDate.timeIntervalSince1970
            }
        }
        for record in records where record.state == .dismissed || record.state == .ended {
            suppressedUntil[record.eventID] = record.content.activityEndDate.timeIntervalSince1970
        }

        let desired =
            client.activitiesEnabled
            ? ReminderLiveActivitySelection.select(
                events: events,
                at: now,
                supportsScheduling: client.supportsScheduling,
                suppressedIDs: Set(suppressedUntil.keys)
            ) : []
        let desiredIDs = Set(desired.map(\.id))
        var retained: [String: ReminderLiveActivityRecord] = [:]
        for record in records {
            if desiredIDs.contains(record.eventID),
                record.state != .dismissed, record.state != .ended,
                retained[record.eventID] == nil
            {
                retained[record.eventID] = record
            } else {
                // Record our own cancellation before awaiting ActivityKit, so a newer
                // snapshot never mistakes the resulting absence for a user dismissal.
                if knownActivities[record.eventID] == record.id {
                    knownActivities.removeValue(forKey: record.eventID)
                    persistState()
                }
                await client.end(record.id)
                guard revision == currentRevision else { return }
            }
        }
        knownActivities = retained.mapValues(\.id)

        for event in desired {
            if let record = retained[event.id] {
                if record.content != ReminderActivityAttributes.ContentState(event: event) {
                    await client.update(record.id, event: event)
                    guard revision == currentRevision else { return }
                }
            } else if allowStarts && canStart() {
                do {
                    knownActivities[event.id] = try client.request(
                        event, scheduled: event.startDate > now)
                } catch {
                    logger.error(
                        "Unable to start reminder Live Activity: \(String(describing: error), privacy: .public)"
                    )
                }
            }
        }
        persistState()
        scheduleNextReconciliation(events: events, selected: desired, now: now)
    }

    private func persistState() {
        defaults.set(knownActivities, forKey: Self.knownActivitiesKey)
        defaults.set(suppressedUntil, forKey: Self.suppressedActivitiesKey)
    }

    private func scheduleNextReconciliation(
        events: [ReminderLiveActivityEvent],
        selected: [ReminderLiveActivityEvent],
        now: Date
    ) {
        let endDates = selected.filter { knownActivities[$0.id] != nil }.map(\.activityEndDate)
        let startDates = events.filter {
            $0.isValid && $0.startDate > now && suppressedUntil[$0.id] == nil
        }.map(\.startDate)
        guard schedulesExpiration,
            let deadline = (endDates + startDates).min()
        else { return }
        let delay = max(0, deadline.timeIntervalSince(now))
        let sleep = sleep
        expirationTask = Task { [weak self] in
            do {
                try await sleep(delay)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            // This task resumes only when iOS gives the process execution time; it does not wake it.
            await reconcile(events: events, now: currentDate(), allowStarts: canStart())
        }
    }

    private struct ReconciliationRequest {
        let events: [ReminderLiveActivityEvent]
        let now: Date
        let allowStarts: Bool
        let revision: UInt64
    }
}
