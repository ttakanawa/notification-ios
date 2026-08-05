public struct CanonicalRepeatFormatter: Sendable {
    public init() {}

    public func string(for rule: RepeatRule) -> String {
        switch rule {
        case .none:
            return "Does Not Repeat"
        case let .hourly(interval):
            return frequency(interval: interval, singular: "hour", plural: "hours")
        case let .daily(interval):
            return frequency(interval: interval, singular: "day", plural: "days")
        case let .weekly(interval, kind, weekdays):
            return weekly(interval: interval, kind: kind, weekdays: weekdays)
        case let .monthly(interval, selector):
            return frequency(interval: interval, singular: "month", plural: "months")
                + selectorText(selector)
        case let .yearly(interval, month, selector):
            let prefix = frequency(interval: interval, singular: "year", plural: "years")
            guard let month, (1...12).contains(month) else { return prefix }
            return prefix + selectorText(selector) + " of " + Self.monthNames[month - 1]
        }
    }

    private func frequency(interval: Int, singular: String, plural: String) -> String {
        interval == 1 ? "Every \(singular)" : "Every \(interval) \(plural)"
    }

    private func weekly(
        interval: Int,
        kind: WeekdaySetKind,
        weekdays: [Weekday]
    ) -> String {
        if interval != 1 {
            return frequency(interval: interval, singular: "week", plural: "weeks")
        }
        switch kind {
        case .weekday:
            return "Every weekday"
        case .weekend:
            return "Every weekend"
        case .explicit:
            let names = weekdays
                .sorted { $0.rawValue < $1.rawValue }
                .map(weekdayName)
            switch names.count {
            case 0:
                return "Every week"
            case 1:
                return "Every \(names[0])"
            case 2:
                return "Every \(names[0]) and \(names[1])"
            default:
                return "Every " + names.dropLast().joined(separator: ", ") + ", and " + names.last!
            }
        }
    }

    private func selectorText(_ selector: RepeatSelector) -> String {
        switch selector {
        case .anchorDay, .anchorMonthDay:
            return ""
        case let .dayOfMonth(day):
            return " on the \(ordinal(day))"
        case .lastDay:
            return " on the last day"
        case let .ordinalDaySet(value, daySet):
            return " on the \(ordinal(value)) \(daySet == .weekday ? "weekday" : "weekend day")"
        case let .ordinalWeekday(value, weekday):
            if value == -1 {
                return " on the last \(weekdayName(weekday))"
            }
            if value < -1 {
                return " on the \(ordinal(-value)) last \(weekdayName(weekday))"
            }
            return " on the \(ordinal(value)) \(weekdayName(weekday))"
        }
    }

    private func ordinal(_ value: Int) -> String {
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

    private func weekdayName(_ weekday: Weekday) -> String {
        Self.weekdayNames[weekday.rawValue - 1]
    }

    private static let weekdayNames = [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
    ]

    private static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]
}
