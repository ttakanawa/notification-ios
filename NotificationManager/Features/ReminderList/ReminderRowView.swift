import NotificationManagerDomain
import SwiftUI

struct ReminderRowView: View {
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var deviceTimeZone
    let item: ReminderListItemPresentation

    private let scheduleFormatter = CompactScheduleTimeFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: item.title)
                .font(.headline)
                .multilineTextAlignment(.leading)

            if let notes = item.displayNotes {
                Text(verbatim: notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reminder-row.notes")
            }

            if item.nextPresentation != nil || item.displayRepeatSummary != nil {
                CompactScheduleLineView(
                    presentation: item.nextPresentation.map { nextPresentation in
                        scheduleFormatter.presentation(
                            for: nextPresentation.authoritativeAlertInstant,
                            sourceTimeZoneIdentifier: item.sourceWallClock?.timeZoneIdentifier,
                            locale: locale,
                            deviceTimeZone: deviceTimeZone
                        )
                    },
                    localizedRepeatSummary: item.displayRepeatSummary
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .padding(.vertical, 4)
    }

}

extension AlertKind {
    var semanticKey: LocalizedStringKey {
        switch self {
        case .main: "reminder.reason.main"
        case .early: "reminder.reason.early"
        }
    }
}

extension PhysicalNotificationReasonRole {
    var semanticKey: LocalizedStringKey {
        switch self {
        case .primary: "reminder.next.primary-reason"
        case .secondary: "reminder.next.secondary-reason"
        }
    }
}

extension LifecycleStatus {
    var semanticKey: LocalizedStringKey {
        switch self {
        case .active: "reminder.lifecycle.active"
        case .disabled: "reminder.lifecycle.disabled"
        case .expired: "reminder.lifecycle.expired"
        case .updateRequired: "reminder.lifecycle.update-required"
        case .invalidSchedule: "reminder.lifecycle.invalid-schedule"
        }
    }

    var systemImage: String {
        switch self {
        case .active: "checkmark.circle"
        case .disabled: "pause.circle"
        case .expired: "clock.badge.xmark"
        case .updateRequired: "arrow.triangle.2.circlepath"
        case .invalidSchedule: "exclamationmark.triangle"
        }
    }
}

extension DeviceSchedulingStatus {
    var semanticKey: LocalizedStringKey {
        switch self {
        case .notApplicable: "reminder.device-status.not-applicable"
        case .notScheduledThisDeviceOff: "reminder.device-status.device-off"
        case .permissionNotDetermined: "reminder.device-status.permission-not-determined"
        case .notScheduledPermissionDenied: "reminder.device-status.permission-denied"
        case .notScheduledAuthorizationUnknown: "reminder.device-status.authorization-unknown"
        case .unscheduledError: "reminder.device-status.error"
        case .scheduling: "reminder.device-status.scheduling"
        case .unscheduledCapacity: "reminder.device-status.capacity"
        case .scheduled: "reminder.device-status.scheduled"
        }
    }

    var systemImage: String {
        switch self {
        case .notApplicable: "minus.circle"
        case .notScheduledThisDeviceOff, .notScheduledPermissionDenied,
             .notScheduledAuthorizationUnknown, .unscheduledCapacity:
            "bell.slash"
        case .permissionNotDetermined, .scheduling:
            "clock.arrow.circlepath"
        case .unscheduledError:
            "exclamationmark.triangle"
        case .scheduled:
            "bell.badge"
        }
    }
}

extension AlertGroupSchedulingOutcome {
    var semanticKey: LocalizedStringKey {
        switch self {
        case .scheduled: "reminder.group-outcome.scheduled"
        case .unscheduledCapacity: "reminder.group-outcome.capacity"
        case .unscheduledError: "reminder.group-outcome.error"
        }
    }

    var systemImage: String {
        switch self {
        case .scheduled: "checkmark.circle"
        case .unscheduledCapacity: "tray.full"
        case .unscheduledError: "exclamationmark.triangle"
        }
    }
}
