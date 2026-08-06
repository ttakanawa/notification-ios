import SwiftUI
import UIKit

struct DataUnavailableView: View {
    @Bindable var actions: DataUnavailableActions

    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ContentUnavailableView {
                        Label(
                            "data_unavailable.title",
                            systemImage: "externaldrive.badge.exclamationmark"
                        )
                    } description: {
                        VStack(spacing: 8) {
                            Text("data_unavailable.description")
                            Text("data_unavailable.notifications-may-continue")
                                .fontWeight(.semibold)
                                .accessibilityIdentifier(
                                    "data-unavailable.notifications-may-continue"
                                )
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section("settings.section.notifications") {
                    Toggle(
                        "settings.notifications.this-device",
                        isOn: notificationsEnabledBinding
                    )
                    .disabled(actions.isWorking)
                    .accessibilityIdentifier(
                        "data-unavailable.notifications-this-device"
                    )

                    Button {
                        Task { await actions.removeAllPending() }
                    } label: {
                        Label("data_unavailable.remove-pending", systemImage: "bell.slash")
                    }
                    .disabled(actions.isWorking)
                    .accessibilityIdentifier("data-unavailable.remove-pending")

                    Text("data_unavailable.remove-pending.explanation")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        openNotificationSettings()
                    } label: {
                        Label("settings.open-os-settings", systemImage: "gear")
                    }
                    .accessibilityIdentifier("data-unavailable.open-os-settings")

                    if let error = actions.actionError {
                        Label(error.semanticKey, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("data-unavailable.action-error")
                    }
                }

                Section {
                    Button("common.retry") {
                        Task { await actions.retry() }
                    }
                    .disabled(actions.didRequestRetry)
                    .accessibilityIdentifier("data-unavailable.retry")
                }
            }
            .navigationTitle("data_unavailable.title")
        }
        .task { await actions.load() }
        .announcesAccessibilityErrors(accessibilityErrors)
        .accessibilityIdentifier("data-unavailable.root")
    }

    private var notificationsEnabledBinding: Binding<Bool> {
        Binding(
            get: { actions.isEnabled },
            set: { enabled in
                Task { await actions.setEnabled(enabled) }
            }
        )
    }

    private var accessibilityErrors: [AccessibilityErrorIdentity] {
        var result: [AccessibilityErrorIdentity] = [.dataUnavailable]
        if let error = actions.actionError {
            result.append(error.accessibilityIdentity)
        }
        return result
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else {
            return
        }
        openURL(url)
    }
}
