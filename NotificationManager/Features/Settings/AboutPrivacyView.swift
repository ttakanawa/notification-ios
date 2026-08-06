import SwiftUI

struct AboutPrivacyView: View {
    var body: some View {
        List {
            disclosureSection(
                "privacy.section.icloud",
                disclosures: [
                    .automaticICloudSync,
                    .syncCompletionNotGuaranteed,
                    .accountBehaviorNotGuaranteed
                ]
            )
            disclosureSection(
                "privacy.section.notifications",
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
                "privacy.section.data",
                disclosures: [
                    .noServerAnalyticsOrAdvertising,
                    .foundationModelsRunOnDevice
                ]
            )
        }
        .navigationTitle("privacy.title")
        .accessibilityIdentifier("privacy.root")
    }

    private func disclosureSection(
        _ title: LocalizedStringKey,
        disclosures: [AboutPrivacyDisclosure]
    ) -> some View {
        Section(title) {
            ForEach(disclosures) { disclosure in
                Label {
                    Text(LocalizedStringKey(disclosure.semanticKey))
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
