import SwiftUI
import UIKit

struct SettingsView: View {
    @Bindable var model: NotificationSettingsModel
    @Bindable var tagModel: TagManagementModel

    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                Toggle(
                    LocalizedStringResource(
                        "settings.notifications.this-device",
                        table: "Settings"
                    ),
                    isOn: notificationsEnabledBinding
                )
                .disabled(model.isWorking)
                .accessibilityIdentifier("settings.notifications-this-device")

                Text(LocalizedStringResource(
                    "settings.notifications.explanation",
                    table: "Settings"
                ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LabeledContent {
                    Text(model.authorization.rawStatus.localizedResource)
                        .accessibilityIdentifier("settings.authorization-status")
                } label: {
                    Text(LocalizedStringResource(
                        "settings.authorization.title",
                        table: "Settings"
                    ))
                }

                Text(verbatim: authorizationRawValue)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.authorization-raw-value")

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
                .accessibilityIdentifier("settings.open-os-settings")

                if let error = model.actionError {
                    Label(
                        error.localizedResource,
                        systemImage: "exclamationmark.triangle"
                    )
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.action-error")
                }
            } header: {
                Text(LocalizedStringResource(
                    "settings.section.notifications",
                    table: "Settings"
                ))
            }

            Section(LocalizedStringResource(
                "settings.section.organization",
                table: "Settings"
            )) {
                NavigationLink {
                    TagManagementView(model: tagModel)
                } label: {
                    Label(
                        LocalizedStringResource(
                            "settings.tags",
                            table: "Settings"
                        ),
                        systemImage: "tag"
                    )
                }
                .accessibilityIdentifier("settings.tags")

                NavigationLink {
                    AboutPrivacyView()
                } label: {
                    Label(
                        LocalizedStringResource(
                            "settings.about-privacy",
                            table: "Settings"
                        ),
                        systemImage: "hand.raised"
                    )
                }
                .accessibilityIdentifier("settings.about-privacy")
            }
        }
        .navigationTitle(LocalizedStringResource(
            "settings.title",
            table: "Settings"
        ))
        .task { await model.load() }
        .announcesAccessibilityErrors(accessibilityErrors)
        .background {
            AccessibilityIdentifierContainer(identifier: "settings.root")
        }
    }

    private var notificationsEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.isEnabled },
            set: { enabled in
                Task { await model.setEnabled(enabled) }
            }
        )
    }

    private var authorizationRawValue: String {
        let format = String(
            localized: "settings.authorization.raw-value",
            table: "Settings",
            bundle: .main,
            locale: locale
        )
        return String(
            format: format,
            locale: locale,
            arguments: [Int64(model.authorization.rawValue)]
        )
    }

    private var accessibilityErrors: [AccessibilityErrorIdentity] {
        guard let error = model.actionError else { return [] }
        return [error.accessibilityIdentity]
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else {
            return
        }
        openURL(url)
    }
}

extension NotificationAuthorizationRawStatus {
    var localizedResource: LocalizedStringResource {
        switch self {
        case .notDetermined:
            LocalizedStringResource(
                "settings.authorization.not-determined",
                table: "Settings"
            )
        case .denied:
            LocalizedStringResource(
                "settings.authorization.denied",
                table: "Settings"
            )
        case .authorized:
            LocalizedStringResource(
                "settings.authorization.authorized",
                table: "Settings"
            )
        case .provisional:
            LocalizedStringResource(
                "settings.authorization.provisional",
                table: "Settings"
            )
        case .ephemeral:
            LocalizedStringResource(
                "settings.authorization.ephemeral",
                table: "Settings"
            )
        case .unknown:
            LocalizedStringResource(
                "settings.authorization.unknown",
                table: "Settings"
            )
        }
    }
}

extension NotificationSettingsActionErrorIdentity {
    var localizedResource: LocalizedStringResource {
        switch self {
        case .authorizationRequest:
            LocalizedStringResource(
                "settings.error.authorization-request",
                table: "Settings"
            )
        case .pendingCleanup:
            LocalizedStringResource(
                "settings.error.pending-cleanup",
                table: "Settings"
            )
        }
    }

    var accessibilityIdentity: AccessibilityErrorIdentity {
        switch self {
        case .authorizationRequest: .settingsAuthorizationRequest
        case .pendingCleanup: .settingsPendingCleanup
        }
    }
}
