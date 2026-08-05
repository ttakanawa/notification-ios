public enum RepeatCandidateFrequency: String, Sendable, Equatable, CaseIterable {
    case hourly
    case daily
    case weekly
    case monthly
    case yearly
}

public enum RepeatCandidateSelector: Sendable, Equatable {
    case anchorDay
    case anchorMonthDay
    case dayOfMonth(Int)
    case lastDay
    case ordinalDaySet(ordinal: Int, daySet: DaySet)
    case ordinalWeekday(ordinal: Int, weekday: Weekday)
}

public struct RepeatCandidate: Sendable, Equatable {
    public var isSupported: Bool
    public var frequency: RepeatCandidateFrequency
    public var interval: Int
    public var weekdaySetKind: WeekdaySetKind?
    public var weekdays: [Weekday]
    public var month: Int?
    public var selector: RepeatCandidateSelector?

    public init(
        isSupported: Bool = true,
        frequency: RepeatCandidateFrequency,
        interval: Int,
        weekdaySetKind: WeekdaySetKind? = nil,
        weekdays: [Weekday] = [],
        month: Int? = nil,
        selector: RepeatCandidateSelector? = nil
    ) {
        self.isSupported = isSupported
        self.frequency = frequency
        self.interval = interval
        self.weekdaySetKind = weekdaySetKind
        self.weekdays = weekdays
        self.month = month
        self.selector = selector
    }
}
