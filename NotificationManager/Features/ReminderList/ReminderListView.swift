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
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    router.showSettings()
                } label: {
                    Label(
                        LocalizedStringResource("settings.title", table: "Settings"),
                        systemImage: "gear"
                    )
                }
                .accessibilityIdentifier("reminder-list.settings")
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
            }
        } header: {
            Text(title)
                .background {
                    AccessibilityIdentifierContainer(identifier: identifier)
                }
        }
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
