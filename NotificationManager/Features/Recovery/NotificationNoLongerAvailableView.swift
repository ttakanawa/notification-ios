import SwiftUI

struct NotificationNoLongerAvailableView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                NotificationUnavailableContent.title,
                systemImage: "bell.slash",
                description: Text(NotificationUnavailableContent.message)
            )
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(NotificationUnavailableContent.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("notification-unavailable.root")
    }
}
