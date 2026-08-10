import SwiftUI

struct AdaptiveRootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var router: AppRouter
    @Bindable var listModel: ReminderListModel
    @Bindable private var actions: ReminderActionCoordinator

    init(router: AppRouter, listModel: ReminderListModel) {
        self.router = router
        self.listModel = listModel
        actions = router.actions
    }

    var body: some View {
        let capacityConfirmation = actions.enabledCapacityConfirmation
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
                NavigationStack(path: compactPathBinding) {
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
        .sheet(isPresented: enabledCapacityConfirmationPresented) {
            if let confirmation = capacityConfirmation {
                CapacityConfirmationView(
                    warning: confirmation.warning,
                    onConfirm: {
                        Task {
                            await actions.confirmEnabledCapacityChange(
                                confirmation.reminderID
                            )
                        }
                    },
                    onCancel: {
                        actions.cancelEnabledCapacityChange(
                            confirmation.reminderID
                        )
                    }
                )
                .presentationDetents([.medium])
            }
        }
    }

    private func synchronizeRouter() {
        router.synchronizeLayout(horizontalSizeClass == .regular ? .regular : .compact)
    }

    private var compactPathBinding: Binding<[AppRouterDestination]> {
        Binding(
            get: { router.compactPath },
            set: { path in
                router.setCompactPathFromSystem(path)
            }
        )
    }

    private var enabledCapacityConfirmationPresented: Binding<Bool> {
        Binding(
            get: { actions.enabledCapacityConfirmation != nil },
            set: { presented in
                guard !presented,
                      let confirmation = actions.enabledCapacityConfirmation
                else {
                    return
                }
                actions.cancelEnabledCapacityChange(confirmation.reminderID)
            }
        )
    }
}
