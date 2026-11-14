import Foundation
import Synchronization
import Testing

@testable import NotificationManagerWidgetSupport

struct LiveActivityEndOutboxTests {
    private let now = Date(timeIntervalSince1970: 1_794_816_000)

    @Test func cloudCommitIsRequiredBeforeTheFirstRegistration() async throws {
        let context = try context()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        try await context.outbox.reconcile([observation(committed: false)])
        await context.outbox.flush()
        #expect(await context.sender.requests.isEmpty)

        try await context.outbox.reconcile([observation(committed: true)])
        await context.outbox.flush()

        #expect(await context.sender.requests.map(\.operation) == [.put])
    }

    @Test func failedBodySurvivesRestartButMustBeRevalidatedBeforeReplay() async throws {
        let context = try context()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        await context.sender.failNextRequest()
        try await context.outbox.reconcile([observation(committed: true)])
        await context.outbox.flush()
        let original = try #require(await context.sender.requests.first)
        let clock = now
        let restored = try LiveActivityEndOutbox(
            url: context.url, sender: context.sender, now: { clock })

        await restored.flush()
        #expect(await context.sender.requests.count == 1)
        try await restored.reconcile([observation(committed: false)])
        await restored.flush()
        #expect(await context.sender.requests.count == 1)
        try await restored.reconcile([observation(committed: true)])
        await restored.flush()

        let replay = try #require(await context.sender.requests.last)
        #expect(replay.jobID == original.jobID)
        #expect(replay.revision == original.revision)
        #expect(replay.body == original.body)
    }

    @Test func offlineDismissalPersistsAndCancelsBeforeAnUnsentRegistration() async throws {
        let context = try context()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let observation = observation(committed: true)
        try await context.outbox.reconcile([observation])
        try await context.outbox.dismiss(
            eventID: observation.event.id, notificationDate: observation.event.notificationDate)
        let clock = now
        let restored = try LiveActivityEndOutbox(
            url: context.url, sender: context.sender, now: { clock })

        await restored.flush(cancellationsOnly: true)
        try await restored.reconcile([observation])
        await restored.flush()

        #expect(await context.sender.requests.map(\.operation) == [.cancel])
        #expect(await restored.dismissedEventIDs().contains(observation.event.id))
    }

    @Test func tokenRotationDoesNotPublishAnUncommittedSchedule() async throws {
        let context = try context()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        try await context.outbox.reconcile([observation(committed: true)])
        await context.outbox.flush()

        try await context.outbox.reconcile([
            observation(committed: false, token: "02", endOffset: 900)
        ])
        await context.outbox.flush()

        let requests = await context.sender.requests
        #expect(requests.map(\.operation) == [.put, .token])
        let tokenBody = try #require(String(data: requests[1].body, encoding: .utf8))
        #expect(!tokenBody.contains("endsAt"))

        try await context.outbox.reconcile([
            observation(committed: true, token: "02", endOffset: 900)
        ])
        await context.outbox.flush()
        #expect(await context.sender.requests.map(\.operation) == [.put, .token, .put])
    }

    @Test func conflictRequiresFreshSnapshotRatherThanBlindlyIncreasingTheRevision() async throws {
        let context = try context()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        await context.sender.conflictNextRequest()
        try await context.outbox.reconcile([observation(committed: true)])
        await context.outbox.flush()
        await context.outbox.flush()
        #expect(await context.sender.requests.count == 1)

        try await context.outbox.reconcile([observation(committed: true, endOffset: 900)])
        await context.outbox.flush()

        let current = try #require(await context.sender.requests.last)
        #expect(current.revision == 18)
        let body = try #require(JSONSerialization.jsonObject(with: current.body) as? [String: Any])
        #expect(body["endsAt"] as? String == now.addingTimeInterval(900).ISO8601Format())
    }

    @Test func cancelArrivingDuringAPICallIsNotOverwrittenByItsSuccess() async throws {
        let context = try context()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let (started, didStart) = AsyncStream<Void>.makeStream()
        let (release, resume) = AsyncStream<Void>.makeStream()
        await context.sender.pauseFirstRequest(started: didStart, release: release)
        let observation = observation(committed: true)
        try await context.outbox.reconcile([observation])
        var iterator = started.makeAsyncIterator()
        let sending = Task { await context.outbox.flush() }
        _ = await iterator.next()

        try await context.outbox.dismiss(
            eventID: observation.event.id, notificationDate: observation.event.notificationDate)
        resume.yield(())
        await sending.value

        #expect(await context.sender.requests.map(\.operation) == [.put, .cancel])
        #expect(await context.outbox.summary().pendingCount == 0)
        didStart.finish()
        resume.finish()
    }

