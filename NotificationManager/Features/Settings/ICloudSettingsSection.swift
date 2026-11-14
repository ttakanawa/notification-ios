import NotificationManagerPersistence
import SwiftUI

struct ICloudSettingsSection: View {
    @Bindable var model: ICloudSyncStatusModel

    var body: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { model.isSyncEnabled },
                    set: { enabled in
                        Task { await model.setSyncEnabled(enabled) }
                    })
            ) {
                Text(LocalizedStringResource("settings.icloud.switch", table: "Settings"))
            }
            .accessibilityIdentifier("settings.icloud.switch")

            LabeledContent {
                Text(model.accountAvailability.localizedResource)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.icloud.account-status")
            } label: {
                AppRowLabel(
                    title: LocalizedStringResource(
                        "settings.icloud.account.title", table: "Settings"),
                    systemImage: "icloud.fill", color: .blue
                )
            }
            LabeledContent {
                if model.retainedPhase == .off {
                    Text(LocalizedStringResource("settings.icloud.off", table: "Settings"))
                } else if model.retainedPhase == .confirmationRequired {
                    Text(
                        LocalizedStringResource(
                            "settings.icloud.confirmation-needed", table: "Settings"))
                } else {
                    Text(model.syncActivity.localizedResource)
                        .accessibilityIdentifier("settings.icloud.activity-status")
                }
            } label: {
                AppRowLabel(
                    title: LocalizedStringResource(
                        "settings.icloud.activity.title", table: "Settings"),
                    systemImage: "arrow.triangle.2.circlepath", color: .teal
                )
            }
            Button {
                Task { await model.refreshAccountAvailability() }
            } label: {
                Text(LocalizedStringResource("settings.icloud.retry", table: "Settings"))
            }
            if !model.recoveryCopies.isEmpty {
                NavigationLink {
                    List(model.recoveryCopies) { revision in
                        NavigationLink {
                            ICloudRecoveryCopyView(model: model, revision: revision)
                        } label: {
                            Text(verbatim: revision.entityKey)
                        }
                    }
                    .navigationTitle(
                        LocalizedStringResource("settings.icloud.recovery", table: "Settings"))
                } label: {
                    Text(LocalizedStringResource("settings.icloud.recovery", table: "Settings"))
                }
            }
            if model.actionFailed {
                Text(LocalizedStringResource("settings.icloud.save-failed", table: "Settings"))
                    .foregroundStyle(.red)
            }
        } header: {
            Text(LocalizedStringResource("settings.section.icloud", table: "Settings"))
        } footer: {
            Text(LocalizedStringResource("settings.icloud.explanation", table: "Settings"))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.icloud.explanation")
        }
        .background { AccessibilityIdentifierContainer(identifier: "settings.icloud.section") }
    }
}

private struct ICloudRecoveryCopyView: View {
    @Bindable var model: ICloudSyncStatusModel
    let revision: RetainedCloudRevision
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let payload = revision.payload {
                Text(
                    verbatim: String(data: payload, encoding: .utf8)
                        ?? payload.base64EncodedString()
                )
                .font(.caption.monospaced())
                .textSelection(.enabled)
            } else {
                Text(LocalizedStringResource("settings.icloud.deleted-version", table: "Settings"))
            }
            Button {
                Task {
                    await model.restore(revision)
                    if !model.actionFailed { dismiss() }
                }
            } label: {
                Text(LocalizedStringResource("settings.icloud.restore-version", table: "Settings"))
            }
        }
        .navigationTitle(LocalizedStringResource("settings.icloud.recovery", table: "Settings"))
    }
}

struct ICloudAccountConfirmation: ViewModifier {
    let model: ICloudSyncStatusModel?

    func body(content: Content) -> some View {
        let confirmationRequired = model?.retainedPhase == .confirmationRequired
        content.alert(
            Text(LocalizedStringResource("settings.icloud.confirm.title", table: "Settings")),
            isPresented: Binding(
                get: { model?.retainedPhase == .confirmationRequired }, set: { _ in })
        ) {
            Button(role: .cancel) {
                Task { await model?.confirmAccount(false) }
            } label: {
                Text(LocalizedStringResource("settings.icloud.confirm.refuse", table: "Settings"))
            }
            Button {
                Task { await model?.confirmAccount(true) }
            } label: {
                Text(LocalizedStringResource("settings.icloud.confirm.accept", table: "Settings"))
            }
        } message: {
            Text(LocalizedStringResource("settings.icloud.confirm.message", table: "Settings"))
        }
    }
}
