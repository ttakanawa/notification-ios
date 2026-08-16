import Foundation
import Testing

@testable import NotificationManagerDomain

@Suite("NextNotificationProviderTests")
struct NextNotificationProviderTests {
    @Test func oneShotMinutesAndHoursUseFixedDurations() throws {
        let minuteResult = try notifications(
            schedule(source: source(hour: 12), early: .init(value: 5, unit: .minutes)),
            after: date("2026-08-04T00:00:00Z")
        )
        let hourResult = try notifications(
            schedule(source: source(hour: 12), early: .init(value: 2, unit: .hours)),
            after: date("2026-08-04T00:00:00Z")
        )

        #expect(
            minuteResult.notifications.map(\.alertInstant) == [
                date("2026-08-04T11:55:00Z"), date("2026-08-04T12:00:00Z")
            ])
        #expect(
            hourResult.notifications.map(\.alertInstant) == [
                date("2026-08-04T10:00:00Z"), date("2026-08-04T12:00:00Z")
            ])
    }

    @Test func dailyMinutesAndHoursUseFixedDurations() throws {
        let minuteResult = try notifications(
            schedule(
                source: source(hour: 12),
                rule: .daily(interval: 1),
                early: .init(value: 5, unit: .minutes, mainEnabled: false)
            ),
            after: date("2026-08-04T00:00:00Z"),
            limit: 2
        )
        let hourResult = try notifications(
            schedule(
                source: source(hour: 12),
                rule: .daily(interval: 1),
                early: .init(value: 2, unit: .hours, mainEnabled: false)
            ),
            after: date("2026-08-04T00:00:00Z"),
            limit: 2
        )

        #expect(
            minuteResult.notifications.map(\.alertInstant) == [
                date("2026-08-04T11:55:00Z"), date("2026-08-05T11:55:00Z")
            ])
        #expect(
            hourResult.notifications.map(\.alertInstant) == [
                date("2026-08-04T10:00:00Z"), date("2026-08-05T10:00:00Z")
            ])
    }

    @Test func oneShotAndDailyDaysAndWeeksUseSourceCalendar() throws {
        let oneShot = try notifications(
            schedule(
                source: source(
                    year: 2026,
                    month: 11,
                    day: 1,
                    hour: 9,
                    minute: 30,
                    timeZoneIdentifier: "America/New_York"
                ),
                early: .init(value: 1, unit: .days, mainEnabled: false)
            ),
            after: date("2026-10-30T00:00:00Z")
        )
        let daily = try notifications(
            schedule(
                source: source(
                    year: 2026,
                    month: 11,
                    day: 1,
                    hour: 9,
                    minute: 30,
                    timeZoneIdentifier: "America/New_York"
                ),
                rule: .daily(interval: 1),
                early: .init(value: 1, unit: .weeks, mainEnabled: false)
            ),
            after: date("2026-10-24T00:00:00Z"),
            limit: 2
        )

        #expect(oneShot.notifications.map(\.alertInstant) == [date("2026-10-31T13:30:00Z")])
        #expect(
            daily.notifications.map(\.alertInstant) == [
                date("2026-10-25T13:30:00Z"), date("2026-10-26T13:30:00Z")
            ])
    }

    @Test func hourlyAllEarlyUnitsUseFixedElapsedDurations() throws {
        let units: [(EarlyReminderUnit, Int, Date)] = [
            (.minutes, 30, date("2026-11-01T14:00:00Z")),
            (.hours, 2, date("2026-11-01T12:30:00Z")),
            (.days, 1, date("2026-10-31T14:30:00Z")),
            (.weeks, 1, date("2026-10-25T14:30:00Z"))
        ]

        for (unit, value, expected) in units {
            let result = try notifications(
                schedule(
                    source: source(
                        year: 2026,
                        month: 11,
                        day: 1,
                        hour: 9,
                        minute: 30,
                        timeZoneIdentifier: "America/New_York"
                    ),
                    rule: .hourly(interval: 1),
                    early: .init(value: value, unit: unit, mainEnabled: false)
                ),
                after: expected.addingTimeInterval(-1),
                limit: 1
            )

            #expect(result.notifications.first?.alertInstant == expected)
        }
    }

    @Test func supportsEarlyOnlyEarlyAndMainAndClearedEarlyMain() throws {
        let earlyOnly = try notifications(
            schedule(
                source: source(hour: 10),
                early: .init(value: 5, unit: .minutes, mainEnabled: false)
            ),
            after: date("2026-08-04T00:00:00Z")
        )
        let both = try notifications(
            schedule(source: source(hour: 10), early: .init(value: 5, unit: .minutes)),
            after: date("2026-08-04T00:00:00Z")
        )
        let cleared = try notifications(
            schedule(source: source(hour: 10), early: nil),
            after: date("2026-08-04T00:00:00Z")
        )

        #expect(earlyOnly.notifications.map { $0.reasons.map(\.kind) } == [[.early]])
        #expect(both.notifications.map { $0.reasons.map(\.kind) } == [[.early], [.main]])
        #expect(cleared.notifications.map { $0.reasons.map(\.kind) } == [[.main]])
    }

    @Test func skipsPastEarlyWithoutCatchUpAndKeepsFutureMain() throws {
        let result = try notifications(
            schedule(source: source(hour: 10), early: .init(value: 1, unit: .hours)),
            after: date("2026-08-04T09:30:00Z")
        )

        #expect(result.notifications.map(\.alertInstant) == [date("2026-08-04T10:00:00Z")])
        #expect(result.notifications[0].reasons.map(\.kind) == [.main])
        #expect(result.didSkipPastEarly)
    }

    @Test func oneShotEarlyOnlyWithPastAlertHasNoFutureNotification() throws {
        let result = try notifications(
            schedule(
                source: source(hour: 10),
                early: .init(value: 1, unit: .hours, mainEnabled: false)
            ),
            after: date("2026-08-04T09:30:00Z")
        )

        #expect(result.notifications.isEmpty)
        #expect(result.exhausted)
        #expect(result.didSkipPastEarly)
    }

    @Test func repeatingEarlyOnlyAdvancesPastSkippedAlert() throws {
        let result = try notifications(
            schedule(
                source: source(hour: 10),
                rule: .daily(interval: 1),
                early: .init(value: 1, unit: .hours, mainEnabled: false)
            ),
            after: date("2026-08-04T09:30:00Z"),
            limit: 2
        )

        #expect(
            result.notifications.map(\.alertInstant) == [
                date("2026-08-05T09:00:00Z"), date("2026-08-06T09:00:00Z")
            ])
        #expect(result.didSkipPastEarly)
        #expect(!result.exhausted)
    }

    @Test func finiteEndIsInclusiveAndThenExhausts() throws {
        let result = try notifications(
            schedule(
                source: source(year: 2026, month: 8, day: 1, hour: 10),
                rule: .daily(interval: 1),
                end: .onDate(.init(year: 2026, month: 8, day: 3)),
                early: nil
            ),
            after: date("2026-08-02T10:00:00Z"),
            limit: 3
        )

        #expect(result.notifications.map(\.alertInstant) == [date("2026-08-03T10:00:00Z")])
        #expect(result.exhausted)
    }

    @Test func alertAtEvaluationNowIsPastAndFreshEvaluationDoesNotCatchUp() throws {
        let schedule = schedule(source: source(hour: 10), early: nil)
        let before = try notifications(schedule, after: date("2026-08-04T09:59:59Z"))
        let equal = try notifications(schedule, after: date("2026-08-04T10:00:00Z"))

        #expect(before.notifications.map(\.alertInstant) == [date("2026-08-04T10:00:00Z")])
        #expect(equal.notifications.isEmpty)
        #expect(equal.exhausted)
    }

    @Test func limitZeroDoesNotConsumeAndPreviewDefaultsAndClampsToThree() throws {
        let recurring = schedule(
            source: source(hour: 10),
            rule: .daily(interval: 1),
            early: nil
        )
        let zero = try notifications(recurring, after: date("2026-08-04T00:00:00Z"), limit: 0)
        let defaultResult = try provider.nextPhysicalNotifications(
            for: reminderID,
            schedule: recurring,
            after: date("2026-08-04T00:00:00Z"),
            environment: .foundation
        )
        let oversized = try notifications(
            recurring,
            after: date("2026-08-04T00:00:00Z"),
            limit: 100
        )

        #expect(zero.notifications.isEmpty)
        #expect(!zero.exhausted)
        #expect(zero.observedFoundationResultCount == 0)
        #expect(defaultResult.notifications.count == 3)
        #expect(oversized.notifications.count == 3)
    }

    @Test func mergesDailyMainWithPreviousOccurrenceEarly() throws {
        let result = try notifications(
            schedule(
                source: source(hour: 9, minute: 30),
                rule: .daily(interval: 1),
                early: .init(value: 1, unit: .days)
            ),
            after: date("2026-08-04T00:00:00Z"),
            limit: 3
        )

        #expect(result.notifications[0].alertInstant == date("2026-08-04T09:30:00Z"))
        #expect(result.notifications[0].reasons.map(\.kind) == [.main, .early])
        #expect(result.notifications[0].primaryReason.kind == .main)
        #expect(
            result.notifications[0].contributingBaseOccurrences.map(\.instant) == [
                date("2026-08-04T09:30:00Z"), date("2026-08-05T09:30:00Z")
            ])
    }

    @Test func mergesHourlyOneDayCollisionAndKeepsStableReasonOrder() throws {
        let result = try notifications(
            schedule(
                source: source(hour: 9, minute: 30),
                rule: .hourly(interval: 1),
                early: .init(value: 1, unit: .days)
            ),
            after: date("2026-08-04T09:00:00Z"),
            limit: 1
        )

        #expect(result.notifications[0].alertInstant == date("2026-08-04T09:30:00Z"))
        #expect(result.notifications[0].reasons.map(\.kind) == [.main, .early])
        #expect(
            result.notifications[0].contributingBaseOccurrences.map(\.instant) == [
                date("2026-08-04T09:30:00Z"), date("2026-08-05T09:30:00Z")
            ])
        #expect(result.observedFoundationResultCount <= 1_024)
    }

    @Test(.timeLimit(.minutes(1)))
    func maximumHourlyEarlyOffsetWithMainUsesBoundedStreams() throws {
        let result = try notifications(
            schedule(
                source: source(hour: 9, minute: 30),
                rule: .hourly(interval: 1),
                early: .init(value: 9_999, unit: .weeks)
            ),
            after: date("2026-08-04T09:00:00Z"),
            limit: 1
        )

        #expect(result.notifications.count == 1)
        #expect(result.notifications[0].alertInstant == date("2026-08-04T09:30:00Z"))
        #expect(result.notifications[0].reasons.map(\.kind) == [.main, .early])
        #expect(result.observedFoundationResultCount > 0)
        #expect(result.observedFoundationResultCount <= 1_024)
    }

    @Test func earlyOnlyCollisionUsesFirstBaseOccurrenceAsPrimary() throws {
        let first = BaseOccurrence(
            instant: date("2026-08-04T10:00:00Z"),
            sourceComponents: DateComponents(year: 2026, month: 8, day: 4, hour: 10)
        )
        let second = BaseOccurrence(
            instant: date("2026-08-05T10:00:00Z"),
            sourceComponents: DateComponents(year: 2026, month: 8, day: 5, hour: 10)
        )
        let physical = PhysicalNotification(
            reminderID: reminderID,
            alertInstant: date("2026-08-04T09:00:00Z"),
            reasons: [
                EffectiveAlert(
                    kind: .early, baseOccurrence: first, alertInstant: date("2026-08-04T09:00:00Z")),
                EffectiveAlert(
                    kind: .early, baseOccurrence: second, alertInstant: date("2026-08-04T09:00:00Z")
                )
            ]
        )

        #expect(physical.primaryReason.baseOccurrence == first)
        #expect(physical.reasons.map(\.baseOccurrence) == [first, second])
    }

    @Test func farPastMaximumOffsetsObserveAtMost1024FoundationResults() throws {
        let result = try notifications(
            schedule(
                source: source(
                    year: 1_900,
                    month: 1,
                    day: 1,
                    hour: 0,
                    timeZoneIdentifier: "Asia/Manila"
                ),
                rule: .daily(interval: 9_999),
                early: .init(value: 9_999, unit: .weeks, mainEnabled: false)
            ),
            after: utcDate(year: 2_500, month: 1, day: 1),
            limit: 3
        )

        #expect(result.notifications.count == 3)
        #expect(result.observedFoundationResultCount > 0)
        #expect(result.observedFoundationResultCount <= 1_024)
    }

    @Test func rejectsDomainInvalidPublicScheduleBeforeRecurrenceMapping() {
        let invalid = schedule(
            source: source(),
            rule: .weekly(
                interval: 1,
                weekdaySetKind: .weekday,
                weekdays: [.monday, .tuesday]
            ),
            early: nil
        )

        #expect(throws: NextNotificationProviderError.invalidSchedule([.invalidWeekdaySet])) {
            try notifications(invalid, after: date("2026-08-04T00:00:00Z"))
        }
    }

    private let provider = NextNotificationProvider()
    private let reminderID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    private func notifications(
        _ schedule: ScheduleDefinition,
        after evaluationNow: Date,
        limit: Int = 3
    ) throws -> NextNotificationResult {
        try provider.nextPhysicalNotifications(
            for: reminderID,
            schedule: schedule,
            after: evaluationNow,
            limit: limit,
            environment: .foundation
        )
    }

    private func schedule(
        source: SourceWallClock,
        rule: RepeatRule = .none,
        end: RepeatEnd = .never,
        early: EarlyReminder?
    ) -> ScheduleDefinition {
        ScheduleDefinition(source: source, rule: rule, end: end, early: early)
    }

    private func source(
        year: Int = 2026,
        month: Int = 8,
        day: Int = 4,
        hour: Int = 9,
        minute: Int = 0,
        timeZoneIdentifier: String = "Africa/Abidjan"
    ) -> SourceWallClock {
        SourceWallClock(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }
}

private func date(_ value: String) -> Date {
    guard let date = ISO8601DateFormatter().date(from: value) else {
        preconditionFailure("Invalid ISO-8601 fixture: \(value)")
    }
    return date
}

private func utcDate(year: Int, month: Int, day: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    guard let utc = TimeZone(secondsFromGMT: 0) else {
        preconditionFailure("Foundation must provide the zero-offset time zone")
    }
    calendar.timeZone = utc
    guard let result = calendar.date(from: DateComponents(year: year, month: month, day: day))
    else {
        preconditionFailure("Invalid UTC fixture")
    }
    return result
}
