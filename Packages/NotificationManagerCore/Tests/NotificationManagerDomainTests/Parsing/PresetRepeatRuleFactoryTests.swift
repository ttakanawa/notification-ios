import Testing
@testable import NotificationManagerDomain

@Suite("Parsing.PresetRepeatRuleFactory")
struct ParsingPresetRepeatRuleFactoryTests {
    @Test func mapsEveryPresetExactlyUsingTheSourceDateForWeeklyAnchors() {
        let expected: [(RepeatPreset, RepeatRule)] = [
            (.doesNotRepeat, .none),
            (.hourly, .hourly(interval: 1)),
            (.daily, .daily(interval: 1)),
            (.weekdays, .weekly(interval: 1, weekdaySetKind: .weekday, weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday])),
            (.weekends, .weekly(interval: 1, weekdaySetKind: .weekend, weekdays: [.saturday, .sunday])),
            (.weekly, .weekly(interval: 1, weekdaySetKind: .explicit, weekdays: [.tuesday])),
            (.biweekly, .weekly(interval: 2, weekdaySetKind: .explicit, weekdays: [.tuesday])),
            (.monthly, .monthly(interval: 1, selector: .anchorDay)),
            (.every3Months, .monthly(interval: 3, selector: .anchorDay)),
            (.every6Months, .monthly(interval: 6, selector: .anchorDay)),
            (.yearly, .yearly(interval: 1, month: nil, selector: .anchorMonthDay))
        ]

        for (preset, rule) in expected {
            #expect(factory.rule(for: preset, source: .repeatFixture) == rule)
        }
    }

    @Test func derivesWeekdayAcrossGregorianCenturyAndLeapYearBoundaries() {
        let fixtures: [(SourceWallClock, Weekday)] = [
            (.init(year: 1, month: 1, day: 1, hour: 0, minute: 0, timeZoneIdentifier: "UTC"), .monday),
            (.init(year: 2000, month: 2, day: 29, hour: 0, minute: 0, timeZoneIdentifier: "UTC"), .tuesday),
            (.init(year: 2100, month: 3, day: 1, hour: 0, minute: 0, timeZoneIdentifier: "UTC"), .monday),
            (.init(year: 9999, month: 12, day: 31, hour: 0, minute: 0, timeZoneIdentifier: "UTC"), .friday)
        ]

        for (source, weekday) in fixtures {
            #expect(factory.rule(for: .weekly, source: source) == .weekly(interval: 1, weekdaySetKind: .explicit, weekdays: [weekday]))
        }
    }

    private let factory = PresetRepeatRuleFactory()
}
