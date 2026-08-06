import Foundation
import NotificationManagerDomain

public enum SchedulingGlobalFailure: Sendable, Equatable {
    case snapshot
    case planning
    case inventory
}

public enum MaterializedNotificationKind: Sendable, Equatable {
    case oneShot
    case repeating
}

public struct DeviceSchedulingStateSnapshot: Sendable, Equatable {
    public let generation: UInt64
    public let reconcileInProgressOrQueued: Bool
    public let globalFailure: SchedulingGlobalFailure?
    public let deviceNotificationsEnabled: Bool
    public let authorization: NotificationAuthorizationSnapshot
    public let outcomes: [AlertGroupID: AlertGroupSchedulingOutcome]
    public let scheduledThrough: [UUID: Date]
    public let materializedKinds: [String: MaterializedNotificationKind]
    public let pendingOrAddedIdentifiers: Set<String>

    public init(
        generation: UInt64,
        reconcileInProgressOrQueued: Bool,
        globalFailure: SchedulingGlobalFailure?,
        deviceNotificationsEnabled: Bool,
        authorization: NotificationAuthorizationSnapshot,
        outcomes: [AlertGroupID: AlertGroupSchedulingOutcome],
        scheduledThrough: [UUID: Date],
        materializedKinds: [String: MaterializedNotificationKind],
        pendingOrAddedIdentifiers: Set<String>
    ) {
        self.generation = generation
        self.reconcileInProgressOrQueued = reconcileInProgressOrQueued
        self.globalFailure = globalFailure
        self.deviceNotificationsEnabled = deviceNotificationsEnabled
        self.authorization = authorization
        self.outcomes = outcomes
        self.scheduledThrough = scheduledThrough
        self.materializedKinds = materializedKinds
        self.pendingOrAddedIdentifiers = pendingOrAddedIdentifiers
    }
}

public actor DeviceSchedulingStateStore {
    private var current = DeviceSchedulingStateSnapshot(
        generation: 0,
        reconcileInProgressOrQueued: false,
        globalFailure: nil,
        deviceNotificationsEnabled: false,
        authorization: NotificationAuthorizationSnapshot(
            state: .notDetermined,
            diagnostic: nil
        ),
        outcomes: [:],
        scheduledThrough: [:],
        materializedKinds: [:],
        pendingOrAddedIdentifiers: []
    )

    public init() {}

    public func snapshot() -> DeviceSchedulingStateSnapshot { current }

    public func outcome(for groupID: AlertGroupID) -> AlertGroupSchedulingOutcome? {
        current.outcomes[groupID]
    }

    func setReconcileInProgressOrQueued(_ value: Bool) {
        current = DeviceSchedulingStateSnapshot(
            generation: current.generation,
            reconcileInProgressOrQueued: value,
            globalFailure: current.globalFailure,
            deviceNotificationsEnabled: current.deviceNotificationsEnabled,
            authorization: current.authorization,
            outcomes: current.outcomes,
            scheduledThrough: current.scheduledThrough,
            materializedKinds: current.materializedKinds,
            pendingOrAddedIdentifiers: current.pendingOrAddedIdentifiers
        )
    }

    func publishFailure(_ failure: SchedulingGlobalFailure) {
        current = DeviceSchedulingStateSnapshot(
            generation: current.generation &+ 1,
            reconcileInProgressOrQueued: current.reconcileInProgressOrQueued,
            globalFailure: failure,
            deviceNotificationsEnabled: current.deviceNotificationsEnabled,
            authorization: current.authorization,
            outcomes: current.outcomes,
            scheduledThrough: current.scheduledThrough,
            materializedKinds: current.materializedKinds,
            pendingOrAddedIdentifiers: current.pendingOrAddedIdentifiers
        )
    }

    func publish(
        deviceNotificationsEnabled: Bool,
        authorization: NotificationAuthorizationSnapshot,
        outcomes: [AlertGroupID: AlertGroupSchedulingOutcome],
        scheduledThrough: [UUID: Date],
        materializedKinds: [String: MaterializedNotificationKind],
        pendingOrAddedIdentifiers: Set<String>
    ) {
        current = DeviceSchedulingStateSnapshot(
            generation: current.generation &+ 1,
            reconcileInProgressOrQueued: current.reconcileInProgressOrQueued,
            globalFailure: nil,
            deviceNotificationsEnabled: deviceNotificationsEnabled,
            authorization: authorization,
            outcomes: outcomes,
            scheduledThrough: scheduledThrough,
            materializedKinds: materializedKinds,
            pendingOrAddedIdentifiers: pendingOrAddedIdentifiers
        )
    }

}
