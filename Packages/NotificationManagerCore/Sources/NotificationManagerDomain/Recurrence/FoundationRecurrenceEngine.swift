import Foundation

public struct BaseOccurrence: Sendable, Equatable {
    public let instant: Date
    public let sourceComponents: DateComponents

    public init(instant: Date, sourceComponents: DateComponents) {
        self.instant = instant
        self.sourceComponents = sourceComponents
    }
}

public enum FoundationRecurrenceError: Error, Sendable, Equatable {
    case invalidRule
    case invalidRange
    case arithmeticOverflow
}

public struct FoundationRecurrenceEngine: Sendable {
    public init() {}

    public func baseOccurrences(
        for schedule: ScheduleDefinition,
        in range: Range<Date>,
        environment: any RecurrenceEnvironment
    ) throws -> AnySequence<BaseOccurrence> {
        try validateRule(schedule.rule)
        guard range.lowerBound.timeIntervalSinceReferenceDate.isFinite,
              range.upperBound.timeIntervalSinceReferenceDate.isFinite
        else {
            throw FoundationRecurrenceError.invalidRange
        }
        guard let timeZone = environment.timeZone(identifier: schedule.source.timeZoneIdentifier) else {
            throw SourceWallClockResolutionError.unknownTimeZone
        }
        let calendar = environment.gregorianCalendar(in: timeZone)
        let anchor = try SourceWallClockResolver().resolve(schedule.source, calendar: calendar)
        guard let effectiveRange = try effectiveRange(
            requested: range,
            schedule: schedule,
            calendar: calendar
        ) else {
            return emptySequence()
        }

        switch schedule.rule {
        case .none:
            guard effectiveRange.contains(anchor) else { return emptySequence() }
            return AnySequence([occurrence(at: anchor, calendar: calendar, timeZone: timeZone)])
        case let .hourly(interval):
            return try hourlyOccurrences(
                anchor: anchor,
                interval: interval,
                range: effectiveRange,
                calendar: calendar,
                timeZone: timeZone
            )
        case .daily, .weekly, .monthly, .yearly:
            let mapping = try recurrenceMapping(for: schedule, calendar: calendar)
            let includesAnchor = effectiveRange.contains(anchor)
                && anchorMatches(mapping.rule, anchor: anchor, calendar: calendar)
            let recurrenceLowerBound = includesAnchor
                ? max(effectiveRange.lowerBound, anchor.addingTimeInterval(1))
                : effectiveRange.lowerBound
            guard recurrenceLowerBound < effectiveRange.upperBound else {
                if includesAnchor {
                    return AnySequence([
                        occurrence(at: anchor, calendar: calendar, timeZone: timeZone)
                    ])
                }
                return emptySequence()
            }
            let recurrenceRange = recurrenceLowerBound..<effectiveRange.upperBound
            let values = mapping.rule.recurrences(of: anchor, in: recurrenceRange)
                .lazy
                .filter { date in
                    let year = calendar.component(.year, from: date)
                    guard (1...9_999).contains(year) else { return false }
                    guard let fixedDate = mapping.fixedYearlyDate else { return true }
                    return SourceWallClockResolver.isValidGregorianDate(
                        year: year,
                        month: fixedDate.month,
                        day: fixedDate.day
                    )
                }
                .map { date in
                    occurrence(at: date, calendar: calendar, timeZone: timeZone)
                }
            let erasedValues = AnySequence(values)
            guard includesAnchor else { return erasedValues }
            return prepending(
                occurrence(at: anchor, calendar: calendar, timeZone: timeZone),
                to: erasedValues
            )
        }
    }

    private func validateRule(_ rule: RepeatRule) throws {
        let interval: Int?
        switch rule {
        case .none:
            interval = nil
        case let .hourly(value),
             let .daily(value),
             let .weekly(value, _, _),
             let .monthly(value, _),
             let .yearly(value, _, _):
            interval = value
        }
        if let interval, !(1...9_999).contains(interval) {
            throw FoundationRecurrenceError.invalidRule
        }
    }

    private func effectiveRange(
        requested: Range<Date>,
        schedule: ScheduleDefinition,
        calendar: Calendar
    ) throws -> Range<Date>? {
        guard let supportedUpperBound = calendar.date(
            from: DateComponents(year: 10_000, month: 1, day: 1, hour: 0, minute: 0, second: 0)
        ) else {
            throw FoundationRecurrenceError.arithmeticOverflow
        }
        let upperBound: Date
        switch schedule.end {
        case .never:
            upperBound = min(requested.upperBound, supportedUpperBound)
        case let .onDate(end):
            let endSource = SourceWallClock(
                year: end.year,
                month: end.month,
                day: end.day,
                hour: 0,
                minute: 0,
                timeZoneIdentifier: schedule.source.timeZoneIdentifier
            )
            let endStart = try SourceWallClockResolver().resolve(endSource, calendar: calendar)
            guard let endExclusive = calendar.date(byAdding: .day, value: 1, to: endStart) else {
                throw FoundationRecurrenceError.arithmeticOverflow
            }
            upperBound = min(min(requested.upperBound, endExclusive), supportedUpperBound)
        }
        guard requested.lowerBound < upperBound else { return nil }
        return requested.lowerBound..<upperBound
    }

