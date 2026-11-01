import Foundation

public enum LifecycleStatus: Sendable, Equatable {
    case updateRequired
    case invalidSchedule
    case disabled
    case expired
    case active
}

public struct ReminderStatus: Sendable, Equatable {
    public let primary: LifecycleStatus
    public let secondary: [LifecycleStatus]

    public init(primary: LifecycleStatus, secondary: [LifecycleStatus]) {
        self.primary = primary
        self.secondary = secondary
    }
}

public struct ReminderStatusCalculator: Sendable {
    public init() {}

    public func status(
        schedule: ScheduleReadState,
        enabled: Bool,
        after evaluationNow: Date,
        environment: any RecurrenceEnvironment
    ) throws -> ReminderStatus {
        var statuses: [LifecycleStatus] = []
        let isUnexpired: Bool

        switch schedule {
        case .unsupportedFuture:
            statuses.append(.updateRequired)
            isUnexpired = false
        case .corrupt, .domainInvalid:
            statuses.append(.invalidSchedule)
            isUnexpired = false
        case .valid(let definition, _, _):
            do {
                let result = try NextNotificationProvider().nextPhysicalNotifications(
                    for: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
                    schedule: definition,
                    after: evaluationNow,
                    limit: 1,
                    environment: environment
                )
                isUnexpired =
                    try !result.notifications.isEmpty
                    || hasOngoingRange(
                        schedule: definition,
                        at: evaluationNow,
                        environment: environment
                    )
            } catch let error as NextNotificationProviderError {
                switch error {
                case .invalidSchedule:
                    statuses.append(.invalidSchedule)
                    isUnexpired = false
                case .invalidEvaluationNow, .arithmeticOverflow:
                    throw error
                }
            } catch {
                throw error
            }
        }

        if !enabled {
            statuses.append(.disabled)
        }
        if !isUnexpired {
            statuses.append(.expired)
        }
        if statuses.isEmpty {
            statuses.append(.active)
        }

        return ReminderStatus(primary: statuses[0], secondary: Array(statuses.dropFirst()))
    }

    public func hasOngoingRange(
        schedule: ScheduleDefinition,
        at evaluationNow: Date,
        environment: any RecurrenceEnvironment
    ) throws -> Bool {
        guard let duration = schedule.durationSeconds else { return false }
        let issues = ReminderAggregateValidator().scheduleIssues(for: schedule)
        guard issues.isEmpty else { throw NextNotificationProviderError.invalidSchedule(issues) }
        let nowInterval = evaluationNow.timeIntervalSinceReferenceDate
        guard nowInterval.isFinite else { throw NextNotificationProviderError.invalidEvaluationNow }
        guard let timeZone = environment.timeZone(identifier: schedule.source.timeZoneIdentifier)
        else {
            throw SourceWallClockResolutionError.unknownTimeZone
        }
        let calendar = environment.gregorianCalendar(in: timeZone)
        let anchor = try SourceWallClockResolver().resolve(schedule.source, calendar: calendar)
        let lowerBound = max(
            anchor,
            Date(timeIntervalSinceReferenceDate: (nowInterval - Double(duration)).nextUp)
        )
        let upperBound = Date(timeIntervalSinceReferenceDate: nowInterval.nextUp)
        guard lowerBound < upperBound else { return false }
        let occurrences = try FoundationRecurrenceEngine().baseOccurrences(
            for: schedule,
            in: lowerBound..<upperBound,
            environment: environment
        )
        return occurrences.first { occurrence in
            occurrence.instant <= evaluationNow
                && occurrence.instant.addingTimeInterval(Double(duration)) > evaluationNow
        } != nil
    }
}