    @Test func dispatchStartedStopsTimingPutsButStillUpdatesTokensAndCancels() async throws {
        let context = try context()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        try await context.outbox.reconcile([observation(committed: true)])
        await context.outbox.flush()

        await context.sender.conflictNextRequest(code: "DISPATCH_STARTED")
        try await context.outbox.reconcile([observation(committed: true, endOffset: 900)])
        await context.outbox.flush()
        for _ in 0..<3 {
            try await context.outbox.reconcile([observation(committed: true, endOffset: 900)])
            await context.outbox.flush()
        }
        #expect(await context.sender.requests.map(\.operation) == [.put, .put])

        try await context.outbox.reconcile([
            observation(committed: false, token: "02", endOffset: 1200)
        ])
        await context.outbox.flush()
        let current = observation(committed: false)
        try await context.outbox.dismiss(
            eventID: current.event.id, notificationDate: current.event.notificationDate)
        await context.outbox.flush()

        #expect(await context.sender.requests.map(\.operation) == [.put, .put, .token, .cancel])
    }

    @Test func failedInitialPersistenceCannotExposeARequestToFlush() async throws {
        let writer = EndOutboxFailingWriter()
        let context = try context(persistData: writer.write)
        defer { try? FileManager.default.removeItem(at: context.directory) }
        writer.failNextWrite()
        await #expect(throws: EndOutboxWriteError.self) {
            try await context.outbox.reconcile([observation(committed: true)])
        }
        await context.outbox.flush()
        #expect(await context.sender.requests.isEmpty)

        try await context.outbox.reconcile([observation(committed: true)])
        let durableBody = try Data(contentsOf: context.url)
        await context.outbox.flush()
        #expect(await context.sender.requests.count == 1)
        #expect(!durableBody.isEmpty)
    }

    @Test func failedEditAndDismissalPersistenceCannotAuthorizeAnObsoletePut() async throws {
        let writer = EndOutboxFailingWriter()
        let context = try context(persistData: writer.write)
        defer { try? FileManager.default.removeItem(at: context.directory) }
        try await context.outbox.reconcile([observation(committed: true)])
        let durable = try Data(contentsOf: context.url)
        writer.failNextWrite()
        await #expect(throws: EndOutboxWriteError.self) {
            try await context.outbox.reconcile([
                observation(committed: true, token: "02", endOffset: 900)
            ])
        }
        writer.failNextWrite()
        let current = observation(committed: true)
        await #expect(throws: EndOutboxWriteError.self) {
            try await context.outbox.dismiss(
                eventID: current.event.id, notificationDate: current.event.notificationDate)
        }
        #expect(await context.outbox.dismissedEventIDs().isEmpty)
        #expect(try Data(contentsOf: context.url) == durable)
        await context.outbox.flush()
        #expect(await context.sender.requests.isEmpty)

        try await context.outbox.reconcile([
            observation(committed: true, token: "02", endOffset: 900)
        ])
        await context.outbox.flush()

        let replay = try #require(await context.sender.requests.last)
        #expect(replay.revision == 2)
        let payload = try #require(
            JSONSerialization.jsonObject(with: replay.body) as? [String: Any])
        #expect(payload["pushToken"] as? String == "02")
        #expect(payload["endsAt"] as? String == now.addingTimeInterval(900).ISO8601Format())
    }

    @Test func aFreshSnapshotFlushCannotBeLostWhileAnotherRequestIsSuspended() async throws {
        let context = try context()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let (started, didStart) = AsyncStream<Void>.makeStream()
        let (release, resume) = AsyncStream<Void>.makeStream()
        await context.sender.conflictNextRequest()
        await context.sender.pauseRequest(number: 2, started: didStart, release: release)
        try await context.outbox.reconcile([
            observation(committed: true), observation(committed: true, activityID: "activity-two")
        ])
        var iterator = started.makeAsyncIterator()
        let sending = Task { await context.outbox.flush() }
        _ = await iterator.next()
        try await context.outbox.reconcile([
            observation(committed: true, endOffset: 900),
            observation(committed: true, activityID: "activity-two")
        ])
        await context.outbox.flush()
        resume.yield(())
        await sending.value
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while await context.sender.requests.count < 3, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(await context.sender.requests.count == 3)
        #expect(await context.outbox.summary().pendingCount == 0)
        didStart.finish()
        resume.finish()
    }

    @Test func aRetryCannotBeLostWhileAnotherRequestIsSuspended() async throws {
        let context = try context()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let (started, didStart) = AsyncStream<Void>.makeStream()
        let (release, resume) = AsyncStream<Void>.makeStream()
        await context.sender.failNextRequest()
        await context.sender.pauseRequest(number: 2, started: didStart, release: release)
        try await context.outbox.reconcile([
            observation(committed: true), observation(committed: true, activityID: "activity-two")
        ])
        var iterator = started.makeAsyncIterator()
        let sending = Task { await context.outbox.flush() }
        _ = await iterator.next()
        try await Task.sleep(for: .milliseconds(1200))
        resume.yield(())
        await sending.value
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while await context.sender.requests.count < 3, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(await context.sender.requests.count == 3)
        #expect(await context.outbox.summary().pendingCount == 0)
        didStart.finish()
        resume.finish()
    }

    private func observation(
        committed: Bool, token: String = "01", endOffset: TimeInterval = 600,
        activityID: String = "activity-one"
    ) -> LiveActivityEndObservation {
        LiveActivityEndObservation(
            activityID: activityID,
            event: ReminderLiveActivityEvent(
                reminderID: UUID(uuidString: "dd69953f-d628-441c-aebe-823496232ca1")!,
                title: "Private title", startDate: now.addingTimeInterval(-60),
                endDate: now.addingTimeInterval(endOffset), notificationDate: now),
            pushToken: token, cloudCommitted: committed)
    }

    private func context(
        persistData: (@Sendable (Data, URL) throws -> Void)? = nil
    ) throws -> EndOutboxContext {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "end-outbox-\(UUID())")
        let url = directory.appending(path: "outbox.json")
        let sender = EndOutboxTestSender()
        let clock = now
        let outbox = try LiveActivityEndOutbox(
            url: url, sender: sender, now: { clock }, persistData: persistData)
        return EndOutboxContext(directory: directory, url: url, sender: sender, outbox: outbox)
    }
}

