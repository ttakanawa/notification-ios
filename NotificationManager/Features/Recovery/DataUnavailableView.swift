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
                            Text(
                                LocalizedStringResource(
                                    "data_unavailable.description",
                                    table: "Recovery"
                                ))
                            Text(
                                LocalizedStringResource(
                                    "data_unavailable.notifications-may-continue",
                                    table: "Recovery"
                                )
                            )
                            .fontWeight(.semibold)
                            .accessibilityIdentifier(
                                "data-unavailable.notifications-may-continue"
                            )
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))

                Section {
                    Toggle(isOn: notificationsEnabledBinding) {
                        AppRowLabel(
                            title: LocalizedStringResource(
                                "settings.notifications.this-device", table: "Settings"),
                            systemImage: "bell.badge.fill", color: .red)
                    }
                    .disabled(actions.isWorking)
                    .accessibilityIdentifier(
                        "data-unavailable.notifications-this-device"
                    )

                    Button {
                        Task { await actions.removeAllPending() }
                    } label: {
                        AppRowLabel(
                            title: LocalizedStringResource(
                                "data_unavailable.remove-pending", table: "Recovery"),
                            systemImage: "bell.slash.fill", color: .orange)
                    }
                    .disabled(actions.isWorking)
                    .accessibilityLabel(
                        Text(
                            LocalizedStringResource(
                                "data_unavailable.remove-pending",
                                table: "Recovery"
                            ))
                    )
                    .accessibilityHint(
                        Text(
                            LocalizedStringResource(
                                "data_unavailable.remove-pending.explanation",
                                table: "Recovery"
                            ))
                    )
                    .accessibilityIdentifier("data-unavailable.remove-pending")

                    Button {
                        openNotificationSettings()
                    } label: {
                        AppRowLabel(
                            title: LocalizedStringResource(
                                "settings.open-os-settings", table: "Settings"),
                            systemImage: "gearshape.fill", color: .gray)
                    }
                    .accessibilityIdentifier("data-unavailable.open-os-settings")

                    if let error = actions.actionError {
                        Label(
                            error.localizedResource,
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("data-unavailable.action-error")
                    }
                } header: {
                    Text(
                        LocalizedStringResource(
                            "settings.section.notifications", table: "Settings"))
                } footer: {
                    Text(
                        LocalizedStringResource(
                            "data_unavailable.remove-pending.explanation", table: "Recovery")
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                }

                Section {
                    Button {
                        Task { await actions.retry() }
                    } label: {
                        HStack {
                            Label(
                                LocalizedStringResource("common.retry", table: "Common"),
                                systemImage: "arrow.clockwise")
                            if actions.isRetrying {
                                Spacer()
                                ProgressView()
                            }
                        }
                        .frame(minHeight: 44)
                    }
                    .disabled(actions.isRetrying)
                    .accessibilityIdentifier("data-unavailable.retry")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(
                LocalizedStringResource(
                    "data_unavailable.title",
                    table: "Recovery"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
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
