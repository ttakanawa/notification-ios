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
    public let nextTriggerDates: [String: Date]
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
        nextTriggerDates: [String: Date] = [:],
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
        self.nextTriggerDates = nextTriggerDates
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
        nextTriggerDates: [:],
        pendingOrAddedIdentifiers: []
    )
    private var updateContinuations: [
        UUID: AsyncStream<DeviceSchedulingStateSnapshot>.Continuation
    ] = [:]

    public init() {}

    public func snapshot() -> DeviceSchedulingStateSnapshot { current }

    public func updates() -> AsyncStream<DeviceSchedulingStateSnapshot> {
        let identifier = UUID()
        let initial = current
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            updateContinuations[identifier] = continuation
            continuation.yield(initial)
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { await self?.removeUpdateContinuation(identifier) }
            }
        }
    }

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
            nextTriggerDates: current.nextTriggerDates,
            pendingOrAddedIdentifiers: current.pendingOrAddedIdentifiers
        )
        publishUpdate()
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
            nextTriggerDates: current.nextTriggerDates,
            pendingOrAddedIdentifiers: current.pendingOrAddedIdentifiers
        )
        publishUpdate()
    }

    func publish(
        deviceNotificationsEnabled: Bool,
        authorization: NotificationAuthorizationSnapshot,
        outcomes: [AlertGroupID: AlertGroupSchedulingOutcome],
        scheduledThrough: [UUID: Date],
        materializedKinds: [String: MaterializedNotificationKind],
        nextTriggerDates: [String: Date],
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
            nextTriggerDates: nextTriggerDates,
            pendingOrAddedIdentifiers: pendingOrAddedIdentifiers
        )
        publishUpdate()
    }

    private func publishUpdate() {
        for continuation in updateContinuations.values {
            continuation.yield(current)
        }
    }

    private func removeUpdateContinuation(_ identifier: UUID) {
        updateContinuations.removeValue(forKey: identifier)
    }
}
