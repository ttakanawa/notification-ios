import Foundation
import NotificationManagerDomain

struct LocalizedRepeatFormatter: Sendable {
    func summary(for schedule: ScheduleDefinition, locale: Locale) -> String {
        let japanese = locale.isJapanese
        switch schedule.rule {
        case .none:
            return japanese ? "1回のみです。" : "One time."
        case let .hourly(interval):
            if japanese { return interval == 1 ? "毎時繰り返します。" : "\(interval)時間ごとに繰り返します。" }
            return interval == 1 ? "Every hour." : "Every \(interval) hours."
        case let .daily(interval):
            if japanese { return interval == 1 ? "毎日繰り返します。" : "\(interval)日ごとに繰り返します。" }
            return interval == 1 ? "Every day." : "Every \(interval) days."
        case let .weekly(interval, kind, weekdays):
            if interval == 1, kind == .weekday {
                return japanese ? "平日に繰り返します。" : "Every weekday."
            }
            if interval == 1, kind == .weekend {
                return japanese ? "週末に繰り返します。" : "Every weekend."
            }
            let names = weekdayList(weekdays, japanese: japanese)
            if japanese {
                return interval == 1
                    ? "毎週\(names)に繰り返します。"
                    : "\(interval)週間ごとの\(names)に繰り返します。"
            }
            return interval == 1
                ? "Every \(names)."
                : "Every \(interval) weeks on \(names)."
        case let .monthly(interval, selector):
            let selectorText = monthlySelectorSummary(
                selector,
                sourceDay: schedule.source.day,
                japanese: japanese
            )
            if japanese {
                return interval == 1
                    ? "毎月\(selectorText)に繰り返します。"
                    : "\(interval)か月ごとの\(selectorText)に繰り返します。"
            }
            return interval == 1
                ? "Every month on \(selectorText)."
                : "Every \(interval) months on \(selectorText)."
        case let .yearly(interval, month, selector):
            let selectorText = yearlySelectorSummary(
                selector,
                month: month,
                sourceMonth: schedule.source.month,
                sourceDay: schedule.source.day,
                japanese: japanese
            )
            if japanese {
                return interval == 1
                    ? "毎年\(selectorText)に繰り返します。"
                    : "\(interval)年ごとの\(selectorText)に繰り返します。"
            }
            return interval == 1
                ? "Every year on \(selectorText)."
                : "Every \(interval) years on \(selectorText)."
        }
    }

    func sourceTime(for source: SourceWallClock, locale: Locale) -> String {
        let time = String(format: "%02d:%02d", source.hour, source.minute)
        if locale.isJapanese {
            return "基準時刻: \(time)（\(source.timeZoneIdentifier)）。"
        }
        return "Source time: \(time) (\(source.timeZoneIdentifier))."
    }

    private func weekdayList(_ weekdays: [Weekday], japanese: Bool) -> String {
        let names = weekdays.map { weekdayName($0, japanese: japanese) }
        if japanese { return names.joined(separator: "・") }
        guard names.count > 1 else { return names.first ?? "" }
        if names.count == 2 { return names.joined(separator: " and ") }
        return names.dropLast().joined(separator: ", ") + ", and " + names.last!
    }

    private func weekdayName(_ weekday: Weekday, japanese: Bool) -> String {
        if japanese {
            return switch weekday {
            case .monday: "月曜日"
            case .tuesday: "火曜日"
            case .wednesday: "水曜日"
            case .thursday: "木曜日"
            case .friday: "金曜日"
            case .saturday: "土曜日"
            case .sunday: "日曜日"
            }
        }
        return switch weekday {
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        case .sunday: "Sunday"
        }
    }

    private func monthName(_ month: Int, japanese: Bool) -> String {
        if japanese { return "\(month)月" }
        let names = [
            "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December"
        ]
        return names[month - 1]
    }

    private func monthlySelectorSummary(
        _ selector: RepeatSelector,
        sourceDay: Int,
        japanese: Bool
    ) -> String {
        switch selector {
        case .anchorDay:
            return japanese ? "\(sourceDay)日" : "day \(sourceDay)"
        case let .dayOfMonth(day):
            return japanese ? "\(day)日" : "day \(day)"
        case .lastDay:
            return japanese ? "最終日" : "the last day"
        case let .ordinalDaySet(ordinal, daySet):
            let set = daySet == .weekday
                ? (japanese ? "平日" : "weekday")
                : (japanese ? "週末日" : "weekend day")
            return japanese ? "第\(ordinal)\(set)" : "the \(ordinalText(ordinal)) \(set)"
        case let .ordinalWeekday(ordinal, weekday):
            return ordinalWeekdaySummary(ordinal, weekday: weekday, japanese: japanese)
        case .anchorMonthDay:
            return ""
        }
    }

    private func yearlySelectorSummary(
        _ selector: RepeatSelector,
        month: Int?,
        sourceMonth: Int,
        sourceDay: Int,
        japanese: Bool
    ) -> String {
        guard let month else {
            if japanese { return "\(sourceMonth)月\(sourceDay)日" }
            return "\(monthName(sourceMonth, japanese: false)) \(sourceDay)"
        }
        let monthText = monthName(month, japanese: japanese)
        switch selector {
        case let .dayOfMonth(day):
            return japanese ? "\(monthText)\(day)日" : "\(monthText) \(day)"
        case .lastDay:
            return japanese ? "\(monthText)の最終日" : "the last day of \(monthText)"
        case let .ordinalDaySet(ordinal, daySet):
            let set = daySet == .weekday
                ? (japanese ? "平日" : "weekday")
                : (japanese ? "週末日" : "weekend day")
            if japanese { return "\(monthText)の第\(ordinal)\(set)" }
            return "the \(ordinalText(ordinal)) \(set) of \(monthText)"
        case let .ordinalWeekday(ordinal, weekday):
            let value = ordinalWeekdaySummary(ordinal, weekday: weekday, japanese: japanese)
            return japanese ? "\(monthText)の\(value)" : "\(value) of \(monthText)"
        case .anchorDay, .anchorMonthDay:
            return ""
        }
    }

    private func ordinalWeekdaySummary(
        _ ordinal: Int,
        weekday: Weekday,
        japanese: Bool
    ) -> String {
        let name = weekdayName(weekday, japanese: japanese)
        if japanese {
            if ordinal == -1 { return "最終\(name)" }
            if ordinal < -1 { return "最後から\(-ordinal)番目の\(name)" }
            return "第\(ordinal)\(name)"
        }
        if ordinal == -1 { return "the last \(name)" }
        if ordinal < -1 { return "the \(ordinalText(-ordinal)) last \(name)" }
        return "the \(ordinalText(ordinal)) \(name)"
    }

    private func ordinalText(_ value: Int) -> String {
        let tens = value % 100
        let suffix: String
        if (11...13).contains(tens) {
            suffix = "th"
        } else {
            suffix = switch value % 10 {
            case 1: "st"
            case 2: "nd"
            case 3: "rd"
            default: "th"
            }
        }
        return "\(value)\(suffix)"
    }
}

extension Locale {
    var isJapanese: Bool {
        language.languageCode == .japanese
    }
}
