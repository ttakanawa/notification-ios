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
                            LocalizedStringResource(
                                "data_unavailable.title",
                                table: "Recovery"
                            ),
                            systemImage: "externaldrive.badge.exclamationmark"
                        )
                    } description: {
                        VStack(spacing: 8) {
                            Text(LocalizedStringResource(
                                "data_unavailable.description",
                                table: "Recovery"
                            ))
                            Text(LocalizedStringResource(
                                "data_unavailable.notifications-may-continue",
                                table: "Recovery"
                            ))
                                .fontWeight(.semibold)
                                .accessibilityIdentifier(
                                    "data-unavailable.notifications-may-continue"
                                )
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section(LocalizedStringResource(
                    "settings.section.notifications",
                    table: "Settings"
                )) {
                    Toggle(
                        LocalizedStringResource(
                            "settings.notifications.this-device",
                            table: "Settings"
                        ),
                        isOn: notificationsEnabledBinding
                    )
                    .disabled(actions.isWorking)
                    .accessibilityIdentifier(
                        "data-unavailable.notifications-this-device"
                    )

                    Button {
                        Task { await actions.removeAllPending() }
                    } label: {
                        Label(
                            LocalizedStringResource(
                                "data_unavailable.remove-pending",
                                table: "Recovery"
                            ),
                            systemImage: "bell.slash"
                        )
                    }
                    .disabled(actions.isWorking)
                    .accessibilityLabel(Text(LocalizedStringResource(
                        "data_unavailable.remove-pending",
                        table: "Recovery"
                    )))
                    .accessibilityHint(Text(LocalizedStringResource(
                        "data_unavailable.remove-pending.explanation",
                        table: "Recovery"
                    )))
                    .accessibilityIdentifier("data-unavailable.remove-pending")

                    Button {
                        openNotificationSettings()
                    } label: {
                        Label(
                            LocalizedStringResource(
                                "settings.open-os-settings",
                                table: "Settings"
                            ),
                            systemImage: "gear"
                        )
                    }
                    .accessibilityIdentifier("data-unavailable.open-os-settings")

                    Text(LocalizedStringResource(
                        "data_unavailable.remove-pending.explanation",
                        table: "Recovery"
                    ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)

                    if let error = actions.actionError {
                        Label(
                            error.localizedResource,
                            systemImage: "exclamationmark.triangle"
                        )
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("data-unavailable.action-error")
                    }
                }

                Section {
                    Button(LocalizedStringResource(
                        "common.retry",
                        table: "Common"
                    )) {
                        Task { await actions.retry() }
                    }
                    .disabled(actions.isRetrying)
                    .accessibilityIdentifier("data-unavailable.retry")
                }
            }
            .navigationTitle(LocalizedStringResource(
                "data_unavailable.title",
                table: "Recovery"
            ))
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