    private func hourlyOccurrences(
        anchor: Date,
        interval: Int,
        range: Range<Date>,
        calendar: Calendar,
        timeZone: TimeZone
    ) throws -> AnySequence<BaseOccurrence> {
        let (step, stepOverflow) = Int64(interval).multipliedReportingOverflow(by: 3_600)
        guard !stepOverflow else { throw FoundationRecurrenceError.arithmeticOverflow }

        let anchorInterval = anchor.timeIntervalSince1970
        guard anchorInterval.isFinite,
              anchorInterval.rounded(FloatingPointRoundingRule.towardZero) == anchorInterval,
              anchorInterval >= Double(Int64.min),
              anchorInterval <= Double(Int64.max)
        else {
            throw FoundationRecurrenceError.arithmeticOverflow
        }
        let anchorSeconds = Int64(anchorInterval)
        let firstIndex: Int64
        if range.lowerBound <= anchor {
            firstIndex = 0
        } else {
            let quotient = range.lowerBound.timeIntervalSince(anchor) / Double(step)
            let rounded = quotient.rounded(FloatingPointRoundingRule.up)
            guard rounded.isFinite, rounded >= 0, rounded <= Double(Int64.max) else {
                throw FoundationRecurrenceError.arithmeticOverflow
            }
            firstIndex = Int64(rounded)
        }

        let (initialOffset, offsetOverflow) = firstIndex.multipliedReportingOverflow(by: step)
        let (firstSeconds, firstOverflow) = anchorSeconds.addingReportingOverflow(initialOffset)
        guard !offsetOverflow, !firstOverflow else {
            throw FoundationRecurrenceError.arithmeticOverflow
        }

        return AnySequence {
            var nextSeconds: Int64? = firstSeconds
            return AnyIterator<BaseOccurrence> {
                guard let seconds = nextSeconds else { return nil }
                let date = Date(timeIntervalSince1970: Double(seconds))
                guard range.contains(date) else {
                    nextSeconds = nil
                    return nil
                }
                guard (1...9_999).contains(calendar.component(.year, from: date)) else {
                    nextSeconds = nil
                    return nil
                }
                let (following, overflow) = seconds.addingReportingOverflow(step)
                nextSeconds = overflow ? nil : following
                return occurrence(at: date, calendar: calendar, timeZone: timeZone)
            }
        }
    }

    private func recurrenceMapping(
        for schedule: ScheduleDefinition,
        calendar: Calendar
    ) throws -> RecurrenceMapping {
        let time = (
            hours: [schedule.source.hour],
            minutes: [schedule.source.minute],
            seconds: [0]
        )
        switch schedule.rule {
        case .none, .hourly:
            throw FoundationRecurrenceError.invalidRule
        case let .daily(interval):
            return RecurrenceMapping(
                rule: .daily(
                    calendar: calendar,
                    interval: interval,
                    matchingPolicy: .nextTimePreservingSmallerComponents,
                    repeatedTimePolicy: .first,
                    hours: time.hours,
                    minutes: time.minutes,
                    seconds: time.seconds
                )
            )
        case let .weekly(interval, _, weekdays):
            guard !weekdays.isEmpty else { throw FoundationRecurrenceError.invalidRule }
            return RecurrenceMapping(
                rule: .weekly(
                    calendar: calendar,
                    interval: interval,
                    matchingPolicy: .nextTimePreservingSmallerComponents,
                    repeatedTimePolicy: .first,
                    weekdays: weekdays.map { .every(foundationWeekday($0)) },
                    hours: time.hours,
                    minutes: time.minutes,
                    seconds: time.seconds
                )
            )
        case let .monthly(interval, selector):
            let fields = try selectorFields(selector, source: schedule.source)
            return RecurrenceMapping(
                rule: .monthly(
                    calendar: calendar,
                    interval: interval,
                    matchingPolicy: .nextTimePreservingSmallerComponents,
                    repeatedTimePolicy: .first,
                    daysOfTheMonth: fields.daysOfTheMonth,
                    weekdays: fields.weekdays,
                    hours: time.hours,
                    minutes: time.minutes,
                    seconds: time.seconds,
                    setPositions: fields.setPositions
                )
            )
        case let .yearly(interval, month, selector):
            let resolvedMonth: Int
            let resolvedSelector: RepeatSelector
            let fixedYearlyDate: FixedYearlyDate?
            if month == nil, selector == .anchorMonthDay {
                resolvedMonth = schedule.source.month
                resolvedSelector = .dayOfMonth(schedule.source.day)
                fixedYearlyDate = FixedYearlyDate(
                    month: schedule.source.month,
                    day: schedule.source.day
                )
            } else if let month {
                resolvedMonth = month
                resolvedSelector = selector
                if case let .dayOfMonth(day) = selector {
                    fixedYearlyDate = FixedYearlyDate(month: month, day: day)
                } else {
                    fixedYearlyDate = nil
                }
            } else {
                throw FoundationRecurrenceError.invalidRule
            }
            guard (1...12).contains(resolvedMonth) else {
                throw FoundationRecurrenceError.invalidRule
            }
            let fields = try selectorFields(resolvedSelector, source: schedule.source)
            return RecurrenceMapping(
                rule: .yearly(
                    calendar: calendar,
                    interval: interval,
                    matchingPolicy: .nextTimePreservingSmallerComponents,
                    repeatedTimePolicy: .first,
                    months: [.init(resolvedMonth)],
                    daysOfTheMonth: fields.daysOfTheMonth,
                    weekdays: fields.weekdays,
                    hours: time.hours,
                    minutes: time.minutes,
                    seconds: time.seconds,
                    setPositions: fields.setPositions
                ),
                fixedYearlyDate: fixedYearlyDate
            )
        }
    }

