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
            case .hourly(let interval): self = .hourly(interval)
            case .daily(let interval): self = .daily(interval)
            case .weekly(let interval, let kind, let weekdays):
                self = .weekly(interval, WeekdaySetKindDTO(kind), weekdays.map(WeekdayDTO.init))
            case .monthly(let interval, let selector):
                self = .monthly(interval, SelectorDTO(selector))
            case .yearly(let interval, let month, let selector):
                self = .yearly(interval, month, SelectorDTO(selector))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .none:
                try container.encode("none", forKey: .type)
            case .hourly(let interval):
                try container.encode("hourly", forKey: .type)
                try container.encode(interval, forKey: .interval)
            case .daily(let interval):
                try container.encode("daily", forKey: .type)
                try container.encode(interval, forKey: .interval)
            case .weekly(let interval, let kind, let weekdays):
                try container.encode("weekly", forKey: .type)
                try container.encode(interval, forKey: .interval)
                try container.encode(kind, forKey: .weekdaySetKind)
                try container.encode(weekdays, forKey: .weekdays)
            case .monthly(let interval, let selector):
                try container.encode("monthly", forKey: .type)
                try container.encode(interval, forKey: .interval)
                try container.encode(selector, forKey: .selector)
            case .yearly(let interval, let month, let selector):
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
            case .dayOfMonth(let day): self = .dayOfMonth(day)
            case .lastDay: self = .lastDay
            case .ordinalDaySet(let ordinal, let daySet):
                self = .ordinalDaySet(ordinal, DaySetDTO(daySet))
            case .ordinalWeekday(let ordinal, let weekday):
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
            case .dayOfMonth(let day):
                try container.encode("dayOfMonth", forKey: .type)
                try container.encode(day, forKey: .day)
            case .lastDay:
                try container.encode("lastDay", forKey: .type)
            case .ordinalDaySet(let ordinal, let daySet):
                try container.encode("ordinalDaySet", forKey: .type)
                try container.encode(ordinal, forKey: .ordinal)
                try container.encode(daySet, forKey: .daySet)
            case .ordinalWeekday(let ordinal, let weekday):
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
            case .onDate(let date): self = .onDate(date)
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .never:
                try container.encode("never", forKey: .type)
            case .onDate(let date):
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
