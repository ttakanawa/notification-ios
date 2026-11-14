import SwiftUI
import UIKit

struct SettingsView: View {
    @Bindable var model: NotificationSettingsModel
    @Bindable var iCloudModel: ICloudSyncStatusModel
    @Bindable var tagModel: TagManagementModel
    @Bindable var appIconModel: AppIconSelectionModel

    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            notificationSection
            appearanceSection
            organizationSection
            ICloudSettingsSection(model: iCloudModel)

            if #available(iOS 26.0, *) {
                Section {
                    NavigationLink {
                        AlarmKitTrialView()
                    } label: {
                        AppRowLabel(
                            title: LocalizedStringResource(
                                "settings.alarmkit-trial.link", table: "Settings"),
                            systemImage: "alarm.fill", color: .orange)
                    }
                    .accessibilityIdentifier("settings.alarmkit-trial")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(
            LocalizedStringResource(
                "settings.title",
                table: "Settings"
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load()
            await iCloudModel.refreshAccountAvailability()
        }
        .announcesAccessibilityErrors(accessibilityErrors)
        .background {
            AccessibilityIdentifierContainer(identifier: "settings.root")
        }
    }

    private var notificationSection: some View {
        Section {
            Toggle(isOn: notificationsEnabledBinding) {
                AppRowLabel(
                    title: LocalizedStringResource(
                        "settings.notifications.this-device", table: "Settings"),
                    systemImage: "bell.badge.fill", color: .red)
            }
            .disabled(model.isWorking)
            .accessibilityIdentifier("settings.notifications-this-device")

            LabeledContent {
                Text(model.authorization.rawStatus.localizedResource)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.authorization-status")
            } label: {
                AppRowLabel(
                    title: LocalizedStringResource(
                        "settings.authorization.title", table: "Settings"),
                    systemImage: "checkmark.shield.fill", color: .green)
            }

            Button {
                openNotificationSettings()
            } label: {
                AppRowLabel(
                    title: LocalizedStringResource(
                        "settings.open-os-settings", table: "Settings"),
                    systemImage: "gearshape.fill", color: .gray)
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
            Text(
                LocalizedStringResource(
                    "settings.section.notifications",
                    table: "Settings"
                ))
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    LocalizedStringResource(
                        "settings.notifications.explanation", table: "Settings"))
                Text(verbatim: authorizationRawValue)
                    .font(.caption.monospacedDigit())
                    .accessibilityIdentifier("settings.authorization-raw-value")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var appearanceSection: some View {
        Section(
            LocalizedStringResource(
                "settings.section.appearance",
                table: "Settings"
            )
        ) {
            NavigationLink {
                AppIconPickerView(model: appIconModel)
            } label: {
                AppRowLabel(
                    title: LocalizedStringResource("settings.app-icon", table: "Settings"),
                    systemImage: "app.fill", color: .indigo)
            }
            .accessibilityIdentifier("settings.app-icon")
        }
    }

    private var organizationSection: some View {
        Section(
            LocalizedStringResource(
                "settings.section.organization",
                table: "Settings"
            )
        ) {
            NavigationLink {
                TagManagementView(model: tagModel)
            } label: {
                AppRowLabel(
                    title: LocalizedStringResource("settings.tags", table: "Settings"),
                    systemImage: "tag.fill", color: .orange)
            }
            .accessibilityIdentifier("settings.tags")

            NavigationLink {
                AboutPrivacyView()
            } label: {
                AppRowLabel(
                    title: LocalizedStringResource("settings.about-privacy", table: "Settings"),
                    systemImage: "hand.raised.fill", color: .blue)
            }
            .accessibilityIdentifier("settings.about-privacy")
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

extension ICloudAccountAvailability {
    var localizedResource: LocalizedStringResource {
        let key: String.LocalizationValue =
            switch self {
            case .checking: "settings.icloud.account.checking"
            case .available: "settings.icloud.account.available"
            case .noAccount: "settings.icloud.account.no-account"
            case .restricted: "settings.icloud.account.restricted"
            case .temporarilyUnavailable: "settings.icloud.account.temporarily-unavailable"
            case .couldNotDetermine: "settings.icloud.account.could-not-determine"
            }
        return LocalizedStringResource(key, table: "Settings")
    }

}

extension ICloudSyncActivity {
    var localizedResource: LocalizedStringResource {
        let key: String.LocalizationValue =
            switch self {
            case .notObserved: "settings.icloud.activity.not-observed"
            case .inProgress: "settings.icloud.activity.in-progress"
            case .succeeded: "settings.icloud.activity.succeeded"
            case .failed: "settings.icloud.activity.failed"
            }
        return LocalizedStringResource(key, table: "Settings")
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
