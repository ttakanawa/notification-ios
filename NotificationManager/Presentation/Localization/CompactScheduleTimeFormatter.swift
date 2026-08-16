import Foundation

struct CompactScheduleTimePresentation: Sendable, Equatable {
    let localTime: String
    let sourceTime: String?
    let sourceTimeZoneLabel: String?
    let dayOffset: Int?
    let dayOffsetLabel: String?
    let accessibilityDayOffsetLabel: String?
}

struct CompactScheduleTimeFormatter: Sendable {
    func presentation(
        for instant: Date,
        sourceTimeZoneIdentifier: String?,
        locale: Locale,
        deviceTimeZone: TimeZone
    ) -> CompactScheduleTimePresentation {
        let localTime = formatTime(instant, timeZone: deviceTimeZone, locale: locale)
        guard let sourceTimeZoneIdentifier,
            let sourceTimeZone = TimeZone(identifier: sourceTimeZoneIdentifier)
        else {
            return CompactScheduleTimePresentation(
                localTime: localTime,
                sourceTime: nil,
                sourceTimeZoneLabel: nil,
                dayOffset: nil,
                dayOffsetLabel: nil,
                accessibilityDayOffsetLabel: nil
            )
        }

        let offset = dayOffset(
            for: instant,
            deviceTimeZone: deviceTimeZone,
            sourceTimeZone: sourceTimeZone
        )
        return CompactScheduleTimePresentation(
            localTime: localTime,
            sourceTime: formatTime(instant, timeZone: sourceTimeZone, locale: locale),
            sourceTimeZoneLabel: sourceZoneLabel(
                sourceTimeZone,
                at: instant,
                locale: locale
            ),
            dayOffset: offset == 0 ? nil : offset,
            dayOffsetLabel: offset == 0 ? nil : dayOffsetLabel(offset, locale: locale),
            accessibilityDayOffsetLabel: offset == 0
                ? nil
                : accessibilityDayOffsetLabel(offset, locale: locale)
        )
    }

    private func formatTime(
        _ instant: Date,
        timeZone: TimeZone,
        locale: Locale
    ) -> String {
        instant.formatted(
            Date.FormatStyle(
                date: .omitted,
                time: .shortened,
                locale: locale,
                calendar: Calendar(identifier: .gregorian),
                timeZone: timeZone
            ))
    }

    private func sourceZoneLabel(
        _ timeZone: TimeZone,
        at instant: Date,
        locale: Locale
    ) -> String {
        let style: TimeZone.NameStyle =
            timeZone.isDaylightSavingTime(for: instant)
            ? .shortDaylightSaving
            : .shortStandard
        return timeZone.localizedName(for: style, locale: locale)
            ?? gmtOffsetLabel(timeZone.secondsFromGMT(for: instant))
    }

    private func gmtOffsetLabel(_ seconds: Int) -> String {
        guard seconds != 0 else { return "GMT" }
        let sign = seconds < 0 ? "-" : "+"
        let magnitude = abs(seconds)
        let hours = magnitude / 3_600
        let minutes = magnitude % 3_600 / 60
        if minutes == 0 { return "GMT\(sign)\(hours)" }
        return String(format: "GMT%@%d:%02d", sign, hours, minutes)
    }

    private func dayOffset(
        for instant: Date,
        deviceTimeZone: TimeZone,
        sourceTimeZone: TimeZone
    ) -> Int {
        var neutralCalendar = Calendar(identifier: .gregorian)
        neutralCalendar.timeZone = .gmt
        let localDate = dayAnchor(
            for: instant,
            timeZone: deviceTimeZone,
            neutralCalendar: neutralCalendar
        )
        let sourceDate = dayAnchor(
            for: instant,
            timeZone: sourceTimeZone,
            neutralCalendar: neutralCalendar
        )
        return neutralCalendar.dateComponents(
            [.day],
            from: localDate,
            to: sourceDate
        ).day ?? 0
    }

    private func dayAnchor(
        for instant: Date,
        timeZone: TimeZone,
        neutralCalendar: Calendar
    ) -> Date {
        var zonedCalendar = Calendar(identifier: .gregorian)
        zonedCalendar.timeZone = timeZone
        let components = zonedCalendar.dateComponents(
            [.year, .month, .day],
            from: instant
        )
        return neutralCalendar.date(from: components) ?? .distantPast
    }

    private func dayOffsetLabel(_ offset: Int, locale: Locale) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        let magnitude =
            formatter.string(
                from: DateComponents(day: abs(offset))
            ) ?? String(abs(offset))
        let sign = offset < 0 ? "-" : "+"
        return "\(sign)\(magnitude)".uppercased(with: locale)
    }

    private func accessibilityDayOffsetLabel(_ offset: Int, locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(from: DateComponents(day: offset))
    }
}
