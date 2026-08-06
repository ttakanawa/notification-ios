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

            reminderSection(
                "reminder.list.section.upcoming",
                identifier: "reminder-list.section.upcoming",
                items: model.sections.upcoming
            )
            reminderSection(
                "reminder.list.section.needs-attention",
                identifier: "reminder-list.section.needs-attention",
                items: model.sections.needsAttention
            )
            reminderSection(
                "reminder.list.section.inactive",
                identifier: "reminder-list.section.inactive",
                items: model.sections.inactive
            )
        }
        .listStyle(.insetGrouped)
        .navigationTitle("reminder.list.title")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    router.showSettings()
                } label: {
                    Label("settings.title", systemImage: "gear")
                }
                .accessibilityIdentifier("reminder-list.settings")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.showCreate()
                } label: {
                    Label("reminder.action.add", systemImage: "plus")
                }
                .accessibilityIdentifier("reminder-list.add")
            }
        }
        .announcesAccessibilityErrors(actionAccessibilityErrors)
        .accessibilityIdentifier("reminder-list.root")
    }

    @ViewBuilder
    private func reminderSection(
        _ title: LocalizedStringKey,
        identifier: String,
        items: [ReminderListItemPresentation]
    ) -> some View {
        Section(title) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 12) {
                        Button {
                            router.showReminder(item.id)
                        } label: {
                            ReminderRowView(item: item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("reminder-row.\(item.id.uuidString.lowercased())")
                        .accessibilityAddTraits(
                            router.selectedReminderID == item.id ? .isSelected : []
                        )

                        if item.lifecycleStatus == .active || item.lifecycleStatus == .disabled {
                            Toggle("reminder.field.enabled", isOn: enabledBinding(for: item))
                                .labelsHidden()
                                .disabled(actions.isWorking(item.id))
                                .accessibilityIdentifier(
                                    "reminder-row.enabled.\(item.id.uuidString.lowercased())"
                                )
                        }
                    }

                    if let failure = actionFailure(for: item.id) {
                        Label(failure.semanticKey, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(
                                "reminder-row.action-error.\(item.id.uuidString.lowercased())"
                            )
                    }
                }
            }
        }
        .accessibilityIdentifier(identifier)
    }

    private func enabledBinding(for item: ReminderListItemPresentation) -> Binding<Bool> {
        Binding(
            get: { actions.enabledValue(for: item.id, fallback: item.enabled) },
            set: { enabled in
                Task {
                    await actions.setEnabled(enabled, for: item.id, fallback: item.enabled)
                }
            }
        )
    }

    private var actionAccessibilityErrors: [AccessibilityErrorIdentity] {
        guard case let .failed(_, failure) = actions.state else { return [] }
        return [failure.accessibilityIdentity]
    }

    private func actionFailure(for reminderID: UUID) -> ReminderActionFailure? {
        guard case let .failed(id, failure) = actions.state, id == reminderID else {
            return nil
        }
        return failure
    }
}

extension ReminderActionFailure {
    var semanticKey: LocalizedStringKey {
        switch self {
        case .enabledChange: "reminder.action.enabled-change-failed"
        case .delete: "reminder.action.delete-failed"
        }
    }

    var accessibilityIdentity: AccessibilityErrorIdentity {
        switch self {
        case .enabledChange: .reminderEnabledChangeFailed
        case .delete: .reminderDeleteFailed
        }
    }
}
