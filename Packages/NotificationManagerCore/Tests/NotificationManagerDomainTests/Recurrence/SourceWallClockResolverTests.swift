import Foundation
import Testing
@testable import NotificationManagerDomain

@Suite("Recurrence.SourceWallClockResolver")
struct SourceWallClockResolverTests {
    @Test func resolvesExactNonTransitionWallClock() throws {
        let source = SourceWallClock(
            year: 2026, month: 8, day: 4, hour: 9, minute: 30,
            timeZoneIdentifier: "Asia/Manila"
        )

        let date = try resolver.resolve(source, environment: FoundationRecurrenceEnvironment())

        #expect(date == isoDate("2026-08-04T01:30:00Z"))
    }

    @Test func gapMovesForwardWhilePreservingMinute() throws {
        let source = SourceWallClock(
            year: 2026, month: 3, day: 8, hour: 2, minute: 30,
            timeZoneIdentifier: "America/New_York"
        )

        let date = try resolver.resolve(source, environment: FoundationRecurrenceEnvironment())

        #expect(date == isoDate("2026-03-08T07:30:00Z"))
    }

    @Test func overlapUsesFirstOccurrence() throws {
        let source = SourceWallClock(
            year: 2026, month: 11, day: 1, hour: 1, minute: 30,
            timeZoneIdentifier: "America/New_York"
        )

        let date = try resolver.resolve(source, environment: FoundationRecurrenceEnvironment())

        #expect(date == isoDate("2026-11-01T05:30:00Z"))
    }

    @Test func acceptsSupportedSourceYearBoundariesWithIntegralSeconds() throws {
        let fixtures: [(SourceWallClock, Int)] = [
            (
                SourceWallClock(
                    year: 1, month: 1, day: 1, hour: 0, minute: 0,
                    timeZoneIdentifier: "test/plus-fourteen"
                ),
                50_400
            ),
            (
                SourceWallClock(
                    year: 9_999, month: 12, day: 31, hour: 23, minute: 59,
                    timeZoneIdentifier: "test/minus-twelve"
                ),
                -43_200
            )
        ]

        for (source, secondsFromGMT) in fixtures {
            let environment = FixedTimeZoneEnvironment(
                acceptedIdentifier: source.timeZoneIdentifier,
                secondsFromGMT: secondsFromGMT
            )
            let date = try resolver.resolve(source, environment: environment)
            let zone = try #require(environment.timeZone(identifier: source.timeZoneIdentifier))
            let calendar = environment.gregorianCalendar(in: zone)
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: date
            )

            #expect(components.year == source.year)
            #expect(components.month == source.month)
            #expect(components.day == source.day)
            #expect(components.hour == source.hour)
            #expect(components.minute == source.minute)
            #expect(components.second == 0)
            #expect(
                date.timeIntervalSinceReferenceDate.rounded(FloatingPointRoundingRule.towardZero)
                    == date.timeIntervalSinceReferenceDate
            )
        }
    }

    @Test func rejectsInvalidComponentsAndUnknownTimeZone() {
        let invalidSources = [
            source(year: 0),
            source(year: 10_000),
            source(month: 0),
            source(month: 13),
            source(year: 2026, month: 2, day: 29),
            source(day: 0),
            source(hour: -1),
            source(hour: 24),
            source(minute: -1),
            source(minute: 60),
            source(timeZoneIdentifier: "Not/A_Real_Time_Zone")
        ]

        for invalidSource in invalidSources {
            #expect(throws: SourceWallClockResolutionError.self) {
                _ = try resolver.resolve(invalidSource, environment: FoundationRecurrenceEnvironment())
            }
        }
    }

    @Test func environmentIsTheTimeZoneAuthority() throws {
        let source = source(timeZoneIdentifier: "fixture/source-zone")
        let environment = FixedTimeZoneEnvironment(
            acceptedIdentifier: "fixture/source-zone",
            secondsFromGMT: 9 * 3_600
        )

        let date = try resolver.resolve(source, environment: environment)

        #expect(date == isoDate("2026-08-04T00:30:00Z"))
    }

    @Test func sevenFixedDayNominalProbePrecedesEveryFoundationZoneResult() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let nominal = try #require(
            utc.date(from: DateComponents(
                year: 2026, month: 6, day: 15, hour: 12, minute: 0, second: 0
            ))
        )
        let probe = nominal.addingTimeInterval(-7 * 24 * 3_600)
        let environment = FoundationRecurrenceEnvironment()

        for identifier in TimeZone.knownTimeZoneIdentifiers {
            let resolved = try resolver.resolve(
                SourceWallClock(
                    year: 2026, month: 6, day: 15, hour: 12, minute: 0,
                    timeZoneIdentifier: identifier
                ),
                environment: environment
            )
            #expect(probe < resolved, "Seven-day probe did not precede \(identifier)")
        }
    }

    private let resolver = SourceWallClockResolver()

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

private struct FixedTimeZoneEnvironment: RecurrenceEnvironment {
    let acceptedIdentifier: String
    let secondsFromGMT: Int

    func timeZone(identifier: String) -> TimeZone? {
        guard identifier == acceptedIdentifier else { return nil }
        return TimeZone(secondsFromGMT: secondsFromGMT)
    }

    func gregorianCalendar(in timeZone: TimeZone) -> Calendar {
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
