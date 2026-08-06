import Foundation
import Testing
@testable import NotificationManagerDomain

@Suite("Notifications.RepeatingTriggerPlanner")
struct NotificationsRepeatingTriggerPlannerTests {
    @Test func permitsEveryWhitelistedBaseRuleWithExactGregorianResidues() throws {
        let fixtures: [(ScheduleDefinition, [RepeatingTriggerComponents])] = [
            (
                schedule(rule: .daily(interval: 1)),
                [.init(timeZoneIdentifier: "Africa/Abidjan", hour: 9, minute: 30, second: 0)]
            ),
            (
                schedule(rule: .weekly(
                    interval: 1,
                    weekdaySetKind: .weekday,
                    weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday]
                )),
                [2, 3, 4, 5, 6].map {
                    .init(timeZoneIdentifier: "Africa/Abidjan", weekday: $0, hour: 9, minute: 30, second: 0)
                }
            ),
            (
                schedule(rule: .monthly(interval: 1, selector: .anchorDay)),
                [.init(timeZoneIdentifier: "Africa/Abidjan", day: 4, hour: 9, minute: 30, second: 0)]
            ),
            (
                schedule(rule: .monthly(interval: 1, selector: .dayOfMonth(15))),
                [.init(timeZoneIdentifier: "Africa/Abidjan", day: 15, hour: 9, minute: 30, second: 0)]
            ),
            (
                schedule(rule: .yearly(interval: 1, month: nil, selector: .anchorMonthDay)),
                [.init(timeZoneIdentifier: "Africa/Abidjan", month: 8, day: 4, hour: 9, minute: 30, second: 0)]
            ),
            (
                schedule(rule: .yearly(interval: 1, month: 12, selector: .dayOfMonth(31))),
                [.init(timeZoneIdentifier: "Africa/Abidjan", month: 12, day: 31, hour: 9, minute: 30, second: 0)]
            )
        ]

