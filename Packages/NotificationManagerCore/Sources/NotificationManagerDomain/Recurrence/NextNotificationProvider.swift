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

        guard let timeZone = environment.timeZone(identifier: schedule.source.timeZoneIdentifier)
        else {
            throw SourceWallClockResolutionError.unknownTimeZone
        }
        let calendar = environment.gregorianCalendar(in: timeZone)
        let observations = FoundationCandidateObservationCounter()
        let engine = FoundationRecurrenceEngine(observe: observations.record)
        var streams = try alertStreams(
            schedule: schedule,
            evaluationNow: evaluationNow,
            calendar: calendar,
            engine: engine,
            environment: environment
        )

        var heads: [EffectiveAlert?] = []
        for index in streams.indices {
            heads.append(try streams[index].next())
        }
        var notifications: [PhysicalNotification] = []
        var didSkipPastEarly = false

        while notifications.count < requestedCount {
            guard let pendingInstant = heads.compactMap({ $0?.alertInstant }).min() else { break }
            var reasons: [EffectiveAlert] = []
            for index in streams.indices {
                while let head = heads[index], head.alertInstant == pendingInstant {
                    reasons.append(head)
                    heads[index] = try streams[index].next()
                }
            }
            guard pendingInstant > evaluationNow else {
                if reasons.contains(where: { $0.kind == .early }) {
                    didSkipPastEarly = true
                }
                continue
            }

            if let early = schedule.early {
                for reason in reasons where reason.kind == .main {
                    if try earlyAlertInstant(
                        for: reason.baseOccurrence.instant,
                        early: early,
                        rule: schedule.rule,
                        calendar: calendar
                    ) <= evaluationNow {
                        didSkipPastEarly = true
                    }
                }
            }

            notifications.append(
                PhysicalNotification(
                    reminderID: reminderID,
                    alertInstant: pendingInstant,
                    reasons: reasons
                ))
        }

        return NextNotificationResult(
            notifications: notifications,
            exhausted: heads.allSatisfy { $0 == nil },
            didSkipPastEarly: didSkipPastEarly,
            observedFoundationResultCount: observations.count
        )
    }

    private func alertStreams(
        schedule: ScheduleDefinition,
        evaluationNow: Date,
        calendar: Calendar,
        engine: FoundationRecurrenceEngine,
        environment: any RecurrenceEnvironment
    ) throws -> [AlertPathStream] {
        var streams: [AlertPathStream] = []
        if schedule.early?.mainEnabled != false {
            let mainSchedule = ScheduleDefinition(
                source: schedule.source,
                rule: schedule.rule,
                end: schedule.end,
                early: nil
            )
            if let stream = try alertStream(
                schedule: mainSchedule,
                evaluationNow: evaluationNow,
                calendar: calendar,
                engine: engine,
                environment: environment
            ) {
                streams.append(stream)
            }
        }
        if let early = schedule.early {
            let earlySchedule = ScheduleDefinition(
                source: schedule.source,
                rule: schedule.rule,
                end: schedule.end,
                early: EarlyReminder(
                    value: early.value,
                    unit: early.unit,
                    mainEnabled: false
                )
            )
            if let stream = try alertStream(
                schedule: earlySchedule,
                evaluationNow: evaluationNow,
                calendar: calendar,
                engine: engine,
                environment: environment
            ) {
                streams.append(stream)
            }
        }
        return streams
    }

    private func alertStream(
        schedule: ScheduleDefinition,
        evaluationNow: Date,
        calendar: Calendar,
        engine: FoundationRecurrenceEngine,
        environment: any RecurrenceEnvironment
    ) throws -> AlertPathStream? {
        guard
            let range = try recurrenceRange(
                schedule: schedule,
                evaluationNow: evaluationNow,
                calendar: calendar
            )
        else {
            return nil
        }
        let sequence = try engine.baseOccurrences(
            for: schedule,
            in: range,
            environment: environment
        )
        return AlertPathStream(
            groups: AlertGroupCursor(
                baseOccurrences: sequence.makeIterator(),
                schedule: schedule,
                calendar: calendar
            ))
    }

    private func recurrenceRange(
        schedule: ScheduleDefinition,
        evaluationNow: Date,
        calendar: Calendar
    ) throws -> Range<Date>? {
        guard
            let supportedLowerBound = calendar.date(
                from: DateComponents(year: 1, month: 1, day: 1, hour: 0, minute: 0, second: 0)
            ),
            let supportedUpperBound = calendar.date(
                from: DateComponents(year: 10_000, month: 1, day: 1, hour: 0, minute: 0, second: 0)
            )
        else {
            throw NextNotificationProviderError.arithmeticOverflow
        }

        let anchor = try SourceWallClockResolver().resolve(schedule.source, calendar: calendar)
        var candidates: [Date] = []
        if schedule.early?.mainEnabled != false {
            candidates.append(evaluationNow)
        }
        if let early = schedule.early {
            candidates.append(
                try baseCandidate(
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
        case .hourly(let interval):
            proposedLowerBound = try addingFixedSeconds(
                -Int64(interval) * 3_600,
                to: candidate
            )
        case .daily(let interval):
            proposedLowerBound = try addingCalendar(
                .day,
                value: -interval,
                to: candidate,
                calendar: calendar
            )
        case .weekly(let interval, _, _):
            proposedLowerBound = try addingCalendar(
                .weekOfYear,
                value: -interval,
                to: candidate,
                calendar: calendar
            )
        case .monthly(let interval, _):
            proposedLowerBound = try addingCalendar(
                .month,
                value: -interval,
                to: candidate,
                calendar: calendar
            )
        case .yearly(let interval, _, _):
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
        case (.seconds, _):
            return try addingFixedSeconds(Int64(early.value), to: evaluationNow)
        case (.days, .hourly):
            return try addingFixedSeconds(Int64(early.value) * 86_400, to: evaluationNow)
        case (.weeks, .hourly):
            return try addingFixedSeconds(Int64(early.value) * 604_800, to: evaluationNow)
        case (.days, _):
            return try addingCalendar(
                .day, value: early.value, to: evaluationNow, calendar: calendar)
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

private struct AlertPathStream {
    var groups: AlertGroupCursor

    mutating func next() throws -> EffectiveAlert? {
        guard let group = try groups.next() else { return nil }
        precondition(group.alerts.count == 1, "An alert path must derive exactly one alert")
        return group.alerts[0]
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
