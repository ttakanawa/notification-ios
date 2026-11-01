import Foundation
import NotificationManagerDomain
import NotificationManagerWidgetSupport
import Testing

@testable import NotificationManager

@Suite("ReminderLiveActivityProjector")
struct ReminderLiveActivityProjectorTests {
    private let now = Date(timeIntervalSince1970: 1_789_204_500)

    @Test func optionalRangeAndDisabledRemindersDoNotCreateActivities() throws {
        let events = try project([
            reminder(duration: nil), reminder(duration: 3_600, enabled: false),
            reminder(duration: -60)
        ])
        #expect(events.isEmpty)
        #expect(try project([reminder(duration: 3_600)], enabled: false).isEmpty)
    }

    @Test func anOngoingRangeIsRecoveredAfterItsNotificationFired() throws {
        let reminder = reminder(duration: 3_600)
        let events = try project([reminder])
        #expect(events.count == 1)
        #expect(events.first?.reminderID == reminder.id)
        #expect(events.first?.startDate == now.addingTimeInterval(-900))
        #expect(events.first?.endDate == now.addingTimeInterval(2_700))
    }

    @Test func endIsExclusiveAndEightHourActivitiesAreNotRestarted() throws {
        #expect(try project([reminder(duration: 900)]).isEmpty)
        #expect(try project([reminder(duration: 86_400, startOffset: -28_800)]).isEmpty)
        let current = try project([reminder(duration: 86_400)])
        #expect(current.first?.activityEndDate == now.addingTimeInterval(27_900))
    }

    @Test func actualRangeEndStillRefreshesTheListAfterTheActivityCap() throws {
        let longRange = reminder(duration: 86_400, startOffset: -28_800)
        let projector = ReminderLiveActivityProjector()
        #expect(try project([longRange]).isEmpty)
        #expect(
            try projector.nextRangeEnd(reminders: [longRange], after: now)
                == now.addingTimeInterval(57_600))
        #expect(
            try projector.nextRangeEnd(
                reminders: [longRange], after: now.addingTimeInterval(57_600)) == nil)
    }

    @Test func repeatedRangesUseBaseOccurrencesAndKeepABoundedQueue() throws {
        let events = try project([
            reminder(
                duration: 1_800, rule: .daily(interval: 1), early: .init(value: 5, unit: .minutes))
        ])
        #expect(events.count == ReminderLiveActivitySelection.maximumActivities)
        #expect(events.map { $0.endDate.timeIntervalSince($0.startDate) } == [1_800, 1_800, 1_800])
        #expect(events.first?.startDate == now.addingTimeInterval(-900))
        #expect(events[1].startDate == now.addingTimeInterval(85_500))
    }

    @Test func earlyOnlyNotificationsStillStartTheRangeAtItsBaseTime() throws {
        let events = try project([
            reminder(duration: 3_600, early: .init(value: 1, unit: .hours, mainEnabled: false))
        ])
        #expect(events.first?.startDate == now.addingTimeInterval(-900))
    }

    @Test func finalRepeatedOccurrenceRemainsVisibleUntilItsEnd() throws {
        let base = reminder(duration: 3_600)
        guard case .valid(let schedule, _, _) = base.schedule else { return }
        let final = reminder(
            duration: 3_600, rule: .daily(interval: 1),
            repeatEnd: .onDate(
                .init(
                    year: schedule.source.year, month: schedule.source.month,
                    day: schedule.source.day))
        )
        #expect(try project([final]).count == 1)
    }

    @Test func futureQueueHasStableOrderRegardlessOfInputOrder() throws {
        let first = reminder(duration: 3_600, startOffset: 600)
        let second = reminder(duration: 3_600, startOffset: 1_200)
        #expect(try project([second, first]).map(\.reminderID) == [first.id, second.id])
    }

    @MainActor
    @Test func publicationDoesNotShowSchedulingForAnOngoingFinalRange() {
        let currentDate = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: currentDate)
        let schedule = ScheduleDefinition(
            source: .init(
                year: parts.year ?? 2026, month: parts.month ?? 1, day: parts.day ?? 1,
                hour: parts.hour ?? 0, minute: parts.minute ?? 0,
                timeZoneIdentifier: "Africa/Abidjan"),
            rule: .none, end: .never, early: nil, durationSeconds: 3_600
        )
        let ongoing = ReminderSnapshot(
            id: UUID(), title: "Ongoing range", notes: nil, urlString: nil, enabled: true,
            schedule: .valid(schedule, sourceVersion: 3, originalData: Data()), tagIDs: [],
            createdAt: currentDate, updatedAt: currentDate
        )
        let state = DeviceSchedulingStateSnapshot(
            generation: 1, reconcileInProgressOrQueued: false, globalFailure: nil,
            deviceNotificationsEnabled: true,
            authorization: .init(state: .allowed, diagnostic: nil), outcomes: [:],
            scheduledThrough: [:],
            materializedKinds: [:], pendingOrAddedIdentifiers: []
        )
        let environment = AppEnvironment()
        environment.publish(.init(reminders: [ongoing], tags: []), deviceState: state)

        #expect(environment.listModel.items.first?.lifecycleStatus == .active)
        #expect(environment.listModel.items.first?.deviceSchedulingStatus == .notApplicable)
    }

    private func project(
        _ reminders: [ReminderSnapshot], enabled: Bool = true
    ) throws -> [ReminderLiveActivityEvent] {
        try ReminderLiveActivityProjector().project(
            reminders: reminders, notificationsEnabled: enabled, now: now)
    }

    private func reminder(
        duration: Int?, enabled: Bool = true, startOffset: TimeInterval = -900,
        rule: RepeatRule = .none, early: EarlyReminder? = nil, repeatEnd: RepeatEnd = .never
    ) -> ReminderSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let date = now.addingTimeInterval(startOffset)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let schedule = ScheduleDefinition(
            source: .init(
                year: parts.year ?? 2026, month: parts.month ?? 1, day: parts.day ?? 1,
                hour: parts.hour ?? 0, minute: parts.minute ?? 0,
                timeZoneIdentifier: "Africa/Abidjan"),
            rule: rule, end: repeatEnd, early: early, durationSeconds: duration
        )
        return ReminderSnapshot(
            id: UUID(), title: "Time range", notes: nil, urlString: nil, enabled: enabled,
            schedule: .valid(schedule, sourceVersion: 3, originalData: Data()), tagIDs: [],
            createdAt: date.addingTimeInterval(-3_600), updatedAt: date
        )
    }
}
