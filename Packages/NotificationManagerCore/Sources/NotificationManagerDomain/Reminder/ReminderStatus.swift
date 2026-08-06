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
    ) -> ReminderStatus {
        var statuses: [LifecycleStatus] = []
        let hasFutureAlert: Bool

        switch schedule {
        case .unsupportedFuture:
            statuses.append(.updateRequired)
            hasFutureAlert = false
        case .corrupt, .domainInvalid:
            statuses.append(.invalidSchedule)
            hasFutureAlert = false
        case let .valid(definition, _, _):
            do {
                let result = try NextNotificationProvider().nextPhysicalNotifications(
                    for: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
                    schedule: definition,
                    after: evaluationNow,
                    limit: 1,
                    environment: environment
                )
                hasFutureAlert = !result.notifications.isEmpty
            } catch {
                statuses.append(.invalidSchedule)
                hasFutureAlert = false
            }
        }

        if !enabled {
            statuses.append(.disabled)
        }
        if !hasFutureAlert {
            statuses.append(.expired)
        }
        if statuses.isEmpty {
            statuses.append(.active)
        }

        return ReminderStatus(primary: statuses[0], secondary: Array(statuses.dropFirst()))
    }
}
