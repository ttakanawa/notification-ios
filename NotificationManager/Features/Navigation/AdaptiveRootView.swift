import SwiftUI

struct AdaptiveRootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var router: AppRouter
    @Bindable var listModel: ReminderListModel
    @Bindable private var actions: ReminderActionCoordinator
    @State private var reminderConfirmations = ReminderFormConfirmationCoordinator()

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
                        router: router,
                        confirmations: reminderConfirmations
                    )
                }
                .accessibilityIdentifier("adaptive-root.regular-split")
            } else {
                NavigationStack(path: compactPathBinding) {
                    ReminderListView(model: listModel, router: router)
                        .navigationDestination(for: AppRouterDestination.self) { destination in
                            AppRouterDestinationView(
                                destination: destination,
                                router: router,
                                confirmations: reminderConfirmations
                            )
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
        .sheet(
            isPresented: reminderCapacityConfirmationPresented,
            onDismiss: reminderConfirmations.capacitySheetDidDismiss
        ) {
            if let warning = reminderConfirmations.capacityWarning {
                CapacityConfirmationView(
                    warning: warning,
                    isPersistenceOperationInFlight: reminderConfirmations
                        .isPersistenceOperationInFlight,
                    onConfirm: reminderConfirmations.confirmCapacity,
                    onCancel: reminderConfirmations.cancelCapacity
                )
                .presentationDetents([.medium])
            }
        }
        .alert(
            reminderConfirmationAlertTitle,
            isPresented: reminderAlertPresented
        ) {
            reminderConfirmationAlertActions
        } message: {
            reminderConfirmationAlertMessage
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

    private var reminderCapacityConfirmationPresented: Binding<Bool> {
        Binding(
            get: { reminderConfirmations.capacityWarning != nil },
            set: { presented in
                if !presented {
                    reminderConfirmations.dismissCapacityFromSystem()
                }
            }
        )
    }

    private var reminderAlertPresented: Binding<Bool> {
        Binding(
            get: { reminderConfirmations.alertKind != nil },
            set: { presented in
                if !presented {
                    reminderConfirmations.dismissAlertFromSystem()
                }
            }
        )
    }

    private var reminderConfirmationAlertTitle: Text {
        switch reminderConfirmations.alertKind {
        case .expiredSchedule:
            Text(LocalizedStringResource(
                "reminder.form.expired-confirmation.title",
                table: "ReminderForm"
            ))
        case .delete:
            Text(LocalizedStringResource(
                "reminder.form.delete-confirmation.title",
                table: "ReminderForm"
            ))
        case .discardChanges:
            Text(LocalizedStringResource(
                "reminder.form.discard-confirmation.title",
                table: "ReminderForm"
            ))
        case nil:
            Text("")
        }
    }

    private var reminderConfirmationAlertMessage: Text {
        switch reminderConfirmations.alertKind {
        case .expiredSchedule:
            Text(LocalizedStringResource(
                "reminder.form.expired-confirmation.message",
                table: "ReminderForm"
            ))
        case .delete:
            Text(LocalizedStringResource(
                "reminder.form.delete-confirmation.message",
                table: "ReminderForm"
            ))
        case .discardChanges:
            Text(LocalizedStringResource(
                "reminder.form.discard-confirmation.message",
                table: "ReminderForm"
            ))
        case nil:
            Text("")
        }
    }

    @ViewBuilder
    private var reminderConfirmationAlertActions: some View {
        switch reminderConfirmations.alertKind {
        case .expiredSchedule:
            Button(role: .destructive, action: reminderConfirmations.confirmAlert) {
                Text(LocalizedStringResource(
                    "reminder.form.expired-confirmation.confirm",
                    table: "ReminderForm"
                ))
                    .accessibilityIdentifier("reminder-form.expired-confirm")
            }
            .disabled(reminderConfirmations.isPersistenceOperationInFlight)
            Button(role: .cancel, action: reminderConfirmations.cancelAlert) {
                Text(LocalizedStringResource(
                    "reminder.action.cancel",
                    table: "Reminder"
                ))
            }
            .disabled(reminderConfirmations.isPersistenceOperationInFlight)
        case .delete:
            Button(role: .destructive, action: reminderConfirmations.confirmAlert) {
                Text(LocalizedStringResource(
                    "reminder.form.delete-confirmation.confirm",
                    table: "ReminderForm"
                ))
                    .accessibilityIdentifier("reminder-form.delete-confirm")
            }
            .disabled(reminderConfirmations.isPersistenceOperationInFlight)
            Button(role: .cancel, action: reminderConfirmations.cancelAlert) {
                Text(LocalizedStringResource(
                    "reminder.action.cancel",
                    table: "Reminder"
                ))
                    .accessibilityIdentifier("reminder-form.delete-cancel")
            }
            .disabled(reminderConfirmations.isPersistenceOperationInFlight)
        case .discardChanges:
            Button(role: .destructive, action: reminderConfirmations.confirmAlert) {
                Text(LocalizedStringResource(
                    "reminder.form.discard-confirmation.confirm",
                    table: "ReminderForm"
                ))
                    .accessibilityIdentifier("reminder-form.discard-confirm")
            }
            .disabled(reminderConfirmations.isPersistenceOperationInFlight)
            Button(role: .cancel, action: reminderConfirmations.cancelAlert) {
                Text(LocalizedStringResource(
                    "reminder.action.cancel",
                    table: "Reminder"
                ))
                    .accessibilityIdentifier("reminder-form.discard-cancel")
            }
            .disabled(reminderConfirmations.isPersistenceOperationInFlight)
        case nil:
            EmptyView()
        }
    }
}
