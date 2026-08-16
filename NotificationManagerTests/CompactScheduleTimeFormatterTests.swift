import Foundation
import Testing

@testable import NotificationManager

struct CompactScheduleTimeFormatterTests {
    private let formatter = CompactScheduleTimeFormatter()
    private let locale = Locale(identifier: "en_US")
    private let manila = TimeZone(identifier: "Asia/Manila")!

    @Test func sameDayLondonTimeHasNoDayOffset() throws {
        let instant = try Date.ISO8601FormatStyle().parse("2040-08-07T15:00:00Z")

        let value = formatter.presentation(
            for: instant,
            sourceTimeZoneIdentifier: "Europe/London",
            locale: locale,
            deviceTimeZone: manila
        )

        #expect(value.localTime == "11:00\u{202F}PM")
        #expect(value.sourceTime == "4:00\u{202F}PM")
        #expect(value.sourceTimeZoneLabel == "GMT+1")
        #expect(value.dayOffset == nil)
        #expect(value.dayOffsetLabel == nil)
    }

    @Test func previousSourceDayProducesMinusOneDay() throws {
        let instant = try Date.ISO8601FormatStyle().parse("2040-08-07T21:00:00Z")

        let value = formatter.presentation(
            for: instant,
            sourceTimeZoneIdentifier: "America/New_York",
            locale: locale,
            deviceTimeZone: manila
        )

        #expect(value.localTime == "5:00\u{202F}AM")
        #expect(value.sourceTime == "5:00\u{202F}PM")
        #expect(value.sourceTimeZoneLabel == "EDT")
        #expect(value.dayOffset == -1)
        #expect(value.dayOffsetLabel == "-1 DAY")
        #expect(value.accessibilityDayOffsetLabel == "1 day ago")
    }

    @Test func nextSourceDayProducesPlusOneDay() throws {
        let instant = try Date.ISO8601FormatStyle().parse("2040-08-07T21:00:00Z")

        let value = formatter.presentation(
            for: instant,
            sourceTimeZoneIdentifier: "Asia/Manila",
            locale: locale,
            deviceTimeZone: TimeZone(identifier: "America/New_York")!
        )

        #expect(value.dayOffset == 1)
        #expect(value.dayOffsetLabel == "+1 DAY")
        #expect(value.accessibilityDayOffsetLabel == "in 1 day")
    }

    @Test func japaneseDayOffsetLabelsAreLocalized() throws {
        let instant = try Date.ISO8601FormatStyle().parse("2040-08-07T21:00:00Z")

        let value = formatter.presentation(
            for: instant,
            sourceTimeZoneIdentifier: "America/New_York",
            locale: Locale(identifier: "ja_JP"),
            deviceTimeZone: manila
        )

        #expect(value.dayOffsetLabel == "-1日")
        #expect(value.accessibilityDayOffsetLabel == "1 日前")
    }

    @Test func invalidSourceZoneKeepsOnlyDeviceLocalTime() throws {
        let instant = try Date.ISO8601FormatStyle().parse("2040-08-07T15:00:00Z")

        let value = formatter.presentation(
            for: instant,
            sourceTimeZoneIdentifier: "Invalid/Zone",
            locale: locale,
            deviceTimeZone: manila
        )

        #expect(value.localTime == "11:00\u{202F}PM")
        #expect(value.sourceTime == nil)
        #expect(value.sourceTimeZoneLabel == nil)
        #expect(value.dayOffset == nil)
        #expect(value.dayOffsetLabel == nil)
        #expect(value.accessibilityDayOffsetLabel == nil)
    }
}
