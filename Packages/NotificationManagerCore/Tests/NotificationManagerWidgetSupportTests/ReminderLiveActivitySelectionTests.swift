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
                endDate: Date(timeIntervalSince1970: .infinity))
        ]

        #expect(
            ReminderLiveActivitySelection.select(events: invalid, at: now, supportsScheduling: true)
                .isEmpty)
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
