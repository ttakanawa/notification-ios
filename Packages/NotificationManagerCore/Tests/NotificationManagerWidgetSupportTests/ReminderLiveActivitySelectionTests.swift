import Foundation
import Testing

@testable import NotificationManagerWidgetSupport

@Suite("ReminderLiveActivitySelection")
struct ReminderLiveActivitySelectionTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func legacySystemsOnlySelectCurrentlyActiveRanges() {
        let current = event(startOffset: -60, duration: 600)
        let future = event(startOffset: 60, duration: 600)
        let ended = event(startOffset: -600, duration: 600)

        #expect(
            ReminderLiveActivitySelection.select(
                events: [future, ended, current], at: now, supportsScheduling: false
            ) == [current]
        )
    }

    @Test func schedulingSelectsNearestOccurrencesAndDeduplicates() {
        let first = event(startOffset: -60, duration: 600)
        let second = event(startOffset: 60, duration: 600)
        let third = event(startOffset: 120, duration: 600)
        let fourth = event(startOffset: 180, duration: 600)

        #expect(
            ReminderLiveActivitySelection.select(
                events: [fourth, third, first, second, first], at: now, supportsScheduling: true
            ) == [first, second, third]
        )
    }

    @Test func noRangeReappearsAfterEightHourLimitOrDismissal() {
        let tooOld = event(startOffset: -8 * 3_600, duration: 12 * 3_600)
        let dismissed = event(startOffset: -60, duration: 600)

        #expect(tooOld.activityEndDate == now)
        #expect(
            ReminderLiveActivitySelection.select(
                events: [tooOld, dismissed], at: now, supportsScheduling: true,
                suppressedIDs: [dismissed.id]
            ).isEmpty
        )
    }

    @Test func invalidDatesAndEmptyTitlesAreRejected() {
        let id = UUID()
        let invalid = [
            ReminderLiveActivityEvent(
                reminderID: id, title: "", startDate: now, endDate: now.addingTimeInterval(60)),
            ReminderLiveActivityEvent(
                reminderID: id, title: "Invalid", startDate: now, endDate: now),
            ReminderLiveActivityEvent(
                reminderID: id, title: "Invalid", startDate: now,
                endDate: Date(timeIntervalSince1970: .infinity)),
            ReminderLiveActivityEvent(
                reminderID: id, title: "Invalid", startDate: now,
                endDate: now.addingTimeInterval(60), notificationDate: now.addingTimeInterval(-1)),
            ReminderLiveActivityEvent(
                reminderID: id, title: "Invalid", startDate: now,
                endDate: now.addingTimeInterval(60), notificationDate: now.addingTimeInterval(61)),
            ReminderLiveActivityEvent(
                reminderID: id, title: "Invalid", startDate: now,
                endDate: now.addingTimeInterval(60),
                notificationDate: Date(timeIntervalSince1970: .nan))
        ]

        #expect(
            ReminderLiveActivitySelection.select(events: invalid, at: now, supportsScheduling: true)
                .isEmpty)
    }

    @Test func changingDisplayOffsetsKeepsTheOccurrenceIdentity() {
        let id = UUID()
        let first = ReminderLiveActivityEvent(
            reminderID: id, title: "Reminder", startDate: now.addingTimeInterval(-300),
            endDate: now.addingTimeInterval(600), notificationDate: now)
        let revised = ReminderLiveActivityEvent(
            reminderID: id, title: "Reminder", startDate: now.addingTimeInterval(-600),
            endDate: now.addingTimeInterval(900), notificationDate: now)

        #expect(first.isValid)
        #expect(first.id == revised.id)
        #expect(first.notificationDate == now)
        #expect(
            ReminderLiveActivitySelection.select(
                events: [first], at: now.addingTimeInterval(600), supportsScheduling: true
            ).isEmpty)
    }

    @Test func beforeOnlyWindowCanEndExactlyAtTheNotification() {
        let beforeOnly = ReminderLiveActivityEvent(
            reminderID: UUID(), title: "Reminder", startDate: now.addingTimeInterval(-300),
            endDate: now, notificationDate: now)
        #expect(beforeOnly.isValid)
        #expect(
            ReminderLiveActivitySelection.select(
                events: [beforeOnly], at: now.addingTimeInterval(-1), supportsScheduling: false)
                == [beforeOnly])
        #expect(
            ReminderLiveActivitySelection.select(
                events: [beforeOnly], at: now, supportsScheduling: false
            ).isEmpty)
    }

    private func event(startOffset: TimeInterval, duration: TimeInterval)
        -> ReminderLiveActivityEvent
    {
        let start = now.addingTimeInterval(startOffset)
        return ReminderLiveActivityEvent(
            reminderID: UUID(), title: "Reminder", startDate: start,
            endDate: start.addingTimeInterval(duration)
        )
    }
}
