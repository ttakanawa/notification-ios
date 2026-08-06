import SwiftUI

struct AdaptiveRootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var router: AppRouter
    @Bindable var listModel: ReminderListModel

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    ReminderListView(model: listModel, router: router)
                } detail: {
                    AppRouterDestinationView(
                        destination: router.regularDestination,
                        router: router
                    )
                }
                .accessibilityIdentifier("adaptive-root.regular-split")
            } else {
                NavigationStack(path: $router.compactPath) {
                    ReminderListView(model: listModel, router: router)
                        .navigationDestination(for: AppRouterDestination.self) { destination in
                            AppRouterDestinationView(destination: destination, router: router)
                        }
                }
                .accessibilityIdentifier("adaptive-root.compact-stack")
            }
        }
        .onAppear { synchronizeRouter() }
        .onChange(of: horizontalSizeClass) { _, _ in synchronizeRouter() }
    }

    private func synchronizeRouter() {
        router.synchronizeLayout(horizontalSizeClass == .regular ? .regular : .compact)
    }
}
