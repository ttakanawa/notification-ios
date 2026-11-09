import SwiftUI

struct ReminderListView: View {
    @Bindable var model: ReminderListModel
    @Bindable var router: AppRouter
    @Bindable private var actions: ReminderActionCoordinator

    init(model: ReminderListModel, router: AppRouter) {
        self.model = model
        self.router = router
        actions = router.actions
    }

    var body: some View {
        List {
            TagFilterView(
                tags: model.tagFilterChoices,
                selectedTagID: $model.selectedTagID
            )
            TimeZoneFilterView(
                identifiers: model.timeZoneFilterChoices,
                selectedIdentifier: $model.selectedTimeZoneIdentifier
            )

            reminderSection(
                LocalizedStringResource(
                    "reminder.list.section.upcoming",
                    table: "Reminder"
                ),
                identifier: "reminder-list.section.upcoming",
                items: model.sections.upcoming
            )
            reminderSection(
                LocalizedStringResource(
                    "reminder.list.section.needs-attention",
                    table: "Reminder"
                ),
                identifier: "reminder-list.section.needs-attention",
                items: model.sections.needsAttention
            )
            reminderSection(
                LocalizedStringResource(
                    "reminder.list.section.inactive",
                    table: "Reminder"
                ),
                identifier: "reminder-list.section.inactive",
                items: model.sections.inactive
            )
        }
        .listStyle(.insetGrouped)
        .navigationTitle(
            LocalizedStringResource(
                "reminder.list.title",
                table: "Reminder"
            )
        )
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button {
                    router.showSettings()
                } label: {
                    Label(
                        LocalizedStringResource("settings.title", table: "Settings"),
                        systemImage: "gear"
                    )
                }
                .accessibilityIdentifier("reminder-list.settings")

                if let iCloudModel = router.iCloudSyncStatusModel {
                    ICloudSyncStatusButton(model: iCloudModel) {
                        router.showSettings()
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.showCreate()
                } label: {
                    Label(
                        LocalizedStringResource("reminder.action.add", table: "Reminder"),
                        systemImage: "plus"
                    )
                }
                .accessibilityIdentifier("reminder-list.add")
            }
        }
        .announcesAccessibilityErrors(actionAccessibilityErrors)
        .background {
            AccessibilityIdentifierContainer(identifier: "reminder-list.root")
        }
        .alert(
            Text(
                LocalizedStringResource(
                    "reminder.form.delete-confirmation.title",
                    table: "ReminderForm"
                )),
            isPresented: deleteConfirmationPresented,
            presenting: actions.pendingDeleteID
        ) { id in
            Button(role: .destructive) {
                guard actions.consumeDeleteConfirmation(id) else { return }
                Task {
                    await router.performReminderDeletion(id) {
                        await actions.performConfirmedDelete(id)
                    }
                }
            } label: {
                Text(
                    LocalizedStringResource(
                        "reminder.form.delete-confirmation.confirm",
                        table: "ReminderForm"
                    ))
            }
            .accessibilityIdentifier("reminder-list.delete-confirm")
            Button(role: .cancel) {
                actions.cancelDelete(id)
            } label: {
                Text(LocalizedStringResource("reminder.action.cancel", table: "Reminder"))
            }
            .accessibilityIdentifier("reminder-list.delete-cancel")
        } message: { _ in
            Text(
                LocalizedStringResource(
                    "reminder.form.delete-confirmation.message",
                    table: "ReminderForm"
                ))
        }
    }

    @ViewBuilder
    private func reminderSection(
        _ title: LocalizedStringResource,
        identifier: String,
        items: [ReminderListItemPresentation]
    ) -> some View {
        Section {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        router.showReminder(item.id)
                    } label: {
                        ReminderRowView(item: item)
                    }
                    .buttonStyle(.plain)
                    .disabled(actions.isBusy)
                    .accessibilityIdentifier("reminder-row.\(item.id.uuidString.lowercased())")
                    .accessibilityAddTraits(
                        router.selectedReminderID == item.id ? .isSelected : []
                    )

                    if let failure = actionFailure(for: item.id) {
                        Label(
                            failure.localizedResource,
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(
                            "reminder-row.action-error.\(item.id.uuidString.lowercased())"
                        )
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if !actions.isBusy {
                        enabledButton(for: item)
                            .tint(
                                actions.enabledValue(for: item.id, fallback: item.enabled)
                                    ? .orange : .green
                            )
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !actions.isBusy {
                        deleteButton(for: item)
                            .tint(.red)
                        if router.canDuplicate(item.id) {
                            duplicateButton(for: item)
                                .tint(.indigo)
                        }
                        editButton(for: item)
                            .tint(.blue)
                    }
                }
            }
        } header: {
            Text(title)
                .background {
                    AccessibilityIdentifierContainer(identifier: identifier)
                }
        }
    }

    private func editButton(for item: ReminderListItemPresentation) -> some View {
        Button {
            guard !actions.isBusy else { return }
            router.showReminder(item.id)
        } label: {
            Label(
                LocalizedStringResource("reminder.action.edit", table: "Reminder"),
                systemImage: "pencil"
            )
        }
        .disabled(actions.isBusy)
        .accessibilityIdentifier("reminder-row.edit.\(item.id.uuidString.lowercased())")
    }

    private func duplicateButton(for item: ReminderListItemPresentation) -> some View {
        Button {
            guard !actions.isBusy else { return }
            router.showDuplicate(item.id)
        } label: {
            Label(
                LocalizedStringResource("reminder.action.duplicate", table: "Reminder"),
                systemImage: "doc.on.doc"
            )
        }
        .disabled(actions.isBusy)
        .accessibilityIdentifier("reminder-row.duplicate.\(item.id.uuidString.lowercased())")
    }

    private func enabledButton(for item: ReminderListItemPresentation) -> some View {
        let enabled = actions.enabledValue(for: item.id, fallback: item.enabled)
        return Button {
            let currentValue = actions.enabledValue(for: item.id, fallback: item.enabled)
            Task {
                await actions.setEnabled(!currentValue, for: item.id, fallback: item.enabled)
            }
        } label: {
            Label(
                LocalizedStringResource(
                    enabled ? "reminder.action.disable" : "reminder.action.enable",
                    table: "Reminder"
                ),
                systemImage: enabled ? "bell.slash" : "bell"
            )
        }
        .disabled(actions.isBusy)
        .accessibilityIdentifier("reminder-row.toggle-enabled.\(item.id.uuidString.lowercased())")
    }

    private func deleteButton(for item: ReminderListItemPresentation) -> some View {
        Button {
            actions.requestDelete(item.id)
        } label: {
            Label(
                LocalizedStringResource("reminder.action.delete", table: "Reminder"),
                systemImage: "trash"
            )
        }
        .disabled(actions.isBusy)
        .accessibilityIdentifier("reminder-row.delete.\(item.id.uuidString.lowercased())")
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { actions.pendingDeleteID != nil },
            set: { presented in
                if !presented, let id = actions.pendingDeleteID {
                    actions.cancelDelete(id)
                }
            }
        )
    }

    private var actionAccessibilityErrors: [AccessibilityErrorIdentity] {
        guard case .failed(_, let failure) = actions.state else { return [] }
        return [failure.accessibilityIdentity]
    }

    private func actionFailure(for reminderID: UUID) -> ReminderActionFailure? {
        guard case .failed(let id, let failure) = actions.state, id == reminderID else {
            return nil
        }
        return failure
    }
}

extension ReminderActionFailure {
    var localizedResource: LocalizedStringResource {
        switch self {
        case .enabledChange:
            LocalizedStringResource(
                "reminder.action.enabled-change-failed",
                table: "Reminder"
            )
        case .delete:
            LocalizedStringResource(
                "reminder.action.delete-failed",
                table: "Reminder"
            )
        }
    }

    var accessibilityIdentity: AccessibilityErrorIdentity {
        switch self {
        case .enabledChange: .reminderEnabledChangeFailed
        case .delete: .reminderDeleteFailed
        }
    }
}
