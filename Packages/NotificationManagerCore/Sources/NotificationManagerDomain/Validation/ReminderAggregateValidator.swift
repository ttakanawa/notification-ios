import Foundation

public enum ReminderLimits {
    public static let titleBytes = 512
    public static let notesBytes = 65_536
    public static let urlBytes = 2_048
    public static let scheduleBytes = 16 * 1_024
    public static let aggregateBytes = 96 * 1_024
    public static let tagCount = 100
}

public enum ReminderValidationIssue: Error, Sendable, Equatable {
    case titleEmpty
    case titleTooLarge
    case notesTooLarge
    case invalidURL
    case urlTooLarge
    case missingScheduleData
    case replacementScheduleDataRequired
    case scheduleFieldsDoNotMatchReplacement
    case scheduleTooLarge
    case aggregateTooLarge
    case tooManyTags
    case invalidCreatedAt
    case invalidUpdatedAt
    case invalidSchedule
}

public struct ValidatedReminderAggregate: Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let notes: String?
    public let urlString: String?
    public let enabled: Bool
    public let scheduleData: Data
    public let tagIDs: Set<UUID>
    public let createdAt: Date
    public let updatedAt: Date
}

public struct ReminderAggregateValidator: Sendable {
    public init() {}

    @discardableResult
    public func validate(_ draft: ReminderDraft) throws -> ValidatedReminderAggregate {
        try validateDraft(draft, replacementScheduleData: nil)
    }

    @discardableResult
    public func validate(
        _ draft: ReminderDraft,
        replacementScheduleData: Data
    ) throws -> ValidatedReminderAggregate {
        try validateDraft(draft, replacementScheduleData: replacementScheduleData)
    }

    private func validateDraft(
        _ draft: ReminderDraft,
        replacementScheduleData: Data?
    ) throws -> ValidatedReminderAggregate {
        let titleBytes = draft.title.utf8.count
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReminderValidationIssue.titleEmpty
        }
        guard titleBytes <= ReminderLimits.titleBytes else {
            throw ReminderValidationIssue.titleTooLarge
        }

        let notesBytes = draft.notes?.utf8.count ?? 0
        guard notesBytes <= ReminderLimits.notesBytes else {
            throw ReminderValidationIssue.notesTooLarge
        }

        let canonicalURLString: String?
        let urlBytes: Int
        if let urlString = draft.urlString {
            let canonicalURL: CanonicalHTTPURL
            do {
                canonicalURL = try CanonicalHTTPURL(urlString)
            } catch {
                throw ReminderValidationIssue.invalidURL
            }
            canonicalURLString = canonicalURL.string
            urlBytes = canonicalURL.string.utf8.count
            guard urlBytes <= ReminderLimits.urlBytes else {
                throw ReminderValidationIssue.urlTooLarge
            }
        } else {
            canonicalURLString = nil
            urlBytes = 0
        }

        let scheduleData: Data
        switch draft.scheduleChange {
        case .preserveOriginal:
            guard let originalScheduleData = draft.originalScheduleData else {
                throw ReminderValidationIssue.missingScheduleData
            }
            scheduleData = originalScheduleData
        case let .replace(schedule):
            guard let source = draft.source,
                  ScheduleDefinition(
                      source: source,
                      rule: draft.rule,
                      end: draft.end,
                      early: draft.early
                  ) == schedule
            else {
                throw ReminderValidationIssue.scheduleFieldsDoNotMatchReplacement
            }
            guard scheduleIssues(for: schedule).isEmpty else {
                throw ReminderValidationIssue.invalidSchedule
            }
            guard let replacementScheduleData else {
                throw ReminderValidationIssue.replacementScheduleDataRequired
            }
            scheduleData = replacementScheduleData
        }
        let scheduleBytes = scheduleData.count
        guard scheduleBytes <= ReminderLimits.scheduleBytes else {
            throw ReminderValidationIssue.scheduleTooLarge
        }

        guard titleBytes + notesBytes + urlBytes + scheduleBytes <= ReminderLimits.aggregateBytes else {
            throw ReminderValidationIssue.aggregateTooLarge
        }
        guard draft.tagIDs.count <= ReminderLimits.tagCount else {
            throw ReminderValidationIssue.tooManyTags
        }
        guard Self.isFiniteIntegralSecond(draft.createdAt) else {
            throw ReminderValidationIssue.invalidCreatedAt
        }
        guard Self.isFiniteIntegralSecond(draft.updatedAt) else {
            throw ReminderValidationIssue.invalidUpdatedAt
        }

