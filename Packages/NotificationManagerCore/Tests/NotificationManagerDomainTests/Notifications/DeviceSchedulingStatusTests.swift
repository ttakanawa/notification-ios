import Foundation
import Testing
@testable import NotificationManagerDomain

@Suite("Notifications.DeviceSchedulingStatus")
struct DeviceSchedulingStatusTests {
    @Test(arguments: [
        LifecycleStatus.disabled,
        .expired,
        .updateRequired,
        .invalidSchedule
    ])
    func nonSchedulableLifecycleAlwaysWins(_ lifecycle: LifecycleStatus) {
        #expect(status(
            lifecycle: lifecycle,
            deviceEnabled: false,
            authorization: .denied,
            earliestOutcome: .unscheduledError,
            isReconciling: true,
            isPresent: false
        ) == .notApplicable)
    }

    @Test func exactDeviceAuthorizationAndPipelinePrecedence() {
        #expect(status(deviceEnabled: false, authorization: .notDetermined) == .notScheduledThisDeviceOff)
        #expect(status(authorization: .notDetermined) == .permissionNotDetermined)
        #expect(status(authorization: .denied) == .notScheduledPermissionDenied)
        #expect(status(authorization: .unknown) == .notScheduledAuthorizationUnknown)
        #expect(status(
            earliestOutcome: .unscheduledError,
            isReconciling: true,
            isPresent: false
        ) == .unscheduledError)
        #expect(status(
            earliestOutcome: .unscheduledCapacity,
            isReconciling: true,
            isPresent: false
        ) == .scheduling)
        #expect(status(earliestOutcome: .unscheduledCapacity, isPresent: false) == .unscheduledCapacity)
        #expect(status(earliestOutcome: .scheduled, isPresent: true) == .scheduled)
    }

    @Test func laterCapacityDoesNotOverrideScheduledEarliestGroup() {
        let value = DeviceSchedulingStatus.resolve(DeviceSchedulingStatusInput(
            lifecycleStatus: .active,
            deviceNotificationsEnabled: true,
            authorization: .allowed,
            earliestGroupOutcome: .scheduled,
            laterGroupOutcomes: [.unscheduledCapacity],
            reconcileInProgressOrQueued: false,
            earliestRequestPresentOrLatestAddSucceeded: true
        ))

        #expect(value == .scheduled)
    }

    private func status(
        lifecycle: LifecycleStatus = .active,
        deviceEnabled: Bool = true,
        authorization: DeviceAuthorizationSchedulingState = .allowed,
        earliestOutcome: AlertGroupSchedulingOutcome? = .scheduled,
        isReconciling: Bool = false,
        isPresent: Bool = true
    ) -> DeviceSchedulingStatus {
        DeviceSchedulingStatus.resolve(DeviceSchedulingStatusInput(
            lifecycleStatus: lifecycle,
            deviceNotificationsEnabled: deviceEnabled,
            authorization: authorization,
            earliestGroupOutcome: earliestOutcome,
            laterGroupOutcomes: [],
            reconcileInProgressOrQueued: isReconciling,
            earliestRequestPresentOrLatestAddSucceeded: isPresent
        ))
    }
}
