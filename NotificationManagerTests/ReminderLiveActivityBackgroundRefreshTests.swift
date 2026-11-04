import Foundation
import NotificationManagerWidgetSupport
import Testing

@testable import NotificationManager

@Suite("Live Activity background expiration scheduling")
@MainActor
struct LiveActivityBackgroundRefreshTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func schedulesEarliestExpirationIncludingPendingAndEndedActivities() {
        var submitted: [Date] = []
        let scheduler = ReminderLiveActivityBackgroundRefresh(
            submit: { submitted.append($0) }, cancel: {})

        scheduler.schedule(activities: [
            record(endingAfter: 300), record(endingAfter: 120, state: .pending),
            record(endingAfter: 30, state: .dismissed)
        ])
        scheduler.schedule(activities: [record(endingAfter: -60, state: .ended)])

        #expect(submitted == [now.addingTimeInterval(120), now.addingTimeInterval(-60)])
    }

    @Test func editsReplaceTheRequestAndAnEmptyInventoryCancelsIt() {
        var submitted: [Date] = []
        var cancellations = 0
        let scheduler = ReminderLiveActivityBackgroundRefresh(
            submit: { submitted.append($0) }, cancel: { cancellations += 1 })

        scheduler.schedule(activities: [record(endingAfter: 300)])
        scheduler.schedule(activities: [record(endingAfter: 600)])
        #expect(cancellations == 0)
        scheduler.schedule(activities: [record(endingAfter: 300, state: .dismissed)])

        #expect(submitted == [now.addingTimeInterval(300), now.addingTimeInterval(600)])
        #expect(cancellations == 1)
    }

    @Test func failedReplacementKeepsTheExistingRequestAndCanRetry() {
        var shouldFail = false
        var submitted: [Date] = []
        var cancellations = 0
        let scheduler = ReminderLiveActivityBackgroundRefresh(
            submit: {
                if shouldFail { throw SchedulingError.unavailable }
                submitted.append($0)
            },
            cancel: { cancellations += 1 })

        scheduler.schedule(activities: [record(endingAfter: 300)])
        shouldFail = true
        scheduler.schedule(activities: [record(endingAfter: 600)])
        shouldFail = false
        scheduler.schedule(activities: [record(endingAfter: 600)])

        #expect(submitted == [now.addingTimeInterval(300), now.addingTimeInterval(600)])
        #expect(cancellations == 0)
    }

    @Test func appBundlePermitsTheRegisteredRefreshTask() {
        let identifiers =
            Bundle.main.object(
                forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]

        #expect(identifiers == [ReminderLiveActivityBackgroundRefresh.identifier])
        #expect(modes?.contains("fetch") == true)
    }

    private func record(
        endingAfter offset: TimeInterval, state: ReminderLiveActivityState = .active
    ) -> ReminderLiveActivityRecord {
        let event = ReminderLiveActivityEvent(
            reminderID: UUID(), title: "Reminder", startDate: now.addingTimeInterval(-300),
            endDate: now.addingTimeInterval(offset))
        return ReminderLiveActivityRecord(
            id: UUID().uuidString, eventID: event.id, state: state, content: .init(event: event))
    }

    private enum SchedulingError: Error {
        case unavailable
    }
}
