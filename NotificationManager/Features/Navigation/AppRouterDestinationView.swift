import SwiftUI

struct AppRouterDestinationView: View {
    let destination: AppRouterDestination?
    @Bindable var router: AppRouter

    var body: some View {
        Group {
            switch destination {
            case let .reminderDetail(id):
                if let model = router.detailModel(for: id) {
                    ReminderDetailView(
                        model: model,
                        router: router,
                        actions: router.actions
                    )
                } else {
                    unavailable
                }
            case let .reminderEdit(id), let .reminderCreate(id):
                if let model = router.formModel(for: id) {
                    ReminderFormView(
                        model: model,
                        router: router,
                        tagModel: router.tagManagementModel
                    )
                } else {
                    unavailable
                }
            case .settings:
                if let settings = router.notificationSettingsModel,
                   let tags = router.tagManagementModel
                {
                    SettingsView(model: settings, tagModel: tags)
                } else {
                    unavailable
                }
            case .notificationUnavailable:
                NotificationNoLongerAvailableView()
            case nil:
                ContentUnavailableView(
                    "reminder.navigation.select.title",
                    systemImage: "bell.badge",
                    description: Text("reminder.navigation.select.message")
                )
                .accessibilityIdentifier("adaptive-root.empty-detail")
            }
        }
    }

    private var unavailable: some View {
        ContentUnavailableView(
            "reminder.navigation.unavailable.title",
            systemImage: "exclamationmark.triangle",
            description: Text("reminder.navigation.unavailable.message")
        )
        .accessibilityIdentifier("reminder.navigation.unavailable")
    }
}
