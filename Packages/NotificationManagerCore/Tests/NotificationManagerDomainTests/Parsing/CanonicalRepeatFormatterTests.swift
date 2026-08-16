import Testing

@testable import NotificationManagerDomain

@Suite("Parsing.CanonicalRepeatFormatter")
struct ParsingCanonicalRepeatFormatterTests {
    @Test func formatsEveryRuleElementWithCanonicalCapitalizationNamesAndOrdinals() {
        let fixtures: [(RepeatRule, String)] = [
            (.none, "Does Not Repeat"),
            (.hourly(interval: 1), "Every hour"), (.hourly(interval: 2), "Every 2 hours"),
            (.daily(interval: 1), "Every day"), (.daily(interval: 2), "Every 2 days"),
            (.weekly(interval: 1, weekdaySetKind: .explicit, weekdays: [.monday]), "Every Monday"),
            (
                .weekly(
                    interval: 1, weekdaySetKind: .weekday,
                    weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday]), "Every weekday"
            ),
            (
                .weekly(interval: 1, weekdaySetKind: .weekend, weekdays: [.saturday, .sunday]),
                "Every weekend"
            ),
            (
                .weekly(interval: 1, weekdaySetKind: .explicit, weekdays: [.monday, .friday]),
                "Every Monday and Friday"
            ),
            (
                .weekly(
                    interval: 1, weekdaySetKind: .explicit,
                    weekdays: [.monday, .wednesday, .friday]), "Every Monday, Wednesday, and Friday"
            ),
            (
                .weekly(interval: 2, weekdaySetKind: .explicit, weekdays: [.tuesday]),
                "Every 2 weeks"
            ),
            (.monthly(interval: 1, selector: .anchorDay), "Every month"),
            (.monthly(interval: 3, selector: .anchorDay), "Every 3 months"),
            (.monthly(interval: 1, selector: .dayOfMonth(21)), "Every month on the 21st"),
            (.monthly(interval: 1, selector: .lastDay), "Every month on the last day"),
            (
                .monthly(interval: 1, selector: .ordinalDaySet(ordinal: 2, daySet: .weekend)),
                "Every month on the 2nd weekend day"
            ),
            (
                .monthly(interval: 1, selector: .ordinalWeekday(ordinal: 3, weekday: .tuesday)),
                "Every month on the 3rd Tuesday"
            ),
            (
                .monthly(interval: 1, selector: .ordinalWeekday(ordinal: -1, weekday: .monday)),
                "Every month on the last Monday"
            ),
            (
                .monthly(interval: 1, selector: .ordinalWeekday(ordinal: -2, weekday: .friday)),
                "Every month on the 2nd last Friday"
            ),
            (.yearly(interval: 1, month: nil, selector: .anchorMonthDay), "Every year"),
            (.yearly(interval: 2, month: nil, selector: .anchorMonthDay), "Every 2 years"),
            (
                .yearly(interval: 1, month: 1, selector: .lastDay),
                "Every year on the last day of January"
            ),
            (
                .yearly(
                    interval: 1, month: 12, selector: .ordinalWeekday(ordinal: 5, weekday: .sunday)),
                "Every year on the 5th Sunday of December"
            )
        ]

        for (rule, expected) in fixtures {
            #expect(formatter.string(for: rule) == expected)
        }
    }

    @Test func emitsCorrectSuffixForEveryDayAndSelectorOrdinal() {
        let expected: [(Int, String)] = [
            (1, "1st"), (2, "2nd"), (3, "3rd"), (4, "4th"), (11, "11th"), (12, "12th"),
            (13, "13th"), (21, "21st"), (22, "22nd"), (23, "23rd"), (31, "31st")
        ]
        for (day, ordinal) in expected {
            #expect(
                formatter.string(for: .monthly(interval: 1, selector: .dayOfMonth(day)))
                    == "Every month on the \(ordinal)")
        }
    }

    private let formatter = CanonicalRepeatFormatter()
}
