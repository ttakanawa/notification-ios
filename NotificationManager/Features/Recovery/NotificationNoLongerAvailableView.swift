import SwiftUI

struct NotificationNoLongerAvailableView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                LocalizedStringKey(NotificationUnavailableContent.titleKey),
                systemImage: "bell.slash",
                description: Text(
                    LocalizedStringKey(NotificationUnavailableContent.messageKey)
                )
            )
            .navigationTitle(
                LocalizedStringKey(NotificationUnavailableContent.titleKey)
            )
        }
        .accessibilityIdentifier("notification-unavailable.root")
    }
}
