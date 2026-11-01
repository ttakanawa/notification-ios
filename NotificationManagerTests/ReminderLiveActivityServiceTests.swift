import Foundation
import NotificationManagerWidgetSupport
import Testing

@testable import NotificationManager

@Suite("ReminderLiveActivityService")
@MainActor
struct ReminderLiveActivityServiceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func schedulesFutureOccurrenceOnlyOnSupportedSystems() async throws {
        let context = try makeContext()
        let event = event(startOffset: 60)

        await context.service.reconcile(events: [event], now: now)

        #expect(context.client.requested == [event])
        #expect(context.client.scheduled == [true])

        let legacy = try makeContext(supportsScheduling: false)
        await legacy.service.reconcile(events: [event], now: now)
        #expect(legacy.client.requested.isEmpty)
        await legacy.service.reconcile(events: [event], now: now.addingTimeInterval(60))
        #expect(legacy.client.requested == [event])
        #expect(legacy.client.scheduled == [false])
    }

    @Test func editsUpdateExistingActivityAndDeletionEndsIt() async throws {
        let context = try makeContext()
        let original = event(startOffset: -60)
        await context.service.reconcile(events: [original], now: now)
        let revised = ReminderLiveActivityEvent(
            reminderID: original.reminderID, title: "Updated", startDate: original.startDate,
            endDate: original.endDate.addingTimeInterval(60)
        )

        await context.service.reconcile(events: [revised], now: now)
        #expect(context.client.requested == [original])
        #expect(context.client.updated == [revised])

        await context.service.reconcile(events: [], now: now)
        #expect(context.client.ended == ["activity-1"])
    }

    @Test func startDateChangeCancelsOldScheduledOccurrence() async throws {
        let context = try makeContext()
        let original = event(startOffset: 60)
        await context.service.reconcile(events: [original], now: now)
        let revised = ReminderLiveActivityEvent(
            reminderID: original.reminderID, title: original.title,
            startDate: original.startDate.addingTimeInterval(60),
            endDate: original.endDate.addingTimeInterval(60)
        )

        await context.service.reconcile(events: [revised], now: now)

        #expect(context.client.ended == ["activity-1"])
        #expect(context.client.requested == [original, revised])
    }

    @Test func foregroundReconciliationEndsExpiredRange() async throws {
        let context = try makeContext()
        let event = event(startOffset: -60)
        await context.service.reconcile(events: [event], now: now)

        await context.service.reconcile(events: [event], now: event.endDate)

        #expect(context.client.ended == ["activity-1"])
        #expect(context.client.requested.count == 1)
    }

    @Test func restoredActivityIsNotDuplicatedAndDismissalSurvivesRelaunch() async throws {
        let context = try makeContext()
        let event = event(startOffset: -60)
        await context.service.reconcile(events: [event], now: now)
        let restored = ReminderLiveActivityService(
            defaults: context.defaults, client: context.client, schedulesExpiration: false,
            canStart: { true }
        )

        await restored.reconcile(events: [event], now: now)
        #expect(context.client.requested.count == 1)

        context.client.records.removeAll()
        await restored.reconcile(events: [event], now: now)
        let relaunched = ReminderLiveActivityService(
            defaults: context.defaults, client: context.client, schedulesExpiration: false,
            canStart: { true }
        )
        await relaunched.reconcile(events: [event], now: now)

        #expect(context.client.requested.count == 1)
    }

    @Test func backgroundReconciliationCleansUpWithoutStarting() async throws {
        let context = try makeContext()
        let event = event(startOffset: -60)

        await context.service.reconcile(events: [event], now: now, allowStarts: false)
        #expect(context.client.requested.isEmpty)

        await context.service.reconcile(events: [event], now: now)
        await context.service.reconcile(events: [], now: now, allowStarts: false)
        #expect(context.client.ended == ["activity-1"])
    }

    @Test func deniedAuthorizationEndsExistingActivities() async throws {
        let context = try makeContext()
        let event = event(startOffset: -60)
        await context.service.reconcile(events: [event], now: now)

        context.client.activitiesEnabled = false
        await context.service.reconcile(events: [event], now: now)

        #expect(context.client.ended == ["activity-1"])
    }

    @Test func expirationRefillsFromFullInputAfterInitialSlotsWereFull() async throws {
        let context = try makeContext()
        let (wakeups, wakeupContinuation) = AsyncStream<Void>.makeStream()
        let (delays, delayContinuation) = AsyncStream<TimeInterval>.makeStream()
        let (requests, requestContinuation) = AsyncStream<ReminderLiveActivityEvent>.makeStream()
        context.client.onRequest = { requestContinuation.yield($0) }
        var clock = now
        let service = ReminderLiveActivityService(
            defaults: context.defaults, client: context.client, canStart: { true },
            currentDate: { clock },
            sleep: { delay in
                delayContinuation.yield(delay)
                var iterator = wakeups.makeAsyncIterator()
                _ = await iterator.next()
            }
        )
        let initial = (0..<3).map { _ in
            ReminderLiveActivityEvent(
                reminderID: UUID(), title: "Current", startDate: now.addingTimeInterval(-60),
                endDate: now.addingTimeInterval(60)
            )
        }
        let fourth = event(startOffset: 120)
        var requestIterator = requests.makeAsyncIterator()
        var delayIterator = delays.makeAsyncIterator()

        await service.reconcile(events: initial + [fourth], now: now)
        for _ in initial { _ = await requestIterator.next() }
        #expect(await delayIterator.next() == 60)
        clock = now.addingTimeInterval(60)
        wakeupContinuation.yield(())

        #expect(await requestIterator.next() == fourth)
        #expect(context.client.ended.count == 3)
        await service.reconcile(events: [], now: clock, allowStarts: false)
        wakeupContinuation.finish()
        delayContinuation.finish()
        requestContinuation.finish()
    }

    @Test func legacyForegroundTimerStartsRangeAtItsBoundary() async throws {
        let context = try makeContext(supportsScheduling: false)
        let (wakeups, wakeupContinuation) = AsyncStream<Void>.makeStream()
        let (delays, delayContinuation) = AsyncStream<TimeInterval>.makeStream()
        let (requests, requestContinuation) = AsyncStream<ReminderLiveActivityEvent>.makeStream()
        context.client.onRequest = { requestContinuation.yield($0) }
        var clock = now
        let service = ReminderLiveActivityService(
            defaults: context.defaults, client: context.client, canStart: { true },
            currentDate: { clock },
            sleep: { delay in
                delayContinuation.yield(delay)
                var iterator = wakeups.makeAsyncIterator()
                _ = await iterator.next()
            }
        )
        let event = event(startOffset: 60)
        var requestIterator = requests.makeAsyncIterator()
        var delayIterator = delays.makeAsyncIterator()

        await service.reconcile(events: [event], now: now)
        #expect(context.client.requested.isEmpty)
        #expect(await delayIterator.next() == 60)
        clock = event.startDate
        wakeupContinuation.yield(())

        #expect(await requestIterator.next() == event)
        #expect(context.client.scheduled == [false])
        await service.reconcile(events: [], now: clock, allowStarts: false)
        wakeupContinuation.finish()
        delayContinuation.finish()
        requestContinuation.finish()
    }

    @Test func reenabledRangeWaitsForEarlierCancellationBeforeRecreating() async throws {
        let context = try makeContext()
        let event = event(startOffset: -60)
        await context.service.reconcile(events: [event], now: now)
        let (ending, endingContinuation) = AsyncStream<Void>.makeStream()
        let (release, releaseContinuation) = AsyncStream<Void>.makeStream()
        let (reenabling, reenablingContinuation) = AsyncStream<Void>.makeStream()
        context.client.beforeEnding = { _ in
            endingContinuation.yield(())
            var iterator = release.makeAsyncIterator()
            _ = await iterator.next()
        }
        var endingIterator = ending.makeAsyncIterator()
        var reenablingIterator = reenabling.makeAsyncIterator()

        let disable = Task {
            await context.service.reconcile(events: [], now: now)
        }
        _ = await endingIterator.next()
        let enable = Task {
            reenablingContinuation.yield(())
            await context.service.reconcile(events: [event], now: now)
        }
        _ = await reenablingIterator.next()
        releaseContinuation.yield(())
        await disable.value
        await enable.value

        #expect(context.client.requested == [event, event])
        #expect(context.client.records.count == 1)
        await context.service.reconcile(events: [event], now: now)
        #expect(context.client.requested.count == 2)
        endingContinuation.finish()
        releaseContinuation.finish()
        reenablingContinuation.finish()
    }

    private func makeContext(supportsScheduling: Bool = true) throws -> LiveActivityTestContext {
        let defaults = try #require(
            UserDefaults(suiteName: "live-activity-tests.\(UUID().uuidString)"))
        let client = FakeReminderLiveActivityClient(supportsScheduling: supportsScheduling)
        let service = ReminderLiveActivityService(
            defaults: defaults, client: client, schedulesExpiration: false, canStart: { true })
        return LiveActivityTestContext(defaults: defaults, client: client, service: service)
    }

    private func event(startOffset: TimeInterval) -> ReminderLiveActivityEvent {
        let start = now.addingTimeInterval(startOffset)
        return ReminderLiveActivityEvent(
            reminderID: UUID(), title: "Reminder", startDate: start,
            endDate: start.addingTimeInterval(600)
        )
    }
}

