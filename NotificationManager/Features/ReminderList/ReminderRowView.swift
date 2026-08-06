import NotificationManagerDomain
import SwiftUI

struct ReminderRowView: View {
    let item: ReminderListItemPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 12)
                if item.lifecycleStatus != .active && item.lifecycleStatus != .disabled {
                    lifecycleLabel
                }
            }

            nextAlert

            if let source = item.sourceWallClock {
                Text(source.presentationValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("reminder.row.source-time")
                    .accessibilityValue(source.presentationValue)
            }

            if let summary = item.localizedRepeatSummary {
                Text(summary)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reminder-row.repeat-summary")
            }

            if !item.tags.isEmpty {
                Label(item.tags.map(\.name).joined(separator: ", "), systemImage: "tag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let scheduledThrough = item.scheduledThrough {
                LabeledContent("reminder.scheduling.scheduled-through") {
                    Text(scheduledThrough, format: .dateTime)
                }
                .font(.caption)
            }

            if item.deviceSchedulingStatus != .notApplicable {
                Label(
                    item.deviceSchedulingStatus.semanticKey,
                    systemImage: item.deviceSchedulingStatus.systemImage
                )
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("reminder-row.device-status")
            }

            if let outcome = item.earliestGroupOutcome, outcome != .scheduled {
                Label(outcome.semanticKey, systemImage: outcome.systemImage)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reminder-row.group-outcome")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var nextAlert: some View {
        switch item.nextPresentation {
        case let .directOSFire(authoritative, _):
            VStack(alignment: .leading, spacing: 2) {
                LabeledContent("reminder.next.os-fire") {
                    Text(authoritative, format: .dateTime)
                }
                if let nextReason = item.nextReason {
                    Label(nextReason.semanticKey, systemImage: "bell")
                        .font(.caption)
                }
            }
            .font(.subheadline.weight(.semibold))
            .accessibilityIdentifier("reminder-row.next-os-fire")
        case let .rolling(notification):
            VStack(alignment: .leading, spacing: 2) {
                Text(notification.alertInstant, format: .dateTime)
                    .font(.subheadline.weight(.semibold))
                ForEach(Array(notification.reasons.enumerated()), id: \.offset) { _, reason in
                    LabeledContent(reason.role.semanticKey) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Label(reason.kind.semanticKey, systemImage: "bell")
                            Text(reason.baseOccurrenceInstant, format: .dateTime)
                        }
                    }
                    .font(.caption)
                }
            }
            .accessibilityIdentifier("reminder-row.next-rolling")
        case nil:
            Text("reminder.next.unavailable")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var lifecycleLabel: some View {
        Label(item.lifecycleStatus.semanticKey, systemImage: item.lifecycleStatus.systemImage)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("reminder-row.lifecycle-status")
    }
}

extension SourceWallClock {
    var presentationValue: String {
        String(
            format: "%04d-%02d-%02d %02d:%02d · %@",
            year,
            month,
            day,
            hour,
            minute,
            timeZoneIdentifier
        )
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
