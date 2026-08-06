#if canImport(FoundationModels)
import FoundationModels
import NotificationManagerDomain

@available(iOS 26.0, *)
@Generable(description: "A structured repeat rule without a time, time zone, or end condition")
struct FoundationRepeatCandidate: Equatable, Sendable {
    @Guide(description: "Whether the input belongs to the supported repeat grammar")
    var isSupported: Bool

    @Guide(description: "The recurrence frequency")
    var frequency: FoundationRepeatFrequency

    @Guide(description: "A positive repeat interval", .range(1...9_999))
    var interval: Int

    @Guide(description: "The meaning of the weekday collection")
    var weekdaySetKind: FoundationWeekdaySetKind

    @Guide(description: "Zero to seven distinct weekdays", .count(0...7))
    var weekdays: [FoundationWeekday]

    @Guide(description: "The month for a yearly rule, or none")
    var month: FoundationMonth

    @Guide(description: "The monthly or yearly selector, or none")
    var selector: FoundationRepeatSelector

    var repeatCandidate: RepeatCandidate {
        RepeatCandidate(
            isSupported: isSupported,
            frequency: frequency.repeatCandidateFrequency,
            interval: interval,
            weekdaySetKind: weekdaySetKind.weekdaySetKind,
            weekdays: weekdays.map(\.weekday),
            month: month.number,
            selector: selector.repeatCandidateSelector
        )
    }
}

@available(iOS 26.0, *)
@Generable
enum FoundationRepeatFrequency: Equatable, Sendable {
    case hourly
    case daily
    case weekly
    case monthly
    case yearly

    var repeatCandidateFrequency: RepeatCandidateFrequency {
        switch self {
        case .hourly: .hourly
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        }
    }
}

@available(iOS 26.0, *)
@Generable
enum FoundationWeekdaySetKind: Equatable, Sendable {
    case none
    case explicit
    case weekday
    case weekend

    var weekdaySetKind: WeekdaySetKind? {
        switch self {
        case .none: nil
        case .explicit: .explicit
        case .weekday: .weekday
        case .weekend: .weekend
        }
    }
}

@available(iOS 26.0, *)
@Generable
enum FoundationWeekday: Equatable, Sendable {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    var weekday: Weekday {
        switch self {
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        case .sunday: .sunday
        }
    }
}

@available(iOS 26.0, *)
@Generable
enum FoundationMonth: Equatable, Sendable {
    case none
    case january
    case february
    case march
    case april
    case may
    case june
    case july
    case august
    case september
    case october
    case november
    case december

    var number: Int? {
        switch self {
        case .none: nil
        case .january: 1
        case .february: 2
        case .march: 3
        case .april: 4
        case .may: 5
        case .june: 6
        case .july: 7
        case .august: 8
        case .september: 9
        case .october: 10
        case .november: 11
        case .december: 12
        }
    }
}

@available(iOS 26.0, *)
@Generable
enum FoundationRepeatSelector: Equatable, Sendable {
    case none
    case anchorDay
    case anchorMonthDay
    case dayOfMonth(FoundationDayOfMonth)
    case lastDay
    case ordinalDaySet(FoundationOrdinalDaySet)
    case ordinalWeekday(FoundationOrdinalWeekday)

    var repeatCandidateSelector: RepeatCandidateSelector? {
        switch self {
        case .none:
            nil
        case .anchorDay:
            .anchorDay
        case .anchorMonthDay:
            .anchorMonthDay
        case let .dayOfMonth(value):
            .dayOfMonth(value.day)
        case .lastDay:
            .lastDay
        case let .ordinalDaySet(value):
            .ordinalDaySet(ordinal: value.ordinal, daySet: value.daySet.daySet)
        case let .ordinalWeekday(value):
            .ordinalWeekday(ordinal: value.ordinal, weekday: value.weekday.weekday)
        }
    }
}

@available(iOS 26.0, *)
@Generable
struct FoundationDayOfMonth: Equatable, Sendable {
    @Guide(description: "The day number within a month", .range(1...31))
    var day: Int
}

@available(iOS 26.0, *)
@Generable
struct FoundationOrdinalDaySet: Equatable, Sendable {
    @Guide(description: "A forward ordinal", .range(1...5))
    var ordinal: Int

    @Guide(description: "Whether the ordinal selects a weekday or weekend day")
    var daySet: FoundationDaySet
}

@available(iOS 26.0, *)
@Generable
struct FoundationOrdinalWeekday: Equatable, Sendable {
    @Guide(
        description: "A forward 1 through 5 ordinal or reverse -1 through -5 ordinal",
        .range(-5...5)
    )
    var ordinal: Int

    @Guide(description: "The selected weekday")
    var weekday: FoundationWeekday
}

@available(iOS 26.0, *)
@Generable
enum FoundationDaySet: Equatable, Sendable {
    case weekday
    case weekend

    var daySet: DaySet {
        switch self {
        case .weekday: .weekday
        case .weekend: .weekend
        }
    }
}
#endif
