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
                ? "Every week on \(names)."
                : "Every \(interval) weeks on \(names)."
        case let .monthly(interval, selector):
            let selectorText = selectorSummary(selector, japanese: japanese)
            if japanese {
                return interval == 1
                    ? "毎月\(selectorText)に繰り返します。"
                    : "\(interval)か月ごとの\(selectorText)に繰り返します。"
            }
            return interval == 1
                ? "Every month \(selectorText)."
                : "Every \(interval) months \(selectorText)."
        case let .yearly(interval, month, selector):
            let monthText = month.map { monthName($0, japanese: japanese) }
            let selectorText = selectorSummary(selector, japanese: japanese)
            if japanese {
                let date = [monthText, selectorText].compactMap { $0 }.joined()
                return interval == 1
                    ? "毎年\(date)に繰り返します。"
                    : "\(interval)年ごとの\(date)に繰り返します。"
            }
            let date = [monthText, selectorText].compactMap { $0 }.joined(separator: " ")
            return interval == 1
                ? "Every year on \(date)."
                : "Every \(interval) years on \(date)."
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

    private func selectorSummary(_ selector: RepeatSelector, japanese: Bool) -> String {
        switch selector {
        case .anchorDay, .anchorMonthDay:
            return japanese ? "開始日と同じ日" : "on the anchor date"
        case let .dayOfMonth(day):
            return japanese ? "\(day)日" : "on day \(day)"
        case .lastDay:
            return japanese ? "最終日" : "on the last day"
        case let .ordinalDaySet(ordinal, daySet):
            let set = daySet == .weekday
                ? (japanese ? "平日" : "weekday")
                : (japanese ? "週末" : "weekend day")
            return japanese ? "第\(ordinal)\(set)" : "on the \(ordinalText(ordinal)) \(set)"
        case let .ordinalWeekday(ordinal, weekday):
            let name = weekdayName(weekday, japanese: japanese)
            return japanese
                ? "第\(ordinal)\(name)"
                : "on the \(ordinalText(ordinal)) \(name)"
        }
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
