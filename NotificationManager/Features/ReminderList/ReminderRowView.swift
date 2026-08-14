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
    var localizedResource: LocalizedStringResource {
        switch self {
        case .main: LocalizedStringResource("reminder.reason.main", table: "Reminder")
        case .early: LocalizedStringResource("reminder.reason.early", table: "Reminder")
        }
    }
}

extension PhysicalNotificationReasonRole {
    var localizedResource: LocalizedStringResource {
        switch self {
        case .primary:
            LocalizedStringResource("reminder.next.primary-reason", table: "Reminder")
        case .secondary:
            LocalizedStringResource("reminder.next.secondary-reason", table: "Reminder")
        }
    }
}

extension LifecycleStatus {
    var localizedResource: LocalizedStringResource {
        switch self {
        case .active:
            LocalizedStringResource("reminder.lifecycle.active", table: "Reminder")
        case .disabled:
            LocalizedStringResource("reminder.lifecycle.disabled", table: "Reminder")
        case .expired:
            LocalizedStringResource("reminder.lifecycle.expired", table: "Reminder")
        case .updateRequired:
            LocalizedStringResource("reminder.lifecycle.update-required", table: "Reminder")
        case .invalidSchedule:
            LocalizedStringResource("reminder.lifecycle.invalid-schedule", table: "Reminder")
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
    var localizedResource: LocalizedStringResource {
        switch self {
        case .notApplicable:
            LocalizedStringResource("reminder.device-status.not-applicable", table: "Reminder")
        case .notScheduledThisDeviceOff:
            LocalizedStringResource("reminder.device-status.device-off", table: "Reminder")
        case .permissionNotDetermined:
            LocalizedStringResource(
                "reminder.device-status.permission-not-determined",
                table: "Reminder"
            )
        case .notScheduledPermissionDenied:
            LocalizedStringResource("reminder.device-status.permission-denied", table: "Reminder")
        case .notScheduledAuthorizationUnknown:
            LocalizedStringResource(
                "reminder.device-status.authorization-unknown",
                table: "Reminder"
            )
        case .unscheduledError:
            LocalizedStringResource("reminder.device-status.error", table: "Reminder")
        case .scheduling:
            LocalizedStringResource("reminder.device-status.scheduling", table: "Reminder")
        case .unscheduledCapacity:
            LocalizedStringResource("reminder.device-status.capacity", table: "Reminder")
        case .scheduled:
            LocalizedStringResource("reminder.device-status.scheduled", table: "Reminder")
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
    var localizedResource: LocalizedStringResource {
        switch self {
        case .scheduled:
            LocalizedStringResource("reminder.group-outcome.scheduled", table: "Reminder")
        case .unscheduledCapacity:
            LocalizedStringResource("reminder.group-outcome.capacity", table: "Reminder")
        case .unscheduledError:
            LocalizedStringResource("reminder.group-outcome.error", table: "Reminder")
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
