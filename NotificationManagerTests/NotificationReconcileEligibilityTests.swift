import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import Testing
import UserNotifications

@testable import NotificationManager

@Suite("Notification reconcile eligibility invalidation")
struct NotificationReconcileEligibilityTests {
    @Test func deviceSettingsChangeStalesPublishedIndexBeforeBlockedLoadCompletes() async {
        let snapshot = CompleteReminderSnapshot(reminders: [], tags: [])
        let loader = EligibilityBlockingSnapshotLoader(snapshot: snapshot)
        let eligibility = ForegroundEligibilityIndexStore()
        let stateStore = DeviceSchedulingStateStore()
        let reminderID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        eligibility.publish(eligibleReminderIDs: [reminderID])
        let worker = NotificationReconcileWorker(
            snapshotLoader: loader,
            preferenceStore: EligibilityPreferenceStore(),
            authorizationProvider: EligibilityAuthorizationProvider(),
            notificationCenter: EligibilityNotificationCenter(),
            eligibilityIndexStore: eligibility,
            stateStore: stateStore
        )

        await worker.requestReconcile(.deviceSettingsChanged)

        #expect(eligibility.snapshot().isStale)
        #expect(!eligibility.isEligible(reminderID))
        #expect(await stateStore.snapshot().reconcileInProgressOrQueued)
        await loader.waitUntilLoadStarts()
        await loader.releaseLoad()
        await worker.waitUntilIdle()
    }
}

private actor EligibilityBlockingSnapshotLoader: CompleteSchedulingSnapshotLoading {
    private let snapshot: CompleteReminderSnapshot
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(snapshot: CompleteReminderSnapshot) {
        self.snapshot = snapshot
    }

    func loadCompleteSnapshot() async throws -> CompleteReminderSnapshot {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        return snapshot
    }

    func waitUntilLoadStarts() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseLoad() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private struct EligibilityPreferenceStore: DeviceNotificationPreferenceStore {
    func isEnabled() async -> Bool { true }
    func setEnabled(_ enabled: Bool) async {}
}

private struct EligibilityAuthorizationProvider: NotificationAuthorizationProviding {
    func currentAuthorization() async -> NotificationAuthorizationSnapshot {
        NotificationAuthorizationSnapshot(state: .allowed, diagnostic: nil)
    }
}

private final class EligibilityNotificationCenter: NotificationCenterClient, @unchecked Sendable {
    func pendingNotificationInventory() async throws -> [NotificationInventoryItem] { [] }
    func deliveredNotificationInventory() async -> [NotificationInventoryItem] { [] }
    func add(_ request: UNNotificationRequest) async throws {}
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {}
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {}
}
