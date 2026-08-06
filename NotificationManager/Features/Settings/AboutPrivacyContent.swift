enum AboutPrivacyDisclosure: String, CaseIterable, Sendable, Hashable, Identifiable {
    case automaticICloudSync
    case syncCompletionNotGuaranteed
    case accountBehaviorNotGuaranteed
    case notificationStorageManagedByOS
    case notificationPreviewsControlledByOS
    case staleSyncedContentMayAppear
    case notificationRemovalIsNonAtomic
    case deliveredNotificationRetention
    case delayedOperationsAfterTermination
    case staleRepeatingRequestsUntilReconcile
    case noServerAnalyticsOrAdvertising
    case foundationModelsRunOnDevice

    var id: Self { self }

    var semanticKey: String {
        switch self {
        case .automaticICloudSync:
            "privacy.icloud.automatic-sync"
        case .syncCompletionNotGuaranteed:
            "privacy.icloud.sync-completion"
        case .accountBehaviorNotGuaranteed:
            "privacy.icloud.account-behavior"
        case .notificationStorageManagedByOS:
            "privacy.notifications.os-storage"
        case .notificationPreviewsControlledByOS:
            "privacy.notifications.previews"
        case .staleSyncedContentMayAppear:
            "privacy.notifications.stale-content"
        case .notificationRemovalIsNonAtomic:
            "privacy.notifications.non-atomic-removal"
        case .deliveredNotificationRetention:
            "privacy.notifications.delivered-retention"
        case .delayedOperationsAfterTermination:
            "privacy.notifications.delayed-operations"
        case .staleRepeatingRequestsUntilReconcile:
            "privacy.notifications.stale-repeating"
        case .noServerAnalyticsOrAdvertising:
            "privacy.data.no-server-analytics-ads"
        case .foundationModelsRunOnDevice:
            "privacy.data.foundation-models-on-device"
        }
    }
}
