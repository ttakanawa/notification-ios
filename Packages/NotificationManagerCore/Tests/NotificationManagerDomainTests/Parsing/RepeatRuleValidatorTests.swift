import Testing
@testable import NotificationManagerDomain

@Suite("Parsing.RepeatRuleValidator")
struct ParsingRepeatRuleValidatorTests {
    @Test func normalizesExplicitWeekdaysByDeduplicatingAndSortingMondayFirst() throws {
        let candidate = RepeatCandidate(
            frequency: .weekly,
            interval: 1,
            weekdaySetKind: .explicit,
            weekdays: [.friday, .monday, .friday, .wednesday],
            selector: nil
        )

        let rule = try validator.validate(candidate, source: .repeatFixture)
        #expect(rule == .weekly(interval: 1, weekdaySetKind: .explicit, weekdays: [.monday, .wednesday, .friday]))
    }

    @Test func mapsEverySupportedCandidateFamilyToTask2DomainTypes() throws {
        let fixtures: [(RepeatCandidate, RepeatRule)] = [
            (.init(frequency: .hourly, interval: 1), .hourly(interval: 1)),
            (.init(frequency: .daily, interval: 2), .daily(interval: 2)),
            (.init(frequency: .weekly, interval: 1, weekdaySetKind: .weekday, weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday]), .weekly(interval: 1, weekdaySetKind: .weekday, weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday])),
            (.init(frequency: .monthly, interval: 4, selector: .anchorDay), .monthly(interval: 4, selector: .anchorDay)),
            (.init(frequency: .yearly, interval: 5, month: nil, selector: .anchorMonthDay), .yearly(interval: 5, month: nil, selector: .anchorMonthDay)),
            (.init(frequency: .yearly, interval: 1, month: 2, selector: .dayOfMonth(29)), .yearly(interval: 1, month: 2, selector: .dayOfMonth(29))),
            (.init(frequency: .monthly, interval: 1, selector: .ordinalWeekday(ordinal: -5, weekday: .sunday)), .monthly(interval: 1, selector: .ordinalWeekday(ordinal: -5, weekday: .sunday)))
        ]

        for (candidate, expected) in fixtures {
            #expect(try validator.validate(candidate, source: .repeatFixture) == expected)
        }
    }

    @Test func weeklyAnchorAndExplicitSourceWeekdayValidateToTheSameSemanticRule() throws {
        let anchor = RepeatCandidate(frequency: .weekly, interval: 1)
        let explicit = RepeatCandidate(
            frequency: .weekly,
            interval: 1,
            weekdaySetKind: .explicit,
            weekdays: [.tuesday]
        )

        #expect(try validator.validate(anchor, source: .repeatFixture) == validator.validate(explicit, source: .repeatFixture))
    }

    @Test func rejectsUnsupportedGeneratedCandidateAndInvalidFieldCombinations() {
        let invalid: [RepeatCandidate] = [
            .init(isSupported: false, frequency: .daily, interval: 1),
            .init(frequency: .hourly, interval: 0),
            .init(frequency: .daily, interval: 10_000),
            .init(frequency: .hourly, interval: 1, month: 1),
            .init(frequency: .daily, interval: 1, selector: .anchorDay),
            .init(frequency: .weekly, interval: 1, weekdaySetKind: nil, weekdays: [.monday]),
            .init(frequency: .weekly, interval: 1, weekdaySetKind: .explicit, weekdays: []),
            .init(frequency: .weekly, interval: 1, weekdaySetKind: .weekday, weekdays: [.monday]),
            .init(frequency: .weekly, interval: 2, weekdaySetKind: .explicit, weekdays: [.monday]),
            .init(frequency: .monthly, interval: 1, selector: nil),
            .init(frequency: .monthly, interval: 1, month: 1, selector: .anchorDay),
            .init(frequency: .monthly, interval: 1, selector: .anchorMonthDay),
            .init(frequency: .monthly, interval: 1, selector: .dayOfMonth(0)),
            .init(frequency: .monthly, interval: 1, selector: .ordinalDaySet(ordinal: 6, daySet: .weekday)),
            .init(frequency: .monthly, interval: 1, selector: .ordinalWeekday(ordinal: 0, weekday: .monday)),
            .init(frequency: .yearly, interval: 1, month: nil, selector: .anchorDay),
            .init(frequency: .yearly, interval: 1, month: 13, selector: .dayOfMonth(1)),
            .init(frequency: .yearly, interval: 1, month: 4, selector: .dayOfMonth(31)),
            .init(frequency: .yearly, interval: 1, month: 2, selector: .dayOfMonth(30)),
            .init(frequency: .yearly, interval: 1, month: 1, selector: .anchorMonthDay)
        ]

        for candidate in invalid {
            #expect(throws: RepeatCandidateValidationError.self) {
                _ = try validator.validate(candidate, source: .repeatFixture)
            }
        }
    }

    @Test func acceptsAllSelectorBoundariesAndLeapDay() throws {
        let selectors: [RepeatCandidateSelector] = [
            .dayOfMonth(1), .dayOfMonth(31), .lastDay,
            .ordinalDaySet(ordinal: 1, daySet: .weekday),
            .ordinalDaySet(ordinal: 5, daySet: .weekend),
            .ordinalWeekday(ordinal: -5, weekday: .monday),
            .ordinalWeekday(ordinal: -1, weekday: .tuesday),
            .ordinalWeekday(ordinal: 1, weekday: .wednesday),
            .ordinalWeekday(ordinal: 5, weekday: .sunday)
        ]
        for selector in selectors {
            _ = try validator.validate(.init(frequency: .monthly, interval: 1, selector: selector), source: .repeatFixture)
        }
        _ = try validator.validate(.init(frequency: .yearly, interval: 1, month: 2, selector: .dayOfMonth(29)), source: .repeatFixture)
    }

    private let validator = RepeatRuleValidator()
}
