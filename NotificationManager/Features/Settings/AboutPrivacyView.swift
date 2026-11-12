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
        .listStyle(.insetGrouped)
        .navigationTitle(
            LocalizedStringResource(
                "privacy.title",
                table: "Settings"
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("privacy.root")
    }

    private func disclosureSection(
        _ title: LocalizedStringResource,
        disclosures: [AboutPrivacyDisclosure]
    ) -> some View {
        Section(title) {
            ForEach(disclosures) { disclosure in
                Text(disclosure.localizedResource)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("privacy.disclosure.\(disclosure.rawValue)")
            }
        }
    }
}
