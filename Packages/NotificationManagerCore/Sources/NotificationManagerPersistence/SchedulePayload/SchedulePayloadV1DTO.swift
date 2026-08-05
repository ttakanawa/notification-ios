import NotificationManagerDomain

struct ScheduleEnvelopeV1DTO: Encodable {
    let format: String
    let payload: SchedulePayloadV1DTO
    let version: UInt32
}

struct SchedulePayloadV1DTO: Encodable {
    let source: SourceDTO
    let rule: RuleDTO
    let end: EndDTO
    let early: EarlyDTO?

    init(_ definition: ScheduleDefinition) {
        source = SourceDTO(definition.source)
        rule = RuleDTO(definition.rule)
        end = EndDTO(definition.end)
        early = definition.early.map(EarlyDTO.init)
    }

    struct SourceDTO: Encodable {
        let year: Int
        let month: Int
        let day: Int
        let hour: Int
        let minute: Int
        let timeZone: String

        init(_ source: SourceWallClock) {
            year = source.year
            month = source.month
            day = source.day
            hour = source.hour
            minute = source.minute
            timeZone = source.timeZoneIdentifier
        }
    }

    enum RuleDTO: Encodable {
        case none
        case hourly(Int)
        case daily(Int)
        case weekly(Int, WeekdaySetKindDTO, [WeekdayDTO])
        case monthly(Int, SelectorDTO)
        case yearly(Int, Int?, SelectorDTO)

        init(_ rule: RepeatRule) {
            switch rule {
            case .none: self = .none
            case let .hourly(interval): self = .hourly(interval)
            case let .daily(interval): self = .daily(interval)
            case let .weekly(interval, kind, weekdays):
                self = .weekly(interval, WeekdaySetKindDTO(kind), weekdays.map(WeekdayDTO.init))
            case let .monthly(interval, selector):
                self = .monthly(interval, SelectorDTO(selector))
            case let .yearly(interval, month, selector):
                self = .yearly(interval, month, SelectorDTO(selector))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .none:
                try container.encode("none", forKey: .type)
            case let .hourly(interval):
                try container.encode("hourly", forKey: .type)
                try container.encode(interval, forKey: .interval)
            case let .daily(interval):
                try container.encode("daily", forKey: .type)
                try container.encode(interval, forKey: .interval)
            case let .weekly(interval, kind, weekdays):
                try container.encode("weekly", forKey: .type)
                try container.encode(interval, forKey: .interval)
                try container.encode(kind, forKey: .weekdaySetKind)
                try container.encode(weekdays, forKey: .weekdays)
            case let .monthly(interval, selector):
                try container.encode("monthly", forKey: .type)
                try container.encode(interval, forKey: .interval)
                try container.encode(selector, forKey: .selector)
            case let .yearly(interval, month, selector):
                try container.encode("yearly", forKey: .type)
                try container.encode(interval, forKey: .interval)
                try container.encodeIfPresent(month, forKey: .month)
                try container.encode(selector, forKey: .selector)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case type, interval, weekdaySetKind, weekdays, selector, month
        }
    }

    enum SelectorDTO: Encodable {
        case anchorDay
        case anchorMonthDay
        case dayOfMonth(Int)
        case lastDay
        case ordinalDaySet(Int, DaySetDTO)
        case ordinalWeekday(Int, WeekdayDTO)

        init(_ selector: RepeatSelector) {
            switch selector {
            case .anchorDay: self = .anchorDay
            case .anchorMonthDay: self = .anchorMonthDay
            case let .dayOfMonth(day): self = .dayOfMonth(day)
            case .lastDay: self = .lastDay
            case let .ordinalDaySet(ordinal, daySet):
                self = .ordinalDaySet(ordinal, DaySetDTO(daySet))
            case let .ordinalWeekday(ordinal, weekday):
                self = .ordinalWeekday(ordinal, WeekdayDTO(weekday))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .anchorDay:
                try container.encode("anchorDay", forKey: .type)
            case .anchorMonthDay:
                try container.encode("anchorMonthDay", forKey: .type)
            case let .dayOfMonth(day):
                try container.encode("dayOfMonth", forKey: .type)
                try container.encode(day, forKey: .day)
            case .lastDay:
                try container.encode("lastDay", forKey: .type)
            case let .ordinalDaySet(ordinal, daySet):
                try container.encode("ordinalDaySet", forKey: .type)
                try container.encode(ordinal, forKey: .ordinal)
                try container.encode(daySet, forKey: .daySet)
            case let .ordinalWeekday(ordinal, weekday):
                try container.encode("ordinalWeekday", forKey: .type)
                try container.encode(ordinal, forKey: .ordinal)
                try container.encode(weekday, forKey: .weekday)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case type, day, ordinal, daySet, weekday
        }
    }

    enum EndDTO: Encodable {
        case never
        case onDate(SourceDate)

        init(_ end: RepeatEnd) {
            switch end {
            case .never: self = .never
            case let .onDate(date): self = .onDate(date)
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .never:
                try container.encode("never", forKey: .type)
            case let .onDate(date):
                try container.encode("onDate", forKey: .type)
                try container.encode(date.year, forKey: .year)
                try container.encode(date.month, forKey: .month)
                try container.encode(date.day, forKey: .day)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case type, year, month, day
        }
    }

    struct EarlyDTO: Encodable {
        let value: Int
        let unit: EarlyReminderUnitDTO
        let mainEnabled: Bool

        init(_ early: EarlyReminder) {
            value = early.value
            unit = EarlyReminderUnitDTO(early.unit)
            mainEnabled = early.mainEnabled
        }
    }
}

enum WeekdayDTO: String, Encodable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday

    init(_ value: Weekday) {
        self = Self.allCases[value.rawValue - 1]
    }
}

extension WeekdayDTO: CaseIterable {}

enum WeekdaySetKindDTO: String, Encodable {
    case explicit, weekday, weekend

    init(_ value: WeekdaySetKind) {
        switch value {
        case .explicit: self = .explicit
        case .weekday: self = .weekday
        case .weekend: self = .weekend
        }
    }
}

enum DaySetDTO: String, Encodable {
    case weekday, weekend

    init(_ value: DaySet) {
        switch value {
        case .weekday: self = .weekday
        case .weekend: self = .weekend
        }
    }
}

enum EarlyReminderUnitDTO: String, Encodable {
    case minutes, hours, days, weeks

    init(_ value: EarlyReminderUnit) {
        switch value {
        case .minutes: self = .minutes
        case .hours: self = .hours
        case .days: self = .days
        case .weeks: self = .weeks
        }
    }
}