    private func selectorFields(
        _ selector: RepeatSelector,
        source: SourceWallClock
    ) throws -> SelectorFields {
        switch selector {
        case .anchorDay:
            return SelectorFields(daysOfTheMonth: [source.day])
        case .anchorMonthDay:
            throw FoundationRecurrenceError.invalidRule
        case let .dayOfMonth(day):
            guard (1...31).contains(day) else { throw FoundationRecurrenceError.invalidRule }
            return SelectorFields(daysOfTheMonth: [day])
        case .lastDay:
            return SelectorFields(daysOfTheMonth: [-1])
        case let .ordinalDaySet(ordinal, daySet):
            guard (1...5).contains(ordinal) else { throw FoundationRecurrenceError.invalidRule }
            let weekdays: [Weekday] = switch daySet {
            case .weekday:
                [.monday, .tuesday, .wednesday, .thursday, .friday]
            case .weekend:
                [.saturday, .sunday]
            }
            return SelectorFields(
                weekdays: weekdays.map { .every(foundationWeekday($0)) },
                setPositions: [ordinal]
            )
        case let .ordinalWeekday(ordinal, weekday):
            guard (-5 ... -1).contains(ordinal) || (1...5).contains(ordinal) else {
                throw FoundationRecurrenceError.invalidRule
            }
            return SelectorFields(weekdays: [.nth(ordinal, foundationWeekday(weekday))])
        }
    }

    private func foundationWeekday(_ weekday: Weekday) -> Locale.Weekday {
        switch weekday {
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        case .sunday: .sunday
        }
    }

    private func anchorMatches(
        _ rule: Calendar.RecurrenceRule,
        anchor: Date,
        calendar: Calendar
    ) -> Bool {
        let periodStart: Date?
        switch rule.frequency {
        case .daily:
            periodStart = calendar.startOfDay(for: anchor)
        case .weekly:
            periodStart = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start
        case .monthly:
            let components = calendar.dateComponents([.era, .year, .month], from: anchor)
            periodStart = calendar.date(from: components)
        case .yearly:
            let components = calendar.dateComponents([.era, .year], from: anchor)
            periodStart = calendar.date(from: components)
        case .minutely, .hourly:
            return false
        @unknown default:
            return false
        }
        guard let periodStart else { return false }
        var iterator = rule.recurrences(
            of: periodStart,
            in: anchor..<anchor.addingTimeInterval(1)
        ).makeIterator()
        return iterator.next() == anchor
    }

    private func prepending(
        _ first: BaseOccurrence,
        to remainder: AnySequence<BaseOccurrence>
    ) -> AnySequence<BaseOccurrence> {
        AnySequence {
            var shouldEmitFirst = true
            let iterator = remainder.makeIterator()
            return AnyIterator<BaseOccurrence> {
                if shouldEmitFirst {
                    shouldEmitFirst = false
                    return first
                }
                return iterator.next()
            }
        }
    }

    private func occurrence(
        at date: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> BaseOccurrence {
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .weekday],
            from: date
        )
        components.calendar = calendar
        components.timeZone = timeZone
        return BaseOccurrence(instant: date, sourceComponents: components)
    }

    private func emptySequence() -> AnySequence<BaseOccurrence> {
        AnySequence(EmptyCollection())
    }
}

private struct RecurrenceMapping {
    let rule: Calendar.RecurrenceRule
    let fixedYearlyDate: FixedYearlyDate?

    init(rule: Calendar.RecurrenceRule, fixedYearlyDate: FixedYearlyDate? = nil) {
        self.rule = rule
        self.fixedYearlyDate = fixedYearlyDate
    }
}

private struct FixedYearlyDate {
    let month: Int
    let day: Int
}

private struct SelectorFields {
    let daysOfTheMonth: [Int]
    let weekdays: [Calendar.RecurrenceRule.Weekday]
    let setPositions: [Int]

    init(
        daysOfTheMonth: [Int] = [],
        weekdays: [Calendar.RecurrenceRule.Weekday] = [],
        setPositions: [Int] = []
    ) {
        self.daysOfTheMonth = daysOfTheMonth
        self.weekdays = weekdays
        self.setPositions = setPositions
    }
}
