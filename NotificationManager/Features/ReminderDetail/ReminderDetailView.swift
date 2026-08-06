import Foundation
import SwiftUI

struct ReminderDetailView: View {
    let model: ReminderDetailModel
    @Bindable var router: AppRouter
    @Bindable var actions: ReminderActionCoordinator

    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section("reminder.detail.section.status") {
                Label(model.lifecycleStatus.semanticKey, systemImage: model.lifecycleStatus.systemImage)
                    .accessibilityIdentifier("reminder-detail.lifecycle-status")

                Toggle("reminder.field.enabled", isOn: enabledBinding)
                    .disabled(actions.isWorking(model.id))
                    .accessibilityIdentifier("reminder-detail.enabled")

                if actions.state == .failed(model.id, .enabledChange) {
                    Label("reminder.action.enabled-change-failed", systemImage: "exclamationmark.triangle")
                        .accessibilityIdentifier("reminder-detail.enabled-error")
                } else if actions.state == .failed(model.id, .delete) {
                    Label("reminder.action.delete-failed", systemImage: "exclamationmark.triangle")
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

            Section("reminder.detail.section.schedule") {
                if let source = model.item.sourceWallClock {
                    LabeledContent("reminder.field.source-time") {
                        Text(verbatim: source.presentationValue)
                    }
                }
                if let sourceTime = model.sourceTime {
                    LabeledContent("reminder.field.source-instant") {
                        Text(sourceTime, format: .dateTime)
                            .environment(\.timeZone, sourceTimeZone ?? .current)
                    }
                }
                if let currentDeviceTime = model.currentDeviceTime {
                    LabeledContent("reminder.field.current-device-time") {
                        Text(currentDeviceTime, format: .dateTime)
                    }
                }
                if let summary = model.localizedRepeatSummary {
                    LabeledContent("reminder.field.repeat") {
                        Text(verbatim: summary)
                    }
                }
                if let summary = model.repeatEndSummary {
                    LabeledContent("reminder.field.repeat-end") {
                        Text(verbatim: summary)
                    }
                }
                if let summary = model.earlyReminderSummary {
                    LabeledContent("reminder.field.early-reminder") {
                        Text(verbatim: summary)
                    }
                }
                if !model.item.tags.isEmpty {
                    LabeledContent("reminder.field.tags") {
                        Text(verbatim: model.item.tags.map(\.name).joined(separator: ", "))
                    }
                }
            }

            if let notes = model.notes, !notes.isEmpty {
                Section("reminder.detail.section.notes") {
                    Text(verbatim: notes)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("reminder.detail.section.next-notifications") {
                NextNotificationsView(
                    directOSFire: model.directOSFire,
                    notifications: model.nextNotifications
                )
            }

            if !model.requestDiagnostics.isEmpty || !model.alertGroups.isEmpty {
                Section("reminder.detail.section.diagnostics") {
                    ForEach(model.requestDiagnostics) { request in
                        LabeledContent("reminder.diagnostics.request-type") {
                            Text(request.kind.semanticKey)
                        }
                        .accessibilityIdentifier("reminder-detail.request-type")
                    }
                    ForEach(model.alertGroups) { group in
                        LabeledContent {
                            Label(group.outcome.semanticKey, systemImage: group.outcome.systemImage)
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
                        Label("reminder.action.open-link", systemImage: "safari")
                    }
                    .accessibilityIdentifier("reminder-detail.open-link")
                }
            }
        }
        .navigationTitle(model.item.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("reminder.action.edit") {
                    router.showEdit(model.id)
                }
                .accessibilityIdentifier("reminder-detail.edit")

                Button("reminder.action.delete", role: .destructive) {
                    actions.requestDelete(model.id)
                }
                .disabled(actions.isWorking(model.id))
                .accessibilityIdentifier("reminder-detail.delete")
            }
        }
        .alert(
            "reminder.form.delete-confirmation.title",
            isPresented: deleteConfirmationPresented
        ) {
            Button("reminder.form.delete-confirmation.confirm", role: .destructive) {
                guard actions.consumeDeleteConfirmation(model.id) else { return }
                Task {
                    await router.performReminderDeletion(model.id) {
                        await actions.performConfirmedDelete(model.id)
                    }
                }
            }
            .accessibilityIdentifier("reminder-detail.delete-confirm")
            Button("reminder.action.cancel", role: .cancel) {
                actions.cancelDelete(model.id)
            }
        } message: {
            Text("reminder.form.delete-confirmation.message")
        }
        .accessibilityIdentifier("reminder-detail.root")
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

    private var sourceTimeZone: TimeZone? {
        model.item.sourceWallClock.flatMap {
            TimeZone(identifier: $0.timeZoneIdentifier)
        }
    }
}

private extension MaterializedRequestTypePresentation {
    var semanticKey: LocalizedStringKey {
        switch self {
        case .oneShot: "reminder.request-type.rolling-one-shot"
        case .repeating: "reminder.request-type.direct-repeating"
        }
    }
}
