import Foundation

public enum NextNotificationProviderError: Error, Sendable, Equatable {
    case invalidSchedule([ScheduleValidationIssue])
    case invalidEvaluationNow
    case arithmeticOverflow
}

public struct NextNotificationResult: Sendable, Equatable {
    public let notifications: [PhysicalNotification]
    public let exhausted: Bool
    public let didSkipPastEarly: Bool
    public let observedFoundationResultCount: Int

    public init(
        notifications: [PhysicalNotification],
        exhausted: Bool,
        didSkipPastEarly: Bool,
        observedFoundationResultCount: Int
    ) {
        self.notifications = notifications
        self.exhausted = exhausted
        self.didSkipPastEarly = didSkipPastEarly
        self.observedFoundationResultCount = observedFoundationResultCount
    }
}

public struct NextNotificationProvider: Sendable {
    private static let maximumPreviewCount = 3

    public init() {}

    public func nextPhysicalNotifications(
        for reminderID: UUID,
        schedule: ScheduleDefinition,
        after evaluationNow: Date,
        limit: Int = 3,
        environment: any RecurrenceEnvironment
    ) throws -> NextNotificationResult {
        let issues = ReminderAggregateValidator().scheduleIssues(for: schedule)
        guard issues.isEmpty else {
            throw NextNotificationProviderError.invalidSchedule(issues)
        }
        guard evaluationNow.timeIntervalSinceReferenceDate.isFinite else {
            throw NextNotificationProviderError.invalidEvaluationNow
        }

        let requestedCount = min(max(limit, 0), Self.maximumPreviewCount)
        guard requestedCount > 0 else {
            return NextNotificationResult(
                notifications: [],
                exhausted: false,
                didSkipPastEarly: false,
                observedFoundationResultCount: 0
            )
        }

        guard let timeZone = environment.timeZone(identifier: schedule.source.timeZoneIdentifier) else {
            throw SourceWallClockResolutionError.unknownTimeZone
        }
        let calendar = environment.gregorianCalendar(in: timeZone)
        let range = try recurrenceRange(
            schedule: schedule,
            evaluationNow: evaluationNow,
            calendar: calendar
        )
        guard let range else {
            return NextNotificationResult(
                notifications: [],
                exhausted: true,
                didSkipPastEarly: false,
                observedFoundationResultCount: 0
            )
        }

        let observations = FoundationCandidateObservationCounter()
        let engine = FoundationRecurrenceEngine(observe: observations.record)
        let sequence = try engine.baseOccurrences(
            for: schedule,
            in: range,
            environment: environment
        )
        var groups = AlertGroupCursor(
            baseOccurrences: sequence.makeIterator(),
            schedule: schedule,
            calendar: calendar
        )

        var bufferedGroup = try groups.next()
        var pendingAlerts: [EffectiveAlert] = []
        var notifications: [PhysicalNotification] = []
        var didSkipPastEarly = false

        while notifications.count < requestedCount {
            if pendingAlerts.isEmpty {
                guard let group = bufferedGroup else { break }
                pendingAlerts.append(contentsOf: group.alerts)
                bufferedGroup = try groups.next()
            }

            guard let pendingInstant = pendingAlerts.map(\.alertInstant).min() else {
                continue
            }
            if let group = bufferedGroup,
               let groupInstant = group.alerts.map(\.alertInstant).min(),
               groupInstant <= pendingInstant
            {
                pendingAlerts.append(contentsOf: group.alerts)
                bufferedGroup = try groups.next()
                continue
            }

            let reasons = pendingAlerts.filter { $0.alertInstant == pendingInstant }
            pendingAlerts.removeAll { $0.alertInstant == pendingInstant }
            guard pendingInstant > evaluationNow else {
                if reasons.contains(where: { $0.kind == .early }) {
                    didSkipPastEarly = true
                }
                continue
            }

            notifications.append(PhysicalNotification(
                reminderID: reminderID,
                alertInstant: pendingInstant,
                reasons: reasons
            ))
        }

        return NextNotificationResult(
            notifications: notifications,
            exhausted: bufferedGroup == nil && pendingAlerts.isEmpty,
            didSkipPastEarly: didSkipPastEarly,
            observedFoundationResultCount: observations.count
        )
    }

