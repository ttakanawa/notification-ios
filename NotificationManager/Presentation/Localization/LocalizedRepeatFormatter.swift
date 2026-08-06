import Foundation
import NotificationManagerDomain

struct LocalizedRepeatFormatter: Sendable {
    private let localizer: LocalizedTextProvider

    init(localizer: LocalizedTextProvider = .live) {
        self.localizer = localizer
    }

    func summary(for schedule: ScheduleDefinition, locale: Locale) -> String {
        switch schedule.rule {
        case .none:
            return text("localization.repeat.one-time", locale: locale)
        case let .hourly(interval):
            return interval == 1
                ? text("localization.repeat.hourly.one", locale: locale)
                : format(
                    "localization.repeat.hourly.interval",
                    locale: locale,
                    Int64(interval)
                )
        case let .daily(interval):
            return interval == 1
                ? text("localization.repeat.daily.one", locale: locale)
                : format(
                    "localization.repeat.daily.interval",
                    locale: locale,
                    Int64(interval)
                )
        case let .weekly(interval, kind, weekdays):
            if interval == 1, kind == .weekday {
                return text("localization.repeat.weekdays", locale: locale)
            }
            if interval == 1, kind == .weekend {
                return text("localization.repeat.weekends", locale: locale)
            }
            let names = weekdayList(weekdays, locale: locale)
            return interval == 1
                ? format("localization.repeat.weekly.one", locale: locale, names)
                : format(
                    "localization.repeat.weekly.interval",
                    locale: locale,
                    Int64(interval),
                    names
                )
        case let .monthly(interval, selector):
            let selectorText = monthlySelectorSummary(
                selector,
                sourceDay: schedule.source.day,
                locale: locale
            )
            return interval == 1
                ? format("localization.repeat.monthly.one", locale: locale, selectorText)
                : format(
                    "localization.repeat.monthly.interval",
                    locale: locale,
                    Int64(interval),
                    selectorText
                )
        case let .yearly(interval, month, selector):
            let selectorText = yearlySelectorSummary(
                selector,
                month: month,
                sourceMonth: schedule.source.month,
                sourceDay: schedule.source.day,
                locale: locale
            )
            return interval == 1
                ? format("localization.repeat.yearly.one", locale: locale, selectorText)
                : format(
                    "localization.repeat.yearly.interval",
                    locale: locale,
                    Int64(interval),
                    selectorText
                )
        }
    }

