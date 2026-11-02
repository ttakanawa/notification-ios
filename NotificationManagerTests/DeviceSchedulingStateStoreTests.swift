import Foundation
import NotificationManagerDomain
import Testing

@testable import NotificationManager

@Suite("DeviceSchedulingStateStore")
struct DeviceSchedulingStateStoreTests {
    @Test func bootstrapAndQueuedStatesDoNotResolveThePlaceholderPreference() async {
        let store = DeviceSchedulingStateStore()
        let initial = await store.snapshot()
        #expect(!initial.deviceNotificationsEnabled)
        #expect(!initial.hasResolvedDeviceSettings)

        var updates = await store.updates().makeAsyncIterator()
        #expect(await updates.next()?.hasResolvedDeviceSettings == false)
        await store.setReconcileInProgressOrQueued(true, revision: 1)
        #expect(await store.snapshot().hasResolvedDeviceSettings == false)
        await store.setReconcileInProgressOrQueued(false, revision: 2)
        #expect(await store.snapshot().hasResolvedDeviceSettings == false)
    }

    @Test func initialFailureDoesNotMakeThePlaceholderAnAuthoritativeDisable() async {
        let store = DeviceSchedulingStateStore()
        await store.publishFailure(.snapshot)
        let failed = await store.snapshot()

        #expect(failed.generation == 1)
        #expect(failed.globalFailure == .snapshot)
        #expect(!failed.hasResolvedDeviceSettings)
    }

    @Test(arguments: [false, true])
    func authoritativeSettingsStayResolvedAcrossBusyIdleAndFailure(_ enabled: Bool) async {
        let store = DeviceSchedulingStateStore()
        await store.publish(
            deviceNotificationsEnabled: enabled,
            authorization: .init(state: .allowed, diagnostic: nil),
            outcomes: [:], scheduledThrough: [:], materializedKinds: [:],
            nextTriggerDates: [:], pendingOrAddedIdentifiers: []
        )
        await store.setReconcileInProgressOrQueued(true, revision: 1)
        await store.publishFailure(.inventory)
        await store.setReconcileInProgressOrQueued(false, revision: 2)
        let final = await store.snapshot()

        #expect(final.hasResolvedDeviceSettings)
        #expect(final.deviceNotificationsEnabled == enabled)
        #expect(final.globalFailure == .inventory)
        #expect(!final.reconcileInProgressOrQueued)
    }
}
