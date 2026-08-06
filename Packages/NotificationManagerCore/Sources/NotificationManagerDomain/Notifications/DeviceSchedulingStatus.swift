public enum DeviceAuthorizationSchedulingState: Sendable, Equatable {
    case allowed
    case notDetermined
    case denied
    case unknown
}

public enum DeviceSchedulingStatus: Sendable, Equatable {
    case notApplicable
    case notScheduledThisDeviceOff
    case permissionNotDetermined
    case notScheduledPermissionDenied
    case notScheduledAuthorizationUnknown
    case unscheduledError
    case scheduling
    case unscheduledCapacity
    case scheduled

    public static func resolve(_ input: DeviceSchedulingStatusInput) -> Self {
        guard input.lifecycleStatus == .active else { return .notApplicable }
        guard input.deviceNotificationsEnabled else { return .notScheduledThisDeviceOff }

        switch input.authorization {
        case .notDetermined:
            return .permissionNotDetermined
        case .denied:
            return .notScheduledPermissionDenied
        case .unknown:
            return .notScheduledAuthorizationUnknown
        case .allowed:
            break
        }

        if input.earliestGroupOutcome == .unscheduledError { return .unscheduledError }
        if input.reconcileInProgressOrQueued { return .scheduling }
        if input.earliestGroupOutcome == .unscheduledCapacity { return .unscheduledCapacity }
        if input.earliestRequestPresentOrLatestAddSucceeded { return .scheduled }
        return .scheduling
    }
}

public struct DeviceSchedulingStatusInput: Sendable, Equatable {
    public let lifecycleStatus: LifecycleStatus
    public let deviceNotificationsEnabled: Bool
    public let authorization: DeviceAuthorizationSchedulingState
    public let earliestGroupOutcome: AlertGroupSchedulingOutcome?
    public let laterGroupOutcomes: [AlertGroupSchedulingOutcome]
    public let reconcileInProgressOrQueued: Bool
    public let earliestRequestPresentOrLatestAddSucceeded: Bool

    public init(
        lifecycleStatus: LifecycleStatus,
        deviceNotificationsEnabled: Bool,
        authorization: DeviceAuthorizationSchedulingState,
        earliestGroupOutcome: AlertGroupSchedulingOutcome?,
        laterGroupOutcomes: [AlertGroupSchedulingOutcome],
        reconcileInProgressOrQueued: Bool,
        earliestRequestPresentOrLatestAddSucceeded: Bool
    ) {
        self.lifecycleStatus = lifecycleStatus
        self.deviceNotificationsEnabled = deviceNotificationsEnabled
        self.authorization = authorization
        self.earliestGroupOutcome = earliestGroupOutcome
        self.laterGroupOutcomes = laterGroupOutcomes
        self.reconcileInProgressOrQueued = reconcileInProgressOrQueued
        self.earliestRequestPresentOrLatestAddSucceeded = earliestRequestPresentOrLatestAddSucceeded
    }
}
