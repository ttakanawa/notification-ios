import SwiftUI

struct NotificationNoLongerAvailableView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                NotificationUnavailableContent.title,
                systemImage: "bell.slash",
                description: Text(NotificationUnavailableContent.message)
            )
            .navigationTitle(NotificationUnavailableContent.title)
        }
        .accessibilityIdentifier("notification-unavailable.root")
    }
}
