public enum RepeatPreset: String, Sendable, Equatable, CaseIterable {
    case doesNotRepeat
    case hourly
    case daily
    case weekdays
    case weekends
    case weekly
    case biweekly
    case monthly
    case every3Months
    case every6Months
    case yearly
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
        case .every3Months:
            return .monthly(interval: 3, selector: .anchorDay)
        case .every6Months:
            return .monthly(interval: 6, selector: .anchorDay)
        case .yearly:
            return .yearly(interval: 1, month: nil, selector: .anchorMonthDay)
        }
    }
}
