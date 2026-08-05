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
        hasFutureAlert: Bool
    ) -> ReminderStatus {
        var statuses: [LifecycleStatus] = []

        switch schedule {
        case .unsupportedFuture:
            statuses.append(.updateRequired)
        case .corrupt, .domainInvalid:
            statuses.append(.invalidSchedule)
        case .valid:
            break
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
