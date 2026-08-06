import Foundation
import Testing
@testable import NotificationManagerDomain

@Suite("Recurrence.FoundationRecurrenceEngine")
struct FoundationRecurrenceEngineTests {
    @Test func oneShotProducesOnlyAnchorInsideHalfOpenRange() throws {
        let schedule = schedule(source: source(day: 2), rule: .none)

        let containing = try instants(
            schedule,
            in: isoDate("2026-08-01T00:00:00Z")..<isoDate("2026-08-03T00:00:00Z")
        )
        let endingAtAnchor = try instants(
            schedule,
            in: isoDate("2026-08-01T00:00:00Z")..<isoDate("2026-08-02T09:30:00Z")
        )

        #expect(containing == [isoDate("2026-08-02T09:30:00Z")])
        #expect(endingAtAnchor.isEmpty)
    }

    @Test func dailyIntervalIncludesMatchingAnchor() throws {
        let values = try instants(
            schedule(source: source(day: 1), rule: .daily(interval: 2)),
            in: isoDate("2026-08-01T09:30:00Z")..<isoDate("2026-08-07T09:30:00Z")
        )

        #expect(values == [
            isoDate("2026-08-01T09:30:00Z"),
            isoDate("2026-08-03T09:30:00Z"),
            isoDate("2026-08-05T09:30:00Z")
        ])
    }

    @Test func weeklyIntervalMapsWeekdayResidue() throws {
        let values = try instants(
            schedule(
                source: source(year: 2026, month: 8, day: 3),
                rule: .weekly(interval: 2, weekdaySetKind: .explicit, weekdays: [.monday])
            ),
            in: isoDate("2026-08-03T00:00:00Z")..<isoDate("2026-09-15T00:00:00Z")
        )

        #expect(values == [
            isoDate("2026-08-03T09:30:00Z"),
            isoDate("2026-08-17T09:30:00Z"),
            isoDate("2026-08-31T09:30:00Z"),
            isoDate("2026-09-14T09:30:00Z")
        ])
    }

    @Test func weekdaysAndWeekendsUseSourceZoneWeekdays() throws {
        let weekdays = try instants(
            schedule(
                source: source(year: 2026, month: 8, day: 3),
                rule: .weekly(
                    interval: 1,
                    weekdaySetKind: .weekday,
                    weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday]
                )
            ),
            in: isoDate("2026-08-03T00:00:00Z")..<isoDate("2026-08-10T00:00:00Z")
        )
        let weekends = try instants(
            schedule(
                source: source(year: 2026, month: 8, day: 1),
                rule: .weekly(
                    interval: 1,
                    weekdaySetKind: .weekend,
                    weekdays: [.saturday, .sunday]
                )
            ),
            in: isoDate("2026-08-01T00:00:00Z")..<isoDate("2026-08-10T00:00:00Z")
        )

        #expect(weekdays == [3, 4, 5, 6, 7].map { isoDate("2026-08-0\($0)T09:30:00Z") })
        #expect(weekends == [
            isoDate("2026-08-01T09:30:00Z"),
            isoDate("2026-08-02T09:30:00Z"),
            isoDate("2026-08-08T09:30:00Z"),
            isoDate("2026-08-09T09:30:00Z")
        ])
    }

    @Test func monthlyDayOfMonthSkipsMonthsWithoutThatDay() throws {
        let values = try instants(
            schedule(
                source: source(year: 2027, month: 1, day: 31),
                rule: .monthly(interval: 1, selector: .dayOfMonth(31))
            ),
            in: isoDate("2027-01-01T00:00:00Z")..<isoDate("2027-06-01T00:00:00Z")
        )

        #expect(values == [
            isoDate("2027-01-31T09:30:00Z"),
            isoDate("2027-03-31T09:30:00Z"),
            isoDate("2027-05-31T09:30:00Z")
        ])
    }

    @Test func monthlyAnchorDayAndLastDayMapDirectly() throws {
        let anchorDay = try instants(
            schedule(
                source: source(year: 2027, month: 1, day: 30),
                rule: .monthly(interval: 2, selector: .anchorDay)
            ),
            in: isoDate("2027-01-01T00:00:00Z")..<isoDate("2027-08-01T00:00:00Z")
        )
        let lastDay = try instants(
            schedule(
                source: source(year: 2027, month: 1, day: 31),
                rule: .monthly(interval: 1, selector: .lastDay)
            ),
            in: isoDate("2027-01-01T00:00:00Z")..<isoDate("2027-04-01T00:00:00Z")
        )

        #expect(anchorDay == [
            isoDate("2027-01-30T09:30:00Z"),
            isoDate("2027-03-30T09:30:00Z"),
            isoDate("2027-05-30T09:30:00Z"),
            isoDate("2027-07-30T09:30:00Z")
        ])
        #expect(lastDay == [
            isoDate("2027-01-31T09:30:00Z"),
            isoDate("2027-02-28T09:30:00Z"),
            isoDate("2027-03-31T09:30:00Z")
        ])
    }

    @Test func monthlyFifthAndReverseWeekdaysSkipMissingOccurrences() throws {
        let fifthMonday = try instants(
            schedule(
                source: source(year: 2023, month: 1, day: 30),
                rule: .monthly(
                    interval: 1,
                    selector: .ordinalWeekday(ordinal: 5, weekday: .monday)
                )
            ),
            in: isoDate("2023-01-01T00:00:00Z")..<isoDate("2023-08-01T00:00:00Z")
        )
        let lastFriday = try instants(
            schedule(
                source: source(year: 2023, month: 1, day: 27),
                rule: .monthly(
                    interval: 1,
                    selector: .ordinalWeekday(ordinal: -1, weekday: .friday)
                )
            ),
            in: isoDate("2023-01-01T00:00:00Z")..<isoDate("2023-04-01T00:00:00Z")
        )

        #expect(fifthMonday == [
            isoDate("2023-01-30T09:30:00Z"),
            isoDate("2023-05-29T09:30:00Z"),
            isoDate("2023-07-31T09:30:00Z")
        ])
        #expect(lastFriday == [
            isoDate("2023-01-27T09:30:00Z"),
            isoDate("2023-02-24T09:30:00Z"),
            isoDate("2023-03-31T09:30:00Z")
        ])
    }

    @Test func monthlyOrdinalWeekdayAndWeekendSelectorsUseSetPositions() throws {
        let firstWeekday = try instants(
            schedule(
                source: source(year: 2023, month: 2, day: 1),
                rule: .monthly(
                    interval: 1,
                    selector: .ordinalDaySet(ordinal: 1, daySet: .weekday)
                )
            ),
            in: isoDate("2023-02-01T00:00:00Z")..<isoDate("2023-05-01T00:00:00Z")
        )
        let secondWeekendDay = try instants(
            schedule(
                source: source(year: 2023, month: 1, day: 7),
                rule: .monthly(
                    interval: 1,
                    selector: .ordinalDaySet(ordinal: 2, daySet: .weekend)
                )
            ),
            in: isoDate("2023-01-01T00:00:00Z")..<isoDate("2023-04-01T00:00:00Z")
        )

        #expect(firstWeekday == [
            isoDate("2023-02-01T09:30:00Z"),
            isoDate("2023-03-01T09:30:00Z"),
            isoDate("2023-04-03T09:30:00Z")
        ])
        #expect(secondWeekendDay == [
            isoDate("2023-01-07T09:30:00Z"),
            isoDate("2023-02-05T09:30:00Z"),
            isoDate("2023-03-05T09:30:00Z")
        ])
    }

    @Test func yearlyIntervalAndAnchorMonthDayMapDirectly() throws {
        let fixed = try instants(
            schedule(
                source: source(year: 2024, month: 5, day: 10),
                rule: .yearly(interval: 2, month: 5, selector: .dayOfMonth(10))
            ),
            in: isoDate("2024-01-01T00:00:00Z")..<isoDate("2030-01-01T00:00:00Z")
        )
        let anchorMonthDay = try instants(
            schedule(
                source: source(year: 2024, month: 6, day: 12),
                rule: .yearly(interval: 1, month: nil, selector: .anchorMonthDay)
            ),
            in: isoDate("2024-01-01T00:00:00Z")..<isoDate("2027-01-01T00:00:00Z")
        )

        #expect(fixed == [
            isoDate("2024-05-10T09:30:00Z"),
            isoDate("2026-05-10T09:30:00Z"),
            isoDate("2028-05-10T09:30:00Z")
        ])
        #expect(anchorMonthDay == [
            isoDate("2024-06-12T09:30:00Z"),
            isoDate("2025-06-12T09:30:00Z"),
            isoDate("2026-06-12T09:30:00Z")
        ])
    }

    @Test func fixedYearlyFebruary29DoesNotSpillToMarch() throws {
        let fixedValues = try instants(
            schedule(
                source: source(year: 2024, month: 2, day: 29),
                rule: .yearly(interval: 1, month: 2, selector: .dayOfMonth(29))
            ),
            in: isoDate("2027-01-01T00:00:00Z")..<isoDate("2033-01-01T00:00:00Z")
        )
        let anchorMonthDayValues = try instants(
            schedule(
                source: source(year: 2024, month: 2, day: 29),
                rule: .yearly(interval: 1, month: nil, selector: .anchorMonthDay)
            ),
            in: isoDate("2027-01-01T00:00:00Z")..<isoDate("2033-01-01T00:00:00Z")
        )

        let expected = [
            isoDate("2028-02-29T09:30:00Z"),
            isoDate("2032-02-29T09:30:00Z")
        ]
        #expect(fixedValues == expected)
        #expect(anchorMonthDayValues == expected)
    }

    @Test func yearlyOrdinalSelectorMapsMonthAndReverseWeekday() throws {
        let values = try instants(
            schedule(
                source: source(year: 2024, month: 5, day: 27),
                rule: .yearly(
                    interval: 1,
                    month: 5,
                    selector: .ordinalWeekday(ordinal: -1, weekday: .monday)
                )
            ),
            in: isoDate("2024-01-01T00:00:00Z")..<isoDate("2027-01-01T00:00:00Z")
        )

        #expect(values == [
            isoDate("2024-05-27T09:30:00Z"),
            isoDate("2025-05-26T09:30:00Z"),
            isoDate("2026-05-25T09:30:00Z")
        ])
    }

    @Test func existingFixedYearlyDateKeepsFoundationDSTResolution() throws {
        let schedule = schedule(
            source: source(
                year: 2026,
                month: 3,
                day: 8,
                hour: 2,
                minute: 30,
                timeZoneIdentifier: "America/New_York"
            ),
            rule: .yearly(interval: 1, month: 3, selector: .dayOfMonth(8))
        )
        let values = try engine.baseOccurrences(
            for: schedule,
            in: isoDate("2026-01-01T00:00:00Z")..<isoDate("2027-01-01T00:00:00Z"),
            environment: FoundationRecurrenceEnvironment()
        ).map(\.instant)

        #expect(values == [isoDate("2026-03-08T07:30:00Z")])
    }

    @Test func hourlyUsesElapsedPhaseAcrossGapAndOverlapWithoutReresolution() throws {
        let gapSchedule = schedule(
            source: source(
                year: 2026,
                month: 3,
                day: 8,
                hour: 2,
                minute: 30,
                timeZoneIdentifier: "America/New_York"
            ),
            rule: .hourly(interval: 1)
        )
        let overlapSchedule = schedule(
            source: source(
                year: 2026,
                month: 11,
                day: 1,
                hour: 1,
                minute: 30,
                timeZoneIdentifier: "America/New_York"
            ),
            rule: .hourly(interval: 1)
        )

        let gap = try engine.baseOccurrences(
            for: gapSchedule,
            in: isoDate("2026-03-08T07:30:00Z")..<isoDate("2026-03-08T10:31:00Z"),
            environment: FoundationRecurrenceEnvironment()
        ).map { ($0.instant, $0.sourceComponents.hour) }
        let overlap = try engine.baseOccurrences(
            for: overlapSchedule,
            in: isoDate("2026-11-01T05:30:00Z")..<isoDate("2026-11-01T09:31:00Z"),
            environment: FoundationRecurrenceEnvironment()
        ).map { ($0.instant, $0.sourceComponents.hour) }

        #expect(gap.map(\.0) == [
            isoDate("2026-03-08T07:30:00Z"),
            isoDate("2026-03-08T08:30:00Z"),
            isoDate("2026-03-08T09:30:00Z"),
            isoDate("2026-03-08T10:30:00Z")
        ])
        #expect(gap.map(\.1) == [3, 4, 5, 6])
        #expect(overlap.map(\.0) == [
            isoDate("2026-11-01T05:30:00Z"),
            isoDate("2026-11-01T06:30:00Z"),
            isoDate("2026-11-01T07:30:00Z"),
            isoDate("2026-11-01T08:30:00Z"),
            isoDate("2026-11-01T09:30:00Z")
        ])
        #expect(overlap.map(\.1) == [1, 1, 2, 3, 4])
    }

    @Test func hourlyRangeUsesCeilingIndexAndExclusiveUpperBound() throws {
        let anchor = isoDate("2026-08-04T09:30:00Z")
        let values = try instants(
            schedule(source: source(), rule: .hourly(interval: 1)),
            in: anchor.addingTimeInterval(0.5)..<anchor.addingTimeInterval(3 * 3_600)
        )

        #expect(values == [
            isoDate("2026-08-04T10:30:00Z"),
            isoDate("2026-08-04T11:30:00Z")
        ])
    }

    @Test func scheduleEndDateIsInclusiveInSourceZone() throws {
        let values = try instants(
            schedule(
                source: source(year: 2026, month: 8, day: 1),
                rule: .daily(interval: 1),
                end: .onDate(SourceDate(year: 2026, month: 8, day: 3))
            ),
            in: isoDate("2026-08-01T00:00:00Z")..<isoDate("2026-08-06T00:00:00Z")
        )

        #expect(values == [
            isoDate("2026-08-01T09:30:00Z"),
            isoDate("2026-08-02T09:30:00Z"),
            isoDate("2026-08-03T09:30:00Z")
        ])
    }

    @Test func farPastHourlySearchCalculatesLargeInitialIndexOnce() throws {
        let environment = CountingUTCEnvironment()
        let schedule = schedule(
            source: source(year: 1, month: 1, day: 1, hour: 0, minute: 0),
            rule: .hourly(interval: 9_999)
        )
        let range: Range<Date> = utcDate(year: 9_999, month: 12, day: 1)..<utcDate(
            year: 9_999,
            month: 12,
            day: 31
        )

        let values = try engine.baseOccurrences(
            for: schedule,
            in: range,
            environment: environment
        ).prefix(3)

        #expect(values.allSatisfy { range.contains($0.instant) })
        #expect(environment.timeZoneLookupCount == 1)
        #expect(environment.calendarCreationCount == 1)
    }

    @Test func farPastCalendarSearchPassesFiniteRangeToFoundation() throws {
        let environment = CountingUTCEnvironment()
        let schedule = schedule(
            source: source(year: 1900, month: 1, day: 1),
            rule: .daily(interval: 9_999)
        )
        let range = isoDate("2026-01-01T00:00:00Z")..<isoDate("2026-02-01T00:00:00Z")

        let values = try engine.baseOccurrences(
            for: schedule,
            in: range,
            environment: environment
        ).prefix(3)

        #expect(values.allSatisfy { range.contains($0.instant) })
        #expect(environment.timeZoneLookupCount == 1)
        #expect(environment.calendarCreationCount == 1)
    }

    @Test func rejectsUnvalidatedIntervals() {
        let invalidSchedules = [
            schedule(source: source(), rule: .hourly(interval: 0)),
            schedule(source: source(), rule: .daily(interval: 10_000))
        ]

        for invalidSchedule in invalidSchedules {
            #expect(throws: FoundationRecurrenceError.self) {
                _ = try engine.baseOccurrences(
                    for: invalidSchedule,
                    in: isoDate("2026-01-01T00:00:00Z")..<isoDate("2027-01-01T00:00:00Z"),
                    environment: UTCRecurrenceEnvironment()
                )
            }
        }
    }

    @Test func neverEmitsBaseOccurrencesBeyondSupportedSourceYear() throws {
        let lowerBound = utcDate(year: 9_999, month: 12, day: 31)
        let upperBound = utcDate(year: 10_000, month: 1, day: 2)
        let range = lowerBound..<upperBound
        let hourly = try instants(
            schedule(
                source: source(year: 9_999, month: 12, day: 31, hour: 23, minute: 30),
                rule: .hourly(interval: 1)
            ),
            in: range
        )
        let daily = try instants(
            schedule(
                source: source(year: 9_999, month: 12, day: 31),
                rule: .daily(interval: 1)
            ),
            in: range
        )

        #expect(hourly == [utcDate(year: 9_999, month: 12, day: 31).addingTimeInterval(23.5 * 3_600)])
        #expect(daily == [utcDate(year: 9_999, month: 12, day: 31).addingTimeInterval(9.5 * 3_600)])
    }

    private let engine = FoundationRecurrenceEngine()

    private func instants(_ schedule: ScheduleDefinition, in range: Range<Date>) throws -> [Date] {
        try engine.baseOccurrences(
            for: schedule,
            in: range,
            environment: UTCRecurrenceEnvironment()
        ).map(\.instant)
    }

    private func schedule(
        source: SourceWallClock,
        rule: RepeatRule,
        end: RepeatEnd = .never
    ) -> ScheduleDefinition {
        ScheduleDefinition(source: source, rule: rule, end: end, early: nil)
    }

    private func source(
        year: Int = 2026,
        month: Int = 8,
        day: Int = 4,
        hour: Int = 9,
        minute: Int = 30,
        timeZoneIdentifier: String = "UTC"
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

private struct UTCRecurrenceEnvironment: RecurrenceEnvironment {
    func timeZone(identifier: String) -> TimeZone? {
        guard identifier == "UTC" else { return nil }
        return TimeZone(secondsFromGMT: 0)
    }

    func gregorianCalendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

private final class CountingUTCEnvironment: RecurrenceEnvironment, @unchecked Sendable {
    private let lock = NSLock()
    private var timeZoneLookups = 0
    private var calendarCreations = 0

    var timeZoneLookupCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return timeZoneLookups
    }

    var calendarCreationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calendarCreations
    }

    func timeZone(identifier: String) -> TimeZone? {
        lock.lock()
        timeZoneLookups += 1
        lock.unlock()
        guard identifier == "UTC" else { return nil }
        return TimeZone(secondsFromGMT: 0)
    }

    func gregorianCalendar(in timeZone: TimeZone) -> Calendar {
        lock.lock()
        calendarCreations += 1
        lock.unlock()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

private func isoDate(_ value: String) -> Date {
    guard let date = ISO8601DateFormatter().date(from: value) else {
        preconditionFailure("Invalid ISO-8601 test fixture: \(value)")
    }
    return date
}

private func utcDate(year: Int, month: Int, day: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
        preconditionFailure("Invalid UTC test fixture")
    }
    return date
}
