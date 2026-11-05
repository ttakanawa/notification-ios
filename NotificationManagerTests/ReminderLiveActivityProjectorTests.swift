import Foundation
import NotificationManagerDomain
import NotificationManagerWidgetSupport
import SwiftUI
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

    @Test func fiveMinutesBeforeAndTenMinutesAfterUseAnIndependentNotificationAnchor() throws {
        let source = reminder(
            duration: nil, startOffset: 300,
            window: .init(beforeSeconds: 300, afterSeconds: 600))
        let event = try #require(try project([source]).first)

        #expect(event.startDate == now)
        #expect(event.notificationDate == now.addingTimeInterval(300))
        #expect(event.endDate == now.addingTimeInterval(900))
        #expect(
            ReminderLiveActivitySelection.select(
                events: [event], at: now, supportsScheduling: false) == [event])
        let before = ReminderLiveActivityTimePresentation.countdown(
            startDate: event.startDate, notificationDate: event.notificationDate
        ).locale(Locale(identifier: "ja_JP"))
        let after = ReminderLiveActivityTimePresentation.elapsedInterval(
            since: event.notificationDate
        )
        #expect(String(before.format(now).characters) + "前" == "5:00前")
        #expect(after.lowerBound == now.addingTimeInterval(300))
        #expect(after.contains(event.activityEndDate.addingTimeInterval(60)))
        #expect(event.activityEndDate == now.addingTimeInterval(900))
    }

    @Test func appRelaunchSixMinutesAfterTheNotificationRecoversItsDisplayWindow() throws {
        let source = reminder(
            duration: nil, startOffset: -360,
            window: .init(beforeSeconds: 300, afterSeconds: 600))
        let event = try #require(try project([source]).first)

        #expect(event.startDate == now.addingTimeInterval(-660))
        #expect(event.notificationDate == now.addingTimeInterval(-360))
        #expect(event.endDate == now.addingTimeInterval(240))
        #expect(
            try ReminderLiveActivityProjector().project(
                reminders: [source], notificationsEnabled: true,
                now: now.addingTimeInterval(240)
            ).isEmpty)
    }

    @Test func beforeAfterOffsetsDoNotMoveMainOrEarlyNotificationTimes() throws {
        let source = reminder(
            duration: nil, startOffset: 300, rule: .daily(interval: 1),
            early: .init(value: 1, unit: .hours, mainEnabled: false),
            window: .init(beforeSeconds: 300, afterSeconds: 600))
        let events = try project([source])

        #expect(events.count == ReminderLiveActivitySelection.maximumActivities)
        #expect(events[0].notificationDate == now.addingTimeInterval(300))
        #expect(events[0].startDate == now)
        #expect(events[1].notificationDate == now.addingTimeInterval(86_700))
        #expect(events.allSatisfy { $0.notificationDate.timeIntervalSince($0.startDate) == 300 })
        #expect(events.allSatisfy { $0.endDate.timeIntervalSince($0.notificationDate) == 600 })
    }

    @Test func displayOffsetsPreserveElapsedTimeAcrossTheDaylightSavingJump() throws {
        let schedule = ScheduleDefinition(
            source: .init(
                year: 2026, month: 3, day: 8, hour: 1, minute: 58,
                timeZoneIdentifier: "America/New_York"),
            rule: .none, end: .never, early: nil,
            liveActivityWindow: .init(beforeSeconds: 300, afterSeconds: 600))
        let clock = try #require(ISO8601DateFormatter().date(from: "2026-03-08T06:55:00Z"))
        let reminder = ReminderSnapshot(
            id: UUID(), title: "DST", notes: nil, urlString: nil, enabled: true,
            schedule: .valid(schedule, sourceVersion: 4, originalData: Data()), tagIDs: [],
            createdAt: clock, updatedAt: clock)
        let events = try ReminderLiveActivityProjector().project(
            reminders: [reminder], notificationsEnabled: true, now: clock)
        let event = try #require(events.first)
        let resolved = try SourceWallClockResolver().resolve(
            schedule.source, environment: FoundationRecurrenceEnvironment())

        #expect(event.notificationDate == resolved)
        #expect(event.notificationDate.timeIntervalSince(event.startDate) == 300)
        #expect(event.endDate.timeIntervalSince(event.notificationDate) == 600)
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "HH:mm"
        #expect(formatter.string(from: event.startDate) == "01:53")
        #expect(formatter.string(from: event.endDate) == "03:08")
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
        rule: RepeatRule = .none, early: EarlyReminder? = nil, repeatEnd: RepeatEnd = .never,
        window: LiveActivityWindow? = nil
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
            rule: rule, end: repeatEnd, early: early, durationSeconds: duration,
            liveActivityWindow: window
        )
        return ReminderSnapshot(
            id: UUID(), title: "Time range", notes: nil, urlString: nil, enabled: enabled,
            schedule: .valid(schedule, sourceVersion: 3, originalData: Data()), tagIDs: [],
            createdAt: date.addingTimeInterval(-3_600), updatedAt: date
        )
    }
}
