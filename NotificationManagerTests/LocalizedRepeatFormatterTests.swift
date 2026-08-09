import Foundation
import NotificationManagerDomain
import Testing
@testable import NotificationManager

struct LocalizedRepeatFormatterTests {
    @Test func everyValidRuleFamilyHasCompleteEnglishAndJapaneseSentences() {
        let fixtures: [(RepeatRule, String, String)] = [
            (.none, "One time.", "1回のみです。"),
            (.hourly(interval: 1), "Every hour.", "毎時繰り返します。"),
            (.hourly(interval: 9_999), "Every 9,999 hours.", "9,999時間ごとに繰り返します。"),
            (.daily(interval: 1), "Every day.", "毎日繰り返します。"),
            (.daily(interval: 9_999), "Every 9,999 days.", "9,999日ごとに繰り返します。"),
            (
                .weekly(
                    interval: 1,
                    weekdaySetKind: .explicit,
                    weekdays: [.monday, .wednesday, .friday]
                ),
                "Every Monday, Wednesday, and Friday.",
                "毎週月曜日、水曜日、金曜日に繰り返します。"
            ),
            (
                .weekly(
                    interval: 9_999,
                    weekdaySetKind: .explicit,
                    weekdays: [.monday, .friday]
                ),
                "Every 9,999 weeks on Monday and Friday.",
                "9,999週間ごとの月曜日、金曜日に繰り返します。"
            ),
            (
                .weekly(
                    interval: 1,
                    weekdaySetKind: .weekday,
                    weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday]
                ),
                "Every weekday.",
                "平日に繰り返します。"
            ),
            (
                .weekly(
                    interval: 1,
                    weekdaySetKind: .weekend,
                    weekdays: [.saturday, .sunday]
                ),
                "Every weekend.",
                "週末に繰り返します。"
            ),
            (
                .monthly(interval: 1, selector: .anchorDay),
                "Every month on day 31.",
                "毎月31日に繰り返します。"
            ),
            (
                .monthly(interval: 9_999, selector: .anchorDay),
                "Every 9,999 months on day 31.",
                "9,999か月ごとの31日に繰り返します。"
            ),
            (
                .monthly(interval: 1, selector: .dayOfMonth(21)),
                "Every month on day 21.",
                "毎月21日に繰り返します。"
            ),
            (
                .monthly(interval: 1, selector: .lastDay),
                "Every month on the last day.",
                "毎月最終日に繰り返します。"
            ),
            (
                .monthly(
                    interval: 1,
                    selector: .ordinalDaySet(ordinal: 2, daySet: .weekend)
                ),
                "Every month on the 2nd weekend day.",
                "毎月第2週末日に繰り返します。"
            ),
            (
                .monthly(
                    interval: 1,
                    selector: .ordinalWeekday(ordinal: 3, weekday: .tuesday)
                ),
                "Every month on the 3rd Tuesday.",
                "毎月第3火曜日に繰り返します。"
            ),
            (
                .monthly(
                    interval: 1,
                    selector: .ordinalWeekday(ordinal: -1, weekday: .monday)
                ),
                "Every month on the last Monday.",
                "毎月最終月曜日に繰り返します。"
            ),
            (
                .monthly(
                    interval: 1,
                    selector: .ordinalWeekday(ordinal: -5, weekday: .friday)
                ),
                "Every month on the 5th last Friday.",
                "毎月最後から5番目の金曜日に繰り返します。"
            ),
            (
                .yearly(interval: 1, month: nil, selector: .anchorMonthDay),
                "Every year on August 31.",
                "毎年8月31日に繰り返します。"
            ),
            (
                .yearly(interval: 9_999, month: nil, selector: .anchorMonthDay),
                "Every 9,999 years on August 31.",
                "9,999年ごとの8月31日に繰り返します。"
            ),
            (
                .yearly(interval: 1, month: 2, selector: .dayOfMonth(29)),
                "Every year on February 29.",
                "毎年2月29日に繰り返します。"
            ),
            (
                .yearly(interval: 1, month: 4, selector: .lastDay),
                "Every year on the last day of April.",
                "毎年4月の最終日に繰り返します。"
            ),
            (
                .yearly(
                    interval: 1,
                    month: 5,
                    selector: .ordinalDaySet(ordinal: 1, daySet: .weekday)
                ),
                "Every year on the 1st weekday of May.",
                "毎年5月の第1平日に繰り返します。"
            ),
            (
                .yearly(
                    interval: 1,
                    month: 12,
                    selector: .ordinalWeekday(ordinal: 5, weekday: .sunday)
                ),
                "Every year on the 5th Sunday of December.",
                "毎年12月の第5日曜日に繰り返します。"
            ),
            (
                .yearly(
                    interval: 1,
                    month: 8,
                    selector: .ordinalWeekday(ordinal: -1, weekday: .friday)
                ),
                "Every year on the last Friday of August.",
                "毎年8月の最終金曜日に繰り返します。"
            ),
            (
                .yearly(
                    interval: 1,
                    month: 3,
                    selector: .ordinalWeekday(ordinal: -2, weekday: .monday)
                ),
                "Every year on the 2nd last Monday of March.",
                "毎年3月の最後から2番目の月曜日に繰り返します。"
            )
        ]

        let formatter = LocalizedRepeatFormatter()
        for (rule, english, japanese) in fixtures {
            let schedule = fixtureSchedule(rule: rule)
            #expect(formatter.summary(for: schedule, locale: Locale(identifier: "en_US")) == english)
            #expect(formatter.summary(for: schedule, locale: Locale(identifier: "ja_JP")) == japanese)
        }
    }

    private func fixtureSchedule(rule: RepeatRule) -> ScheduleDefinition {
        ScheduleDefinition(
            source: SourceWallClock(
                year: 2040,
                month: 8,
                day: 31,
                hour: 9,
                minute: 30,
                timeZoneIdentifier: "America/New_York"
            ),
            rule: rule,
            end: .never,
            early: nil
        )
    }
}
