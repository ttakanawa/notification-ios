import Foundation
import SwiftUI

struct ReminderDetailView: View {
    let model: ReminderDetailModel
    @Bindable var router: AppRouter
    @Bindable var actions: ReminderActionCoordinator

    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale

    private let sourceFormatter = SourceDateTimePresentationFormatter()

    var body: some View {
        List {
            Section(LocalizedStringResource(
                "reminder.detail.section.status",
                table: "Reminder"
            )) {
                Label(
                    model.lifecycleStatus.localizedResource,
                    systemImage: model.lifecycleStatus.systemImage
                )
                    .accessibilityIdentifier("reminder-detail.lifecycle-status")

                ForEach(
                    Array(model.item.reminderStatus.secondary.enumerated()),
                    id: \.offset
                ) { _, status in
                    Label(status.localizedResource, systemImage: status.systemImage)
                        .accessibilityIdentifier("reminder-detail.secondary-lifecycle-status")
                }

                HStack {
                    Button {
                        enabledBinding.wrappedValue.toggle()
                    } label: {
                        Text(LocalizedStringResource(
                            "reminder.field.enabled",
                            table: "ReminderForm"
                        ))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(actions.isWorking(model.id))
                    .accessibilityHidden(true)

                    Toggle(LocalizedStringResource(
                        "reminder.field.enabled",
                        table: "ReminderForm"
                    ), isOn: enabledBinding)
                        .labelsHidden()
                        .disabled(actions.isWorking(model.id))
                        .accessibilityLabel(Text(LocalizedStringResource(
                            "reminder.field.enabled",
                            table: "ReminderForm"
                        )))
                        .accessibilityIdentifier("reminder-detail.enabled")
                }

                if actions.state == .failed(model.id, .enabledChange) {
                    Label(LocalizedStringResource(
                        "reminder.action.enabled-change-failed",
                        table: "Reminder"
                    ), systemImage: "exclamationmark.triangle")
                        .accessibilityIdentifier("reminder-detail.enabled-error")
                } else if actions.state == .failed(model.id, .delete) {
                    Label(LocalizedStringResource(
                        "reminder.action.delete-failed",
                        table: "Reminder"
                    ), systemImage: "exclamationmark.triangle")
                        .accessibilityIdentifier("reminder-detail.delete-error")
                }

                if let status = model.deviceSchedulingStatusForDisplay {
                    SchedulingStatusView(
                        status: status,
                        alertGroups: model.alertGroups,
                        scheduledThrough: model.scheduledThrough
                    )
                }
            }

            Section(LocalizedStringResource(
                "reminder.detail.section.schedule",
                table: "Reminder"
            )) {
                if let source = model.item.sourceWallClock {
                    LabeledContent {
                        Text(verbatim: sourceFormatter.wallClock(source, locale: locale))
                    } label: {
                        Text(LocalizedStringResource(
                            "reminder.field.source-time",
                            table: "ReminderForm"
                        ))
                    }
                }
                if let sourceTime = model.sourceTime {
                    LabeledContent {
                        Text(
                            verbatim: sourceFormatter.instant(
                                sourceTime,
                                timeZoneIdentifier: sourceTimeZoneIdentifier,
                                locale: locale
                            )
                        )
                    } label: {
                        Text(LocalizedStringResource(
                            "reminder.field.source-instant",
                            table: "ReminderForm"
                        ))
                    }
                }
                if let currentDeviceTime = model.currentDeviceTime {
                    LabeledContent {
                        Text(currentDeviceTime, format: .dateTime)
                    } label: {
                        Text(LocalizedStringResource(
                            "reminder.field.current-device-time",
                            table: "ReminderForm"
                        ))
                    }
                }
                if let summary = model.localizedRepeatSummary {
                    LabeledContent {
                        Text(verbatim: summary)
                    } label: {
                        Text(LocalizedStringResource(
                            "reminder.field.repeat",
                            table: "ReminderForm"
                        ))
                    }
                }
                if let summary = model.repeatEndSummary {
                    LabeledContent {
                        Text(verbatim: summary)
                    } label: {
                        Text(LocalizedStringResource(
                            "reminder.field.repeat-end",
                            table: "ReminderForm"
                        ))
                    }
                }
                if let summary = model.earlyReminderSummary {
                    LabeledContent {
                        Text(verbatim: summary)
                    } label: {
                        Text(LocalizedStringResource(
                            "reminder.field.early-reminder",
                            table: "ReminderForm"
                        ))
                    }
                }
                if !model.item.tags.isEmpty {
                    LabeledContent {
                        Text(verbatim: model.item.tags.map(\.name).joined(separator: ", "))
                    } label: {
                        Text(LocalizedStringResource(
                            "reminder.field.tags",
                            table: "ReminderForm"
                        ))
                    }
                }
            }

            if let notes = model.notes, !notes.isEmpty {
                Section(LocalizedStringResource(
                    "reminder.detail.section.notes",
                    table: "Reminder"
                )) {
                    Text(verbatim: notes)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section(LocalizedStringResource(
                "reminder.detail.section.next-notifications",
                table: "Reminder"
            )) {
                NextNotificationsView(
                    directOSFire: model.directOSFire,
                    notifications: model.nextNotifications
                )
            }

            if !model.requestDiagnostics.isEmpty || !model.alertGroups.isEmpty {
                Section(LocalizedStringResource(
                    "reminder.detail.section.diagnostics",
                    table: "Reminder"
                )) {
                    ForEach(model.requestDiagnostics) { request in
                        LabeledContent {
                            Text(request.kind.localizedResource)
                        } label: {
                            Text(LocalizedStringResource(
                                "reminder.diagnostics.request-type",
                                table: "Reminder"
                            ))
                        }
                        .accessibilityIdentifier("reminder-detail.request-type")
                    }
                    ForEach(model.alertGroups) { group in
                        LabeledContent {
                            Label(
                                group.outcome.localizedResource,
                                systemImage: group.outcome.systemImage
                            )
                        } label: {
                            Text(group.groupID.baseOccurrenceInstant, format: .dateTime)
                        }
                    }
                }
            }

            if let url = model.url {
                Section {
                    Button {
                        openURL(url)
                    } label: {
                        Label(LocalizedStringResource(
                            "reminder.action.open-link",
                            table: "Reminder"
                        ), systemImage: "safari")
                    }
                    .accessibilityIdentifier("reminder-detail.open-link")
                }
            }
        }
        .navigationTitle(Text(verbatim: model.item.title))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(LocalizedStringResource(
                    "reminder.action.edit",
                    table: "Reminder"
                )) {
                    router.showEdit(model.id)
                }
                .accessibilityIdentifier("reminder-detail.edit")

                Button(LocalizedStringResource(
                    "reminder.action.delete",
                    table: "Reminder"
                ), role: .destructive) {
                    actions.requestDelete(model.id)
                }
                .disabled(actions.isWorking(model.id))
                .accessibilityIdentifier("reminder-detail.delete")
            }
        }
        .alert(
            LocalizedStringResource(
                "reminder.form.delete-confirmation.title",
                table: "ReminderForm"
            ),
            isPresented: deleteConfirmationPresented
        ) {
            Button(role: .destructive, action: confirmDelete) {
                Text(LocalizedStringResource(
                    "reminder.form.delete-confirmation.confirm",
                    table: "ReminderForm"
                ))
                    .accessibilityIdentifier("reminder-detail.delete-confirm")
            }
            Button(role: .cancel) {
                actions.cancelDelete(model.id)
            } label: {
                Text(LocalizedStringResource(
                    "reminder.action.cancel",
                    table: "Reminder"
                ))
                    .accessibilityIdentifier("reminder-detail.delete-cancel")
            }
        } message: {
            Text(LocalizedStringResource(
                "reminder.form.delete-confirmation.message",
                table: "ReminderForm"
            ))
        }
        .announcesAccessibilityErrors(actionAccessibilityErrors)
        .background {
            AccessibilityIdentifierContainer(identifier: "reminder-detail.root")
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { actions.enabledValue(for: model.id, fallback: model.item.enabled) },
            set: { enabled in
                Task {
                    await actions.setEnabled(
                        enabled,
                        for: model.id,
                        fallback: model.item.enabled
                    )
                }
            }
        )
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { actions.pendingDeleteID == model.id },
            set: { presented in
                if !presented { actions.cancelDelete(model.id) }
            }
        )
    }

    private func confirmDelete() {
        guard actions.consumeDeleteConfirmation(model.id) else { return }
        Task {
            await router.performReminderDeletion(model.id) {
                await actions.performConfirmedDelete(model.id)
            }
        }
    }

    private var actionAccessibilityErrors: [AccessibilityErrorIdentity] {
        guard case let .failed(id, failure) = actions.state, id == model.id else {
            return []
        }
        return [failure.accessibilityIdentity]
    }

    private var sourceTimeZoneIdentifier: String {
        model.item.sourceWallClock?.timeZoneIdentifier ?? TimeZone.current.identifier
    }
}

private extension MaterializedRequestTypePresentation {
    var localizedResource: LocalizedStringResource {
        switch self {
        case .oneShot:
            LocalizedStringResource(
                "reminder.request-type.rolling-one-shot",
                table: "Reminder"
            )
        case .repeating:
            LocalizedStringResource(
                "reminder.request-type.direct-repeating",
                table: "Reminder"
            )
        }
    }
}
