import Foundation

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

    var localizedResource: LocalizedStringResource {
        switch self {
        case .automaticICloudSync:
            LocalizedStringResource(
                "privacy.icloud.automatic-sync",
                table: "Settings"
            )
        case .syncCompletionNotGuaranteed:
            LocalizedStringResource(
                "privacy.icloud.sync-completion",
                table: "Settings"
            )
        case .accountBehaviorNotGuaranteed:
            LocalizedStringResource(
                "privacy.icloud.account-behavior",
                table: "Settings"
            )
        case .notificationStorageManagedByOS:
            LocalizedStringResource(
                "privacy.notifications.os-storage",
                table: "Settings"
            )
        case .notificationPreviewsControlledByOS:
            LocalizedStringResource(
                "privacy.notifications.previews",
                table: "Settings"
            )
        case .staleSyncedContentMayAppear:
            LocalizedStringResource(
                "privacy.notifications.stale-content",
                table: "Settings"
            )
        case .notificationRemovalIsNonAtomic:
            LocalizedStringResource(
                "privacy.notifications.non-atomic-removal",
                table: "Settings"
            )
        case .deliveredNotificationRetention:
            LocalizedStringResource(
                "privacy.notifications.delivered-retention",
                table: "Settings"
            )
        case .delayedOperationsAfterTermination:
            LocalizedStringResource(
                "privacy.notifications.delayed-operations",
                table: "Settings"
            )
        case .staleRepeatingRequestsUntilReconcile:
            LocalizedStringResource(
                "privacy.notifications.stale-repeating",
                table: "Settings"
            )
        case .noServerAnalyticsOrAdvertising:
            LocalizedStringResource(
                "privacy.data.no-server-analytics-ads",
                table: "Settings"
            )
        case .foundationModelsRunOnDevice:
            LocalizedStringResource(
                "privacy.data.foundation-models-on-device",
                table: "Settings"
            )
        }
    }
}