        return ValidatedReminderAggregate(
            id: draft.id,
            title: draft.title,
            notes: draft.notes,
            urlString: canonicalURLString,
            enabled: draft.enabled,
            scheduleData: scheduleData,
            tagIDs: draft.tagIDs,
            createdAt: draft.createdAt,
            updatedAt: draft.updatedAt
        )
    }

    public func scheduleIssues(for schedule: ScheduleDefinition) -> [ScheduleValidationIssue] {
        var issues = sourceIssues(for: schedule.source)
        issues.append(contentsOf: ruleIssues(for: schedule.rule))
        issues.append(contentsOf: endIssues(for: schedule.end, source: schedule.source, rule: schedule.rule))

        if let early = schedule.early, !(1...9_999).contains(early.value) {
            issues.append(.earlyValueOutOfRange)
        }
        return issues
    }

    private func sourceIssues(for source: SourceWallClock) -> [ScheduleValidationIssue] {
        var issues: [ScheduleValidationIssue] = []
        if !(1...9_999).contains(source.year) { issues.append(.invalidSourceYear) }
        if !(1...12).contains(source.month) { issues.append(.invalidSourceMonth) }
        if !Self.isValidDate(year: source.year, month: source.month, day: source.day) {
            issues.append(.invalidSourceDay)
        }
        if !(0...23).contains(source.hour) { issues.append(.invalidSourceHour) }
        if !(0...59).contains(source.minute) { issues.append(.invalidSourceMinute) }
        if !Self.knownTimeZoneIdentifiers.contains(source.timeZoneIdentifier)
            || TimeZone(identifier: source.timeZoneIdentifier) == nil
        {
            issues.append(.invalidTimeZone)
        }
        return issues
    }

    private func ruleIssues(for rule: RepeatRule) -> [ScheduleValidationIssue] {
        switch rule {
        case .none:
            return []
        case let .hourly(interval), let .daily(interval):
            return Self.intervalIsValid(interval) ? [] : [.intervalOutOfRange]
        case let .weekly(interval, kind, weekdays):
            var issues: [ScheduleValidationIssue] = []
            if !Self.intervalIsValid(interval) { issues.append(.intervalOutOfRange) }
            if !Self.isValidWeekdaySet(kind: kind, weekdays: weekdays) {
                issues.append(.invalidWeekdaySet)
            }
            return issues
        case let .monthly(interval, selector):
            var issues: [ScheduleValidationIssue] = []
            if !Self.intervalIsValid(interval) { issues.append(.intervalOutOfRange) }
            if !Self.isValidMonthlySelector(selector) { issues.append(.invalidSelector) }
            return issues
        case let .yearly(interval, month, selector):
            var issues: [ScheduleValidationIssue] = []
            if !Self.intervalIsValid(interval) { issues.append(.intervalOutOfRange) }
            if let month, !(1...12).contains(month) { issues.append(.invalidMonth) }
            if !Self.isValidYearlySelector(selector, month: month) {
                issues.append(.invalidSelector)
            }
            return issues
        }
    }

    private func endIssues(
        for end: RepeatEnd,
        source: SourceWallClock,
        rule: RepeatRule
    ) -> [ScheduleValidationIssue] {
        switch end {
        case .never:
            return []
        case let .onDate(date):
            if case .none = rule { return [.endNotAllowed] }
            guard Self.isValidDate(year: date.year, month: date.month, day: date.day) else {
                return [.invalidEndDate]
            }
            let start = (source.year, source.month, source.day)
            let end = (date.year, date.month, date.day)
            if end.0 < start.0
                || (end.0 == start.0 && end.1 < start.1)
                || (end.0 == start.0 && end.1 == start.1 && end.2 < start.2)
            {
                return [.endBeforeStart]
            }
            return []
        }
    }

    private static let knownTimeZoneIdentifiers = Set(TimeZone.knownTimeZoneIdentifiers)

    private static func intervalIsValid(_ interval: Int) -> Bool {
        (1...9_999).contains(interval)
    }

    private static func isValidWeekdaySet(kind: WeekdaySetKind, weekdays: [Weekday]) -> Bool {
        guard !weekdays.isEmpty,
              Set(weekdays).count == weekdays.count,
              weekdays == weekdays.sorted(by: { $0.rawValue < $1.rawValue })
        else {
            return false
        }
        switch kind {
        case .explicit:
            return true
        case .weekday:
            return weekdays == [.monday, .tuesday, .wednesday, .thursday, .friday]
        case .weekend:
            return weekdays == [.saturday, .sunday]
        }
    }

    private static func isValidMonthlySelector(_ selector: RepeatSelector) -> Bool {
        switch selector {
        case .anchorDay, .lastDay:
            return true
        case let .dayOfMonth(day):
            return (1...31).contains(day)
        case let .ordinalDaySet(ordinal, _):
            return (1...5).contains(ordinal)
        case let .ordinalWeekday(ordinal, _):
            return (-5 ... -1).contains(ordinal) || (1...5).contains(ordinal)
        case .anchorMonthDay:
            return false
        }
    }

    private static func isValidYearlySelector(_ selector: RepeatSelector, month: Int?) -> Bool {
        guard let month else {
            return selector == .anchorMonthDay
        }
        guard (1...12).contains(month) else { return false }
        switch selector {
        case let .dayOfMonth(day):
            return isValidDate(year: 2_000, month: month, day: day)
        case .lastDay:
            return true
        case let .ordinalDaySet(ordinal, _):
            return (1...5).contains(ordinal)
        case let .ordinalWeekday(ordinal, _):
            return (-5 ... -1).contains(ordinal) || (1...5).contains(ordinal)
        case .anchorDay, .anchorMonthDay:
            return false
        }
    }

    private static func isValidDate(year: Int, month: Int, day: Int) -> Bool {
        guard (1...9_999).contains(year), (1...12).contains(month), day >= 1 else {
            return false
        }
        let daysInMonth: Int
        switch month {
        case 2:
            let isLeapYear = year.isMultiple(of: 4)
                && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
            daysInMonth = isLeapYear ? 29 : 28
        case 4, 6, 9, 11:
            daysInMonth = 30
        default:
            daysInMonth = 31
        }
        return day <= daysInMonth
    }

    private static func isFiniteIntegralSecond(_ date: Date) -> Bool {
        let seconds = date.timeIntervalSinceReferenceDate
        return seconds.isFinite && seconds.rounded(.towardZero) == seconds
    }
}
