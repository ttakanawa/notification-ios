import NotificationManagerApplication
import Observation

@MainActor
@Observable
final class DataUnavailableActions {
    let notificationSettings: NotificationSettingsModel
    private(set) var didRequestRetry = false

    @ObservationIgnored private let retryAction: @MainActor @Sendable () async -> Void

    init(
        preferenceStore: any DeviceNotificationPreferenceStore,
        authorizationProvider: any NotificationAuthorizationProviding,
        authorizationRequester: any NotificationAuthorizationRequesting,
        pendingCleaner: any PendingAppNotificationCleaning,
        retry: @escaping @MainActor @Sendable () async -> Void
    ) {
        notificationSettings = NotificationSettingsModel(
            preferenceStore: preferenceStore,
            authorizationProvider: authorizationProvider,
            authorizationRequester: authorizationRequester,
            pendingCleaner: pendingCleaner,
            reconciler: nil
        )
        retryAction = retry
    }

    var isEnabled: Bool { notificationSettings.isEnabled }
    var authorization: NotificationAuthorizationSnapshot { notificationSettings.authorization }
    var isWorking: Bool { notificationSettings.isWorking }
    var actionError: NotificationSettingsActionErrorIdentity? {
        notificationSettings.actionError
    }

    func load() async {
        await notificationSettings.load()
    }

    func setEnabled(_ enabled: Bool) async {
        await notificationSettings.setEnabled(enabled)
    }

    func removeAllPending() async {
        await notificationSettings.removeAllPending()
    }

    func retry() async {
        guard !didRequestRetry else { return }
        didRequestRetry = true
        await retryAction()
    }
}