    private func recurrenceRange(
        schedule: ScheduleDefinition,
        evaluationNow: Date,
        calendar: Calendar
    ) throws -> Range<Date>? {
        guard let supportedLowerBound = calendar.date(
            from: DateComponents(year: 1, month: 1, day: 1, hour: 0, minute: 0, second: 0)
        ), let supportedUpperBound = calendar.date(
            from: DateComponents(year: 10_000, month: 1, day: 1, hour: 0, minute: 0, second: 0)
        ) else {
            throw NextNotificationProviderError.arithmeticOverflow
        }

        let anchor = try SourceWallClockResolver().resolve(schedule.source, calendar: calendar)
        var candidates: [Date] = []
        if schedule.early?.mainEnabled != false {
            candidates.append(evaluationNow)
        }
        if let early = schedule.early {
            candidates.append(try baseCandidate(
                after: evaluationNow,
                early: early,
                rule: schedule.rule,
                calendar: calendar
            ))
        }
        guard let candidate = candidates.min() else {
            return nil
        }

        let proposedLowerBound: Date
        switch schedule.rule {
        case .none:
            proposedLowerBound = min(anchor, candidate)
        case let .hourly(interval):
            proposedLowerBound = try addingFixedSeconds(
                -Int64(interval) * 3_600,
                to: candidate
            )
        case let .daily(interval):
            proposedLowerBound = try addingCalendar(
                .day,
                value: -interval,
                to: candidate,
                calendar: calendar
            )
        case let .weekly(interval, _, _):
            proposedLowerBound = try addingCalendar(
                .weekOfYear,
                value: -interval,
                to: candidate,
                calendar: calendar
            )
        case let .monthly(interval, _):
            proposedLowerBound = try addingCalendar(
                .month,
                value: -interval,
                to: candidate,
                calendar: calendar
            )
        case let .yearly(interval, _, _):
            proposedLowerBound = try addingCalendar(
                .year,
                value: -interval,
                to: candidate,
                calendar: calendar
            )
        }

        let lowerBound = max(supportedLowerBound, proposedLowerBound)
        guard lowerBound < supportedUpperBound else { return nil }
        return lowerBound..<supportedUpperBound
    }

    private func baseCandidate(
        after evaluationNow: Date,
        early: EarlyReminder,
        rule: RepeatRule,
        calendar: Calendar
    ) throws -> Date {
        switch (early.unit, rule) {
        case (.days, .hourly):
            return try addingFixedSeconds(Int64(early.value) * 86_400, to: evaluationNow)
        case (.weeks, .hourly):
            return try addingFixedSeconds(Int64(early.value) * 604_800, to: evaluationNow)
        case (.days, _):
            return try addingCalendar(.day, value: early.value, to: evaluationNow, calendar: calendar)
        case (.weeks, _):
            return try addingCalendar(
                .weekOfYear,
                value: early.value,
                to: evaluationNow,
                calendar: calendar
            )
        case (.minutes, _):
            return try addingFixedSeconds(Int64(early.value) * 60, to: evaluationNow)
        case (.hours, _):
            return try addingFixedSeconds(Int64(early.value) * 3_600, to: evaluationNow)
        }
    }

    private func addingFixedSeconds(_ seconds: Int64, to date: Date) throws -> Date {
        let result = date.addingTimeInterval(Double(seconds))
        guard result.timeIntervalSinceReferenceDate.isFinite else {
            throw NextNotificationProviderError.arithmeticOverflow
        }
        return result
    }

    private func addingCalendar(
        _ component: Calendar.Component,
        value: Int,
        to date: Date,
        calendar: Calendar
    ) throws -> Date {
        guard let result = calendar.date(byAdding: component, value: value, to: date) else {
            throw NextNotificationProviderError.arithmeticOverflow
        }
        return result
    }
}

private final class FoundationCandidateObservationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCount = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedCount
    }

    func record(_ observation: FoundationRecurrenceObservation) {
        guard case .candidate = observation else { return }
        lock.lock()
        recordedCount += 1
        lock.unlock()
    }
}
