import Foundation

public struct SourceWallClock: Sendable, Equatable {
    public let year: Int
    public let month: Int
    public let day: Int
    public let hour: Int
    public let minute: Int
    public let timeZoneIdentifier: String

    public init(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        timeZoneIdentifier: String
    ) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

public struct SourceDate: Sendable, Equatable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }
}

public struct SourceTime: Sendable, Equatable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }
}

public enum Weekday: Int, CaseIterable, Sendable, Equatable {
    case monday = 1
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday
}

public enum WeekdaySetKind: Sendable, Equatable {
    case explicit
    case weekday
    case weekend
}

public enum DaySet: Sendable, Equatable {
    case weekday
    case weekend
}

public enum RepeatSelector: Sendable, Equatable {
    case anchorDay
    case anchorMonthDay
    case dayOfMonth(Int)
    case lastDay
    case ordinalDaySet(ordinal: Int, daySet: DaySet)
    case ordinalWeekday(ordinal: Int, weekday: Weekday)
}

public enum RepeatRule: Sendable, Equatable {
    case none
    case hourly(interval: Int)
    case daily(interval: Int)
    case weekly(interval: Int, weekdaySetKind: WeekdaySetKind, weekdays: [Weekday])
    case monthly(interval: Int, selector: RepeatSelector)
    case yearly(interval: Int, month: Int?, selector: RepeatSelector)
}

public enum RepeatEnd: Sendable, Equatable {
    case never
    case onDate(SourceDate)
}

public enum EarlyReminderUnit: Sendable, Equatable {
    case seconds
    case minutes
    case hours
    case days
    case weeks
}

public struct EarlyReminder: Sendable, Equatable {
    public let value: Int
    public let unit: EarlyReminderUnit
    public let mainEnabled: Bool

    public init(value: Int, unit: EarlyReminderUnit, mainEnabled: Bool = true) {
        self.value = value
        self.unit = unit
        self.mainEnabled = mainEnabled
    }
}

public struct ScheduleDefinition: Sendable, Equatable {
    public let source: SourceWallClock
    public let rule: RepeatRule
    public let end: RepeatEnd
    public let early: EarlyReminder?

    public init(
        source: SourceWallClock,
        rule: RepeatRule,
        end: RepeatEnd,
        early: EarlyReminder?
    ) {
        self.source = source
        self.rule = rule
        self.end = end
        self.early = early
    }
}

public struct ScheduleRepairSeed: Sendable, Equatable {
    public let source: SourceWallClock?
    public let rule: RepeatRule?
    public let end: RepeatEnd?
    public let early: EarlyReminder?

    public init(
        source: SourceWallClock? = nil,
        rule: RepeatRule? = nil,
        end: RepeatEnd? = nil,
        early: EarlyReminder? = nil
    ) {
        self.source = source
        self.rule = rule
        self.end = end
        self.early = early
    }
}

public enum ScheduleValidationIssue: Sendable, Equatable {
    case invalidSourceYear
    case invalidSourceMonth
    case invalidSourceDay
    case invalidSourceHour
    case invalidSourceMinute
    case invalidTimeZone
    case intervalOutOfRange
    case invalidWeekdaySet
    case invalidSelector
    case invalidMonth
    case invalidEndDate
    case endBeforeStart
    case endNotAllowed
    case earlyValueOutOfRange
}

public enum ScheduleReadState: Sendable, Equatable {
    case valid(ScheduleDefinition, sourceVersion: UInt32, originalData: Data)
    case unsupportedFuture(version: UInt32, originalData: Data)
    case corrupt(originalData: Data)
    case domainInvalid(
        repairSeed: ScheduleRepairSeed,
        originalData: Data,
        issues: [ScheduleValidationIssue]
    )
}

public enum DraftScheduleChange: Sendable, Equatable {
    case preserveOriginal
    case replace(ScheduleDefinition)
}