        for (schedule, expected) in fixtures {
            #expect(try #require(plan(schedule)).map(\.components) == expected)
        }
    }

    @Test func supportsMainAndEarlyResiduesIncludingWeekBoundary() throws {
        let daily = schedule(
            source: source(hour: 9, minute: 30, timeZoneIdentifier: "America/New_York"),
            rule: .daily(interval: 1),
            early: .init(value: 30, unit: .minutes)
        )
        let weekly = schedule(
            source: source(hour: 0, minute: 15),
            rule: .weekly(interval: 1, weekdaySetKind: .explicit, weekdays: [.monday]),
            early: .init(value: 30, unit: .minutes)
        )

        #expect(try #require(plan(daily)).map(\.components) == [
            .init(timeZoneIdentifier: "America/New_York", hour: 9, minute: 0, second: 0),
            .init(timeZoneIdentifier: "America/New_York", hour: 9, minute: 30, second: 0)
        ])
        #expect(try #require(plan(weekly)).map(\.components) == [
            .init(timeZoneIdentifier: "Africa/Abidjan", weekday: 1, hour: 23, minute: 45, second: 0),
            .init(timeZoneIdentifier: "Africa/Abidjan", weekday: 2, hour: 0, minute: 15, second: 0)
        ])
    }

    @Test func earlyOnlyCalendarOffsetsCanRemainDirect() throws {
        let daily = schedule(
            rule: .daily(interval: 1),
            early: .init(value: 1, unit: .days, mainEnabled: false)
        )
        let monthly = schedule(
            rule: .monthly(interval: 1, selector: .dayOfMonth(15)),
            early: .init(value: 1, unit: .days, mainEnabled: false)
        )
        let yearly = schedule(
            rule: .yearly(interval: 1, month: 3, selector: .dayOfMonth(15)),
            early: .init(value: 1, unit: .days, mainEnabled: false)
        )

        #expect(try #require(plan(daily)).map(\.components) == [
            .init(timeZoneIdentifier: "Africa/Abidjan", hour: 9, minute: 30, second: 0)
        ])
        #expect(try #require(plan(monthly)).map(\.components) == [
            .init(timeZoneIdentifier: "Africa/Abidjan", day: 14, hour: 9, minute: 30, second: 0)
        ])
        #expect(try #require(plan(yearly)).map(\.components) == [
            .init(timeZoneIdentifier: "Africa/Abidjan", month: 3, day: 14, hour: 9, minute: 30, second: 0)
        ])
    }

    @Test func startNowAndPastAreDirectButFutureStartRemainsRolling() {
        let past = schedule(source: source(day: 4, hour: 9), rule: .daily(interval: 1))
        let now = schedule(source: source(day: 6, hour: 12, minute: 0), rule: .daily(interval: 1))
        let future = schedule(source: source(day: 6, hour: 12, minute: 1), rule: .daily(interval: 1))

        #expect(plan(past) != nil)
        #expect(plan(now) != nil)
        #expect(plan(future) == nil)
    }

    @Test func finiteEndAndEveryNonWhitelistedRuleRemainRolling() {
        let rolling: [ScheduleDefinition] = [
            schedule(rule: .none),
            schedule(rule: .hourly(interval: 1)),
            schedule(rule: .daily(interval: 2)),
            schedule(rule: .weekly(interval: 2, weekdaySetKind: .explicit, weekdays: [.monday])),
            schedule(rule: .monthly(interval: 3, selector: .dayOfMonth(4))),
            schedule(rule: .yearly(interval: 2, month: 8, selector: .dayOfMonth(4))),
            schedule(rule: .monthly(interval: 1, selector: .lastDay)),
            schedule(rule: .monthly(interval: 1, selector: .ordinalWeekday(ordinal: 2, weekday: .monday))),
            schedule(rule: .monthly(interval: 1, selector: .ordinalDaySet(ordinal: 1, daySet: .weekday))),
            schedule(rule: .yearly(interval: 1, month: 8, selector: .lastDay)),
            schedule(rule: .yearly(interval: 1, month: 8, selector: .ordinalWeekday(ordinal: -1, weekday: .friday))),
            schedule(
                rule: .daily(interval: 1),
                end: .onDate(.init(year: 2026, month: 12, day: 31))
            )
        ]

        for schedule in rolling {
            #expect(plan(schedule) == nil)
        }
    }

    @Test func dynamicOffsetResiduesRemainRollingWhileStableDSTZoneResiduesStayDirect() throws {
        let dynamicDST = schedule(
            source: source(hour: 3, minute: 30, timeZoneIdentifier: "America/New_York"),
            rule: .daily(interval: 1),
            early: .init(value: 2, unit: .hours, mainEnabled: false)
        )
        let dynamicMonth = schedule(
            source: source(day: 1),
            rule: .monthly(interval: 1, selector: .dayOfMonth(1)),
            early: .init(value: 1, unit: .days, mainEnabled: false)
        )
        let dynamicLeapYear = schedule(
            source: source(month: 3, day: 1),
            rule: .yearly(interval: 1, month: 3, selector: .dayOfMonth(1)),
            early: .init(value: 1, unit: .days, mainEnabled: false)
        )
        let stableDST = schedule(
            source: source(hour: 9, minute: 30, timeZoneIdentifier: "America/New_York"),
            rule: .daily(interval: 1),
            early: .init(value: 5, unit: .minutes, mainEnabled: false)
        )

        #expect(plan(dynamicDST) == nil)
        #expect(plan(dynamicMonth) == nil)
        #expect(plan(dynamicLeapYear) == nil)
        #expect(try #require(plan(stableDST)).map(\.components) == [
            .init(timeZoneIdentifier: "America/New_York", hour: 9, minute: 25, second: 0)
        ])
    }

    @Test func crossOccurrenceCollisionsRemainRolling() {
        let dailyMainAndPreviousEarly = schedule(
            rule: .daily(interval: 1),
            early: .init(value: 1, unit: .days)
        )
        let weeklyMainAndPreviousEarly = schedule(
            rule: .weekly(
                interval: 1,
                weekdaySetKind: .explicit,
                weekdays: [.monday, .tuesday]
            ),
            early: .init(value: 1, unit: .days)
        )

        #expect(plan(dailyMainAndPreviousEarly) == nil)
        #expect(plan(weeklyMainAndPreviousEarly) == nil)
    }

    @Test func duplicateEffectiveReasonsAreSetLikeAndDoNotDuplicateCandidates() throws {
        let base = BaseOccurrence(
            instant: fixtureDate("2026-08-07T09:30:00Z"),
            sourceComponents: DateComponents(
                calendar: Calendar(identifier: .gregorian),
                timeZone: TimeZone(identifier: "UTC"),
                year: 2026,
                month: 8,
                day: 7,
                hour: 9,
                minute: 30,
                second: 0
            )
        )
        let reason = EffectiveAlert(kind: .main, baseOccurrence: base, alertInstant: base.instant)
        let physical = PhysicalNotification(
            reminderID: reminderID,
            alertInstant: base.instant,
            reasons: [reason, reason]
        )

        let candidates = try #require(plan(schedule(rule: .daily(interval: 1)), physical: [physical]))

        #expect(candidates.count == 1)
        #expect(candidates[0].contributors.count == 1)
        #expect(candidates[0].contributors[0].kind == .main)
    }

    @Test func observedCrossOccurrenceCollisionRemainsRollingButDuplicateOccurrenceDoesNot() {
        let first = BaseOccurrence(
            instant: fixtureDate("2026-08-07T09:30:00Z"),
            sourceComponents: DateComponents(year: 2026, month: 8, day: 7, hour: 9, minute: 30)
        )
        let second = BaseOccurrence(
            instant: fixtureDate("2026-08-08T09:30:00Z"),
            sourceComponents: DateComponents(year: 2026, month: 8, day: 8, hour: 9, minute: 30)
        )
        let alert = fixtureDate("2026-08-07T08:30:00Z")
        let physical = PhysicalNotification(
            reminderID: reminderID,
            alertInstant: alert,
            reasons: [
                .init(kind: .early, baseOccurrence: first, alertInstant: alert),
                .init(kind: .early, baseOccurrence: second, alertInstant: alert)
            ]
        )

        #expect(plan(
            schedule(rule: .daily(interval: 1), early: .init(value: 1, unit: .hours, mainEnabled: false)),
            physical: [physical]
        ) == nil)
    }

    @Test func contributorAndCandidateOrderingIsDeterministic() throws {
        let definition = schedule(
            rule: .weekly(
                interval: 1,
                weekdaySetKind: .weekend,
                weekdays: [.saturday, .sunday]
            ),
            early: .init(value: 5, unit: .minutes)
        )

        let first = try #require(plan(definition))
        let second = try #require(plan(definition))

        #expect(first == second)
        #expect(first.map(\.components.weekday) == [1, 1, 7, 7])
        #expect(first.map(\.components.minute) == [25, 30, 25, 30])
    }

    private let planner = RepeatingTriggerPlanner()
    private let reminderID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let evaluationNow = fixtureDate("2026-08-06T12:00:00Z")

    private func plan(
        _ schedule: ScheduleDefinition,
        physical: [PhysicalNotification] = []
    ) -> [RepeatingTriggerCandidate]? {
        planner.plan(RepeatingTriggerPlanningInput(
            schedule: schedule,
            evaluationNow: evaluationNow,
            physicalNotifications: physical,
            environment: .foundation
        ))
    }

    private func schedule(
        source: SourceWallClock? = nil,
        rule: RepeatRule,
        end: RepeatEnd = .never,
        early: EarlyReminder? = nil
    ) -> ScheduleDefinition {
        ScheduleDefinition(
            source: source ?? self.source(),
            rule: rule,
            end: end,
            early: early
        )
    }

    private func source(
        year: Int = 2026,
        month: Int = 8,
        day: Int = 4,
        hour: Int = 9,
        minute: Int = 30,
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

private func fixtureDate(_ value: String) -> Date {
    guard let date = ISO8601DateFormatter().date(from: value) else {
        preconditionFailure("Invalid ISO-8601 fixture: \(value)")
    }
    return date
}
