import SwiftUI

struct AboutPrivacyView: View {
    var body: some View {
        List {
            disclosureSection(
                LocalizedStringResource(
                    "privacy.section.icloud",
                    table: "Settings"
                ),
                disclosures: [
                    .automaticICloudSync,
                    .syncCompletionNotGuaranteed,
                    .accountBehaviorNotGuaranteed
                ]
            )
            disclosureSection(
                LocalizedStringResource(
                    "privacy.section.notifications",
                    table: "Settings"
                ),
                disclosures: [
                    .notificationStorageManagedByOS,
                    .notificationPreviewsControlledByOS,
                    .staleSyncedContentMayAppear,
                    .notificationRemovalIsNonAtomic,
                    .deliveredNotificationRetention,
                    .delayedOperationsAfterTermination,
                    .staleRepeatingRequestsUntilReconcile
                ]
            )
            disclosureSection(
                LocalizedStringResource(
                    "privacy.section.data",
                    table: "Settings"
                ),
                disclosures: [
                    .noServerAnalyticsOrAdvertising,
                    .foundationModelsRunOnDevice
                ]
            )
        }
        .navigationTitle(
            LocalizedStringResource(
                "privacy.title",
                table: "Settings"
            )
        )
        .accessibilityIdentifier("privacy.root")
    }

    private func disclosureSection(
        _ title: LocalizedStringResource,
        disclosures: [AboutPrivacyDisclosure]
    ) -> some View {
        Section(title) {
            ForEach(disclosures) { disclosure in
                Label {
                    Text(disclosure.localizedResource)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("privacy.disclosure.\(disclosure.rawValue)")
            }
        }
    }
}
