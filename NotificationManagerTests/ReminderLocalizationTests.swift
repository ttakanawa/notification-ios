import Foundation
import NotificationManagerDomain
import Testing
@testable import NotificationManager

struct ReminderLocalizationTests {
    @Test func actionFailuresUseReminderResources() {
        let fixtures: [(ReminderActionFailure, String)] = [
            (.enabledChange, "reminder.action.enabled-change-failed"),
            (.delete, "reminder.action.delete-failed")
        ]

        for (failure, key) in fixtures {
            expectReminderResource(failure.localizedResource, key: key)
        }
    }

    @Test func alertKindsUseReminderResources() {
        let fixtures: [(AlertKind, String)] = [
            (.main, "reminder.reason.main"),
            (.early, "reminder.reason.early")
        ]

        for (kind, key) in fixtures {
            expectReminderResource(kind.localizedResource, key: key)
        }
    }

    @Test func physicalReasonRolesUseReminderResources() {
        let fixtures: [(PhysicalNotificationReasonRole, String)] = [
            (.primary, "reminder.next.primary-reason"),
            (.secondary, "reminder.next.secondary-reason")
        ]

        for (role, key) in fixtures {
            expectReminderResource(role.localizedResource, key: key)
        }
    }

    @Test func lifecycleStatusesUseReminderResources() {
        let fixtures: [(LifecycleStatus, String)] = [
            (.active, "reminder.lifecycle.active"),
            (.disabled, "reminder.lifecycle.disabled"),
            (.expired, "reminder.lifecycle.expired"),
            (.updateRequired, "reminder.lifecycle.update-required"),
            (.invalidSchedule, "reminder.lifecycle.invalid-schedule")
        ]

        for (status, key) in fixtures {
            expectReminderResource(status.localizedResource, key: key)
        }
    }

    @Test func deviceSchedulingStatusesUseReminderResources() {
        let fixtures: [(DeviceSchedulingStatus, String)] = [
            (.notApplicable, "reminder.device-status.not-applicable"),
            (.notScheduledThisDeviceOff, "reminder.device-status.device-off"),
            (.permissionNotDetermined, "reminder.device-status.permission-not-determined"),
            (.notScheduledPermissionDenied, "reminder.device-status.permission-denied"),
            (.notScheduledAuthorizationUnknown, "reminder.device-status.authorization-unknown"),
            (.unscheduledError, "reminder.device-status.error"),
            (.scheduling, "reminder.device-status.scheduling"),
            (.unscheduledCapacity, "reminder.device-status.capacity"),
            (.scheduled, "reminder.device-status.scheduled")
        ]

        for (status, key) in fixtures {
            expectReminderResource(status.localizedResource, key: key)
        }
    }

    @Test func alertGroupOutcomesUseReminderResources() {
        let fixtures: [(AlertGroupSchedulingOutcome, String)] = [
            (.scheduled, "reminder.group-outcome.scheduled"),
            (.unscheduledCapacity, "reminder.group-outcome.capacity"),
            (.unscheduledError, "reminder.group-outcome.error")
        ]

        for (outcome, key) in fixtures {
            expectReminderResource(outcome.localizedResource, key: key)
        }
    }

    private func expectReminderResource(
        _ resource: LocalizedStringResource,
        key: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(resource.key == .init(stringLiteral: key), sourceLocation: sourceLocation)
        #expect(resource.table == "Reminder", sourceLocation: sourceLocation)
    }
}
