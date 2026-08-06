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
                    "settings.notifications.this-device",
                    isOn: notificationsEnabledBinding
                )
                .disabled(model.isWorking)
                .accessibilityIdentifier("settings.notifications-this-device")

                Text("settings.notifications.explanation")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LabeledContent("settings.authorization.title") {
                    Text(model.authorization.rawStatus.semanticKey)
                        .accessibilityIdentifier("settings.authorization-status")
                }

                Text(verbatim: authorizationRawValue)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.authorization-raw-value")

                Button {
                    openNotificationSettings()
                } label: {
                    Label("settings.open-os-settings", systemImage: "gear")
                }
                .accessibilityIdentifier("settings.open-os-settings")

                if let error = model.actionError {
                    Label(error.semanticKey, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.action-error")
                }
            } header: {
                Text("settings.section.notifications")
            }

            Section("settings.section.organization") {
                NavigationLink {
                    TagManagementView(model: tagModel)
                } label: {
                    Label("settings.tags", systemImage: "tag")
                }
                .accessibilityIdentifier("settings.tags")

                NavigationLink {
                    AboutPrivacyView()
                } label: {
                    Label("settings.about-privacy", systemImage: "hand.raised")
                }
                .accessibilityIdentifier("settings.about-privacy")
            }
        }
        .navigationTitle("settings.title")
        .task { await model.load() }
        .announcesAccessibilityErrors(accessibilityErrors)
        .accessibilityIdentifier("settings.root")
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
            table: "Localizable",
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
    var semanticKey: LocalizedStringKey {
        switch self {
        case .notDetermined: "settings.authorization.not-determined"
        case .denied: "settings.authorization.denied"
        case .authorized: "settings.authorization.authorized"
        case .provisional: "settings.authorization.provisional"
        case .ephemeral: "settings.authorization.ephemeral"
        case .unknown: "settings.authorization.unknown"
        }
    }
}

extension NotificationSettingsActionErrorIdentity {
    var semanticKey: LocalizedStringKey {
        switch self {
        case .authorizationRequest: "settings.error.authorization-request"
        case .pendingCleanup: "settings.error.pending-cleanup"
        }
    }

    var accessibilityIdentity: AccessibilityErrorIdentity {
        switch self {
        case .authorizationRequest: .settingsAuthorizationRequest
        case .pendingCleanup: .settingsPendingCleanup
        }
    }
}
