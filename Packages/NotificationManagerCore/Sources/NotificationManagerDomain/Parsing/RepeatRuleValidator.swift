public enum RepeatCandidateValidationError: Error, Sendable, Equatable {
    case unsupported
    case intervalOutOfRange
    case invalidCombination
    case invalidSelector
    case invalidSourceDate
}

public struct RepeatRuleValidator: Sendable {
    public init() {}

    public func validate(
        _ candidate: RepeatCandidate,
        source: SourceWallClock
    ) throws -> RepeatRule {
        guard candidate.isSupported else {
            throw RepeatCandidateValidationError.unsupported
        }
        guard (1...9_999).contains(candidate.interval) else {
            throw RepeatCandidateValidationError.intervalOutOfRange
        }

        switch candidate.frequency {
        case .hourly:
            try requireNoRecurrenceFields(candidate)
            return .hourly(interval: candidate.interval)
        case .daily:
            try requireNoRecurrenceFields(candidate)
            return .daily(interval: candidate.interval)
        case .weekly:
            guard candidate.month == nil, candidate.selector == nil else {
                throw RepeatCandidateValidationError.invalidCombination
            }
            if candidate.weekdaySetKind == nil, candidate.weekdays.isEmpty {
                guard
                    let weekday = GregorianDate.weekday(
                        year: source.year,
                        month: source.month,
                        day: source.day
                    )
                else {
                    throw RepeatCandidateValidationError.invalidSourceDate
                }
                return .weekly(
                    interval: candidate.interval,
                    weekdaySetKind: .explicit,
                    weekdays: [weekday]
                )
            }
            guard let kind = candidate.weekdaySetKind, !candidate.weekdays.isEmpty else {
                throw RepeatCandidateValidationError.invalidCombination
            }
            guard candidate.interval == 1 else {
                throw RepeatCandidateValidationError.invalidCombination
            }
            let weekdays = Array(Set(candidate.weekdays)).sorted { $0.rawValue < $1.rawValue }
            switch kind {
            case .explicit:
                break
            case .weekday:
                guard weekdays == [.monday, .tuesday, .wednesday, .thursday, .friday] else {
                    throw RepeatCandidateValidationError.invalidCombination
                }
            case .weekend:
                guard weekdays == [.saturday, .sunday] else {
                    throw RepeatCandidateValidationError.invalidCombination
                }
            }
            return .weekly(
                interval: candidate.interval,
                weekdaySetKind: kind,
                weekdays: weekdays
            )
        case .monthly:
            guard candidate.weekdaySetKind == nil, candidate.weekdays.isEmpty,
                candidate.month == nil, let selector = candidate.selector
            else {
                throw RepeatCandidateValidationError.invalidCombination
            }
            guard isValidMonthlySelector(selector) else {
                throw RepeatCandidateValidationError.invalidSelector
            }
            return .monthly(interval: candidate.interval, selector: domainSelector(selector))
        case .yearly:
            guard candidate.weekdaySetKind == nil, candidate.weekdays.isEmpty,
                let selector = candidate.selector
            else {
                throw RepeatCandidateValidationError.invalidCombination
            }
            if candidate.month == nil {
                guard selector == .anchorMonthDay else {
                    throw RepeatCandidateValidationError.invalidCombination
                }
            } else {
                guard let month = candidate.month, (1...12).contains(month),
                    isValidYearlySelector(selector, month: month)
                else {
                    throw RepeatCandidateValidationError.invalidSelector
                }
            }
            return .yearly(
                interval: candidate.interval,
                month: candidate.month,
                selector: domainSelector(selector)
            )
        }
    }

    private func requireNoRecurrenceFields(_ candidate: RepeatCandidate) throws {
        guard candidate.weekdaySetKind == nil, candidate.weekdays.isEmpty,
            candidate.month == nil, candidate.selector == nil
        else {
            throw RepeatCandidateValidationError.invalidCombination
        }
    }

    private func isValidMonthlySelector(_ selector: RepeatCandidateSelector) -> Bool {
        switch selector {
        case .anchorDay, .lastDay:
            true
        case .dayOfMonth(let day):
            (1...31).contains(day)
        case .ordinalDaySet(let ordinal, _):
            (1...5).contains(ordinal)
        case .ordinalWeekday(let ordinal, _):
            (-5 ... -1).contains(ordinal) || (1...5).contains(ordinal)
        case .anchorMonthDay:
            false
        }
    }

    private func isValidYearlySelector(
        _ selector: RepeatCandidateSelector,
        month: Int
    ) -> Bool {
        switch selector {
        case .dayOfMonth(let day):
            GregorianDate.isPotentiallyValid(month: month, day: day)
        case .lastDay:
            true
        case .ordinalDaySet(let ordinal, _):
            (1...5).contains(ordinal)
        case .ordinalWeekday(let ordinal, _):
            (-5 ... -1).contains(ordinal) || (1...5).contains(ordinal)
        case .anchorDay, .anchorMonthDay:
            false
        }
    }

    private func domainSelector(_ selector: RepeatCandidateSelector) -> RepeatSelector {
        switch selector {
        case .anchorDay:
            .anchorDay
        case .anchorMonthDay:
            .anchorMonthDay
        case .dayOfMonth(let day):
            .dayOfMonth(day)
        case .lastDay:
            .lastDay
        case .ordinalDaySet(let ordinal, let daySet):
            .ordinalDaySet(ordinal: ordinal, daySet: daySet)
        case .ordinalWeekday(let ordinal, let weekday):
            .ordinalWeekday(ordinal: ordinal, weekday: weekday)
        }
    }
}

enum GregorianDate {
    static func weekday(year: Int, month: Int, day: Int) -> Weekday? {
        guard (1...9_999).contains(year), (1...12).contains(month),
            isValid(year: year, month: month, day: day)
        else {
            return nil
        }

        var adjustedYear = year
        var adjustedMonth = month
        if adjustedMonth < 3 {
            adjustedYear -= 1
            adjustedMonth += 12
        }
        let era = floorDivision(adjustedYear, by: 400)
        let yearOfEra = adjustedYear - era * 400
        let dayOfYear = (153 * (adjustedMonth - 3) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        let daysSinceMonday = era * 146_097 + dayOfEra - 306
        let mondayBased = positiveModulo(daysSinceMonday, by: 7) + 1
        return Weekday(rawValue: mondayBased)
    }

    static func isPotentiallyValid(month: Int, day: Int) -> Bool {
        guard (1...12).contains(month), day >= 1 else { return false }
        let maximum =
            switch month {
            case 2: 29
            case 4, 6, 9, 11: 30
            default: 31
            }
        return day <= maximum
    }

    private static func isValid(year: Int, month: Int, day: Int) -> Bool {
        guard isPotentiallyValid(month: month, day: day) else { return false }
        if month == 2, day == 29 {
            return year.isMultiple(of: 4)
                && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
        }
        return true
    }

    private static func floorDivision(_ value: Int, by divisor: Int) -> Int {
        let quotient = value / divisor
        let remainder = value % divisor
        return remainder < 0 ? quotient - 1 : quotient
    }

    private static func positiveModulo(_ value: Int, by divisor: Int) -> Int {
        let remainder = value % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }
}