@MainActor
private struct LiveActivityTestContext {
    let defaults: UserDefaults
    let client: FakeReminderLiveActivityClient
    let service: ReminderLiveActivityService
}

@MainActor
private final class FakeReminderLiveActivityClient: ReminderLiveActivityClient {
    var activitiesEnabled = true
    let supportsScheduling: Bool
    var records: [ReminderLiveActivityRecord] = []
    var requested: [ReminderLiveActivityEvent] = []
    var scheduled: [Bool] = []
    var updated: [ReminderLiveActivityEvent] = []
    var ended: [String] = []
    var onRequest: ((ReminderLiveActivityEvent) -> Void)?
    var beforeEnding: (@MainActor (String) async -> Void)?

    init(supportsScheduling: Bool) {
        self.supportsScheduling = supportsScheduling
    }

    func currentActivities() -> [ReminderLiveActivityRecord] { records }

    func request(_ event: ReminderLiveActivityEvent, scheduled: Bool) throws -> String {
        requested.append(event)
        self.scheduled.append(scheduled)
        let id = "activity-\(requested.count)"
        records.append(
            ReminderLiveActivityRecord(
                id: id, eventID: event.id, state: scheduled ? .pending : .active,
                content: ReminderActivityAttributes.ContentState(event: event)
            )
        )
        onRequest?(event)
        return id
    }

    func update(_ id: String, event: ReminderLiveActivityEvent) async {
        updated.append(event)
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index] = ReminderLiveActivityRecord(
            id: id, eventID: event.id, state: records[index].state,
            content: ReminderActivityAttributes.ContentState(event: event)
        )
    }

    func end(_ id: String) async {
        ended.append(id)
        await beforeEnding?(id)
        records.removeAll { $0.id == id }
    }
}
