import Foundation
import NotificationManagerDomain

struct SourceDateTimePresentationFormatter: Sendable {
    private static let leftToRightIsolate = "\u{2066}"
    private static let popDirectionalIsolate = "\u{2069}"

    private let localizer: LocalizedTextProvider

    init(localizer: LocalizedTextProvider = .live) {
        self.localizer = localizer
    }

    func wallClock(_ source: SourceWallClock, locale: Locale) -> String {
        let nominalTimeZone = TimeZone.gmt
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = nominalTimeZone
        let components = DateComponents(
            calendar: calendar,
            timeZone: nominalTimeZone,
            year: source.year,
            month: source.month,
            day: source.day,
            hour: source.hour,
            minute: source.minute
        )
        let date = calendar.date(from: components) ?? .distantPast

        return presentation(
            key: "reminder.source-wall-clock.presentation",
            date: date,
            timeZone: nominalTimeZone,
            timeZoneIdentifier: source.timeZoneIdentifier,
            locale: locale
        )
    }

    func instant(
        _ instant: Date,
        timeZoneIdentifier: String,
        locale: Locale
    ) -> String {
        let timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        return presentation(
            key: "reminder.source-instant.presentation",
            date: instant,
            timeZone: timeZone,
            timeZoneIdentifier: timeZoneIdentifier,
            locale: locale
        )
    }

    private func presentation(
        key: String,
        date: Date,
        timeZone: TimeZone,
        timeZoneIdentifier: String,
        locale: Locale
    ) -> String {
        let formattedDate = date.formatted(
            Date.FormatStyle(
                date: .numeric,
                time: .shortened,
                locale: locale,
                calendar: Calendar(identifier: .gregorian),
                timeZone: timeZone
            )
        )
        let isolatedIdentifier =
            Self.leftToRightIsolate
            + timeZoneIdentifier
            + Self.popDirectionalIsolate
        let format = localizer.value(for: key, locale: locale)
        return String(format: format, arguments: [formattedDate, isolatedIdentifier])
    }
}