private struct EndOutboxContext: Sendable {
    let directory: URL
    let url: URL
    let sender: EndOutboxTestSender
    let outbox: LiveActivityEndOutbox
}

private actor EndOutboxTestSender: LiveActivityEndJobSending {
    private(set) var requests: [LiveActivityEndAPIRequest] = []
    private var failsNext = false
    private var conflictCode: String?
    private var pauseNumber = 1
    private var started: AsyncStream<Void>.Continuation?
    private var release: AsyncStream<Void>?

    func failNextRequest() { failsNext = true }
    func conflictNextRequest(code: String = "STALE_REVISION") { conflictCode = code }
    func pauseFirstRequest(started: AsyncStream<Void>.Continuation, release: AsyncStream<Void>) {
        pauseRequest(number: 1, started: started, release: release)
    }
    func pauseRequest(
        number: Int, started: AsyncStream<Void>.Continuation, release: AsyncStream<Void>
    ) {
        self.pauseNumber = number
        self.started = started
        self.release = release
    }

    func send(_ request: LiveActivityEndAPIRequest) async throws -> LiveActivityEndJobResponse {
        requests.append(request)
        if requests.count == pauseNumber, let release {
            started?.yield(())
            var iterator = release.makeAsyncIterator()
            _ = await iterator.next()
        }
        if failsNext {
            failsNext = false
            throw URLError(.notConnectedToInternet)
        }
        if let conflictCode {
            self.conflictCode = nil
            throw LiveActivityEndAPIError.server(
                status: 409, code: conflictCode, currentRevision: 17, retryAfter: nil)
        }
        let payload: [String: Any] = [
            "jobId": request.jobID.uuidString.lowercased(), "revision": String(request.revision),
            "status": request.operation == .cancel ? "cancelled" : "scheduled",
            "activityEndsAt": NSNull(),
            "delivery": [
                "state": "not_sent", "attemptCount": 0, "acceptedAt": NSNull(),
                "mayHaveBeenSent": false
            ]
        ]
        return try LiveActivityEndAPIJSON.decoder().decode(
            LiveActivityEndJobResponse.self, from: JSONSerialization.data(withJSONObject: payload))
    }
}

private enum EndOutboxWriteError: Error { case injectedFailure }

private final class EndOutboxFailingWriter: Sendable {
    private let shouldFail = Mutex(false)

    func failNextWrite() { shouldFail.withLock { $0 = true } }

    func write(_ data: Data, to url: URL) throws {
        let fails = shouldFail.withLock { value in
            let result = value
            value = false
            return result
        }
        if fails { throw EndOutboxWriteError.injectedFailure }
        try data.write(to: url, options: .atomic)
    }
}