    func sourceTime(for source: SourceWallClock, locale: Locale) -> String {
        let timeZone = TimeZone(identifier: source.timeZoneIdentifier) ?? .gmt
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: timeZone,
            year: source.year,
            month: source.month,
            day: source.day,
            hour: source.hour,
            minute: source.minute
        )) ?? .distantPast
        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.calendar = calendar
        timeFormatter.timeZone = timeZone
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        let time = timeFormatter.string(from: date)
        let isolatedTimeZone = "\u{2066}\(source.timeZoneIdentifier)\u{2069}"
        return format(
            "localization.source-time.sentence",
            locale: locale,
            time,
            isolatedTimeZone
        )
    }

    private func weekdayList(_ weekdays: [Weekday], locale: Locale) -> String {
        let names = weekdays.map { weekdayName($0, locale: locale) }
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: names) ?? names.joined(separator: ", ")
    }

    private func weekdayName(_ weekday: Weekday, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        let symbols = formatter.weekdaySymbols ?? []
        let index = switch weekday {
        case .sunday: 0
        case .monday: 1
        case .tuesday: 2
        case .wednesday: 3
        case .thursday: 4
        case .friday: 5
        case .saturday: 6
        }
        return symbols.indices.contains(index) ? symbols[index] : String(weekday.rawValue)
    }

    private func monthName(_ month: Int, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        let names = formatter.monthSymbols ?? []
        let index = month - 1
        return names.indices.contains(index) ? names[index] : String(month)
    }

    private func ordinal(_ value: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func monthlySelectorSummary(
        _ selector: RepeatSelector,
        sourceDay: Int,
        locale: Locale
    ) -> String {
        switch selector {
        case .anchorDay:
            return format(
                "localization.selector.day-of-month",
                locale: locale,
                Int64(sourceDay)
            )
        case let .dayOfMonth(day):
            return format(
                "localization.selector.day-of-month",
                locale: locale,
                Int64(day)
            )
        case .lastDay:
            return text("localization.selector.last-day", locale: locale)
        case let .ordinalDaySet(ordinalValue, daySet):
            return format(
                "localization.selector.ordinal-day-set",
                locale: locale,
                ordinal(ordinalValue, locale: locale),
                daySetName(daySet, locale: locale)
            )
        case let .ordinalWeekday(ordinalValue, weekday):
            return ordinalWeekdaySummary(
                ordinalValue,
                weekday: weekday,
                locale: locale
            )
        case .anchorMonthDay:
            return ""
        }
    }

    private func yearlySelectorSummary(
        _ selector: RepeatSelector,
        month: Int?,
        sourceMonth: Int,
        sourceDay: Int,
        locale: Locale
    ) -> String {
        guard let month else {
            return format(
                "localization.selector.month-day",
                locale: locale,
                monthName(sourceMonth, locale: locale),
                Int64(sourceDay)
            )
        }
        let monthText = monthName(month, locale: locale)
        switch selector {
        case let .dayOfMonth(day):
            return format(
                "localization.selector.month-day",
                locale: locale,
                monthText,
                Int64(day)
            )
        case .lastDay:
            return format(
                "localization.selector.month-last-day",
                locale: locale,
                monthText
            )
        case let .ordinalDaySet(ordinalValue, daySet):
            return format(
                "localization.selector.month-ordinal-day-set",
                locale: locale,
                monthText,
                ordinal(ordinalValue, locale: locale),
                daySetName(daySet, locale: locale)
            )
        case let .ordinalWeekday(ordinalValue, weekday):
            return format(
                "localization.selector.month-ordinal-weekday",
                locale: locale,
                ordinalWeekdaySummary(
                    ordinalValue,
                    weekday: weekday,
                    locale: locale
                ),
                monthText
            )
        case .anchorDay, .anchorMonthDay:
            return ""
        }
    }

    private func ordinalWeekdaySummary(
        _ ordinalValue: Int,
        weekday: Weekday,
        locale: Locale
    ) -> String {
        let name = weekdayName(weekday, locale: locale)
        if ordinalValue == -1 {
            return format(
                "localization.selector.last-weekday",
                locale: locale,
                name
            )
        }
        if ordinalValue < -1 {
            return format(
                "localization.selector.nth-last-weekday",
                locale: locale,
                nthLastOrdinal(-ordinalValue, locale: locale),
                name
            )
        }
        return format(
            "localization.selector.ordinal-weekday",
            locale: locale,
            ordinal(ordinalValue, locale: locale),
            name
        )
    }

    private func daySetName(_ daySet: DaySet, locale: Locale) -> String {
        switch daySet {
        case .weekday:
            text("localization.selector.day-set.weekday", locale: locale)
        case .weekend:
            text("localization.selector.day-set.weekend", locale: locale)
        }
    }

    private func nthLastOrdinal(_ value: Int, locale: Locale) -> String {
        guard locale.isJapanese else { return ordinal(value, locale: locale) }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func text(_ key: String, locale: Locale) -> String {
        localizer.value(for: key, locale: locale)
    }

    private func format(_ key: String, locale: Locale, _ arguments: CVarArg...) -> String {
        String(
            format: text(key, locale: locale),
            locale: locale,
            arguments: arguments
        )
    }
}

extension Locale {
    var isJapanese: Bool {
        language.languageCode == .japanese
    }
}
