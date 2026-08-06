import NotificationManagerApplication
import Observation

enum NotificationSettingsActionErrorIdentity: Sendable, Equatable {
    case authorizationRequest
    case pendingCleanup
}

@MainActor
@Observable
final class NotificationSettingsModel {
    private(set) var isEnabled = false
    private(set) var authorization = NotificationAuthorizationService.map(rawValue: 0)
    private(set) var isWorking = false
    private(set) var actionError: NotificationSettingsActionErrorIdentity?

    @ObservationIgnored private let preferenceStore: any DeviceNotificationPreferenceStore
    @ObservationIgnored private let authorizationProvider: any NotificationAuthorizationProviding
    @ObservationIgnored private let authorizationRequester: any NotificationAuthorizationRequesting
    @ObservationIgnored private let pendingCleaner: any PendingAppNotificationCleaning
    @ObservationIgnored private let reconciler: (any ReconcileRequesting)?

    init(
        preferenceStore: any DeviceNotificationPreferenceStore,
        authorizationProvider: any NotificationAuthorizationProviding,
        authorizationRequester: any NotificationAuthorizationRequesting,
        pendingCleaner: any PendingAppNotificationCleaning,
        reconciler: (any ReconcileRequesting)?
    ) {
        self.preferenceStore = preferenceStore
        self.authorizationProvider = authorizationProvider
        self.authorizationRequester = authorizationRequester
        self.pendingCleaner = pendingCleaner
        self.reconciler = reconciler
    }

    func load() async {
        guard !isWorking else { return }
        isWorking = true
        actionError = nil
        isEnabled = await preferenceStore.isEnabled()
        authorization = await authorizationProvider.currentAuthorization()
        isWorking = false
    }

    func setEnabled(_ enabled: Bool) async {
        guard !isWorking else { return }
        isWorking = true
        actionError = nil
        isEnabled = enabled
        await preferenceStore.setEnabled(enabled)

        if enabled {
            authorization = await authorizationProvider.currentAuthorization()
            if authorization.rawStatus == .notDetermined {
                do {
                    _ = try await authorizationRequester.requestAuthorization()
                } catch {
                    actionError = .authorizationRequest
                }
                authorization = await authorizationProvider.currentAuthorization()
            }
        } else {
            await removePendingWithoutChangingWorkingState()
        }

        if let reconciler {
            await reconciler.requestReconcile(.deviceSettingsChanged)
        }
        isWorking = false
    }

    func removeAllPending() async {
        guard !isWorking else { return }
        isWorking = true
        actionError = nil
        await removePendingWithoutChangingWorkingState()
        isWorking = false
    }

    private func removePendingWithoutChangingWorkingState() async {
        do {
            try await pendingCleaner.removeAllPendingAppNotificationsReportingFailure()
        } catch {
            actionError = .pendingCleanup
        }
    }
}
