public enum RepeatPreset: String, Sendable, Equatable, CaseIterable {
    case doesNotRepeat
    case hourly
    case daily
    case weekdays
    case weekends
    case weekly
    case biweekly
    case monthly

    public init?(rule: RepeatRule) {
        switch rule {
        case .none:
            self = .doesNotRepeat
        case .hourly(interval: 1):
            self = .hourly
        case .daily(interval: 1):
            self = .daily
        case .weekly(
            interval: 1,
            weekdaySetKind: .weekday,
            weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday]
        ):
            self = .weekdays
        case .weekly(
            interval: 1,
            weekdaySetKind: .weekend,
            weekdays: [.saturday, .sunday]
        ):
            self = .weekends
        case .weekly(interval: 1, weekdaySetKind: .explicit, let weekdays)
        where weekdays.count == 1:
            self = .weekly
        case .weekly(interval: 2, weekdaySetKind: .explicit, let weekdays)
        where weekdays.count == 1:
            self = .biweekly
        case .monthly(interval: 1, selector: .anchorDay):
            self = .monthly
        default:
            return nil
        }
    }
}

public enum PresetRepeatRuleFactoryError: Error, Sendable, Equatable {
    case invalidSourceDate
}

public struct PresetRepeatRuleFactory: Sendable {
    public init() {}

    public func rule(
        for preset: RepeatPreset,
        source: SourceWallClock
    ) throws -> RepeatRule {
        switch preset {
        case .doesNotRepeat:
            return .none
        case .hourly:
            return .hourly(interval: 1)
        case .daily:
            return .daily(interval: 1)
        case .weekdays:
            return .weekly(
                interval: 1,
                weekdaySetKind: .weekday,
                weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday]
            )
        case .weekends:
            return .weekly(
                interval: 1,
                weekdaySetKind: .weekend,
                weekdays: [.saturday, .sunday]
            )
        case .weekly, .biweekly:
            guard
                let weekday = GregorianDate.weekday(
                    year: source.year,
                    month: source.month,
                    day: source.day
                )
            else {
                throw PresetRepeatRuleFactoryError.invalidSourceDate
            }
            return .weekly(
                interval: preset == .weekly ? 1 : 2,
                weekdaySetKind: .explicit,
                weekdays: [weekday]
            )
        case .monthly:
            return .monthly(interval: 1, selector: .anchorDay)
        }
    }
}
