import Foundation
import NotificationManagerDomain

struct AlertGroupSchedulingPresentation: Sendable, Equatable, Identifiable {
    var id: AlertGroupID { groupID }

    let groupID: AlertGroupID
    let outcome: AlertGroupSchedulingOutcome
}

enum MaterializedRequestTypePresentation: Sendable, Equatable {
    case oneShot
    case repeating
}

struct MaterializedRequestDiagnosticPresentation: Sendable, Equatable, Identifiable {
    var id: String { identifier }

    let identifier: String
    let kind: MaterializedRequestTypePresentation
}

struct ReminderDetailModel: Sendable, Equatable, Identifiable {
    var id: UUID { item.id }
    var lifecycleStatus: LifecycleStatus { item.lifecycleStatus }

    let item: ReminderListItemPresentation
    let notes: String?
    let url: URL?
    let repeatEndSummary: String?
    let earlyReminderSummary: String?
    let sourceTime: Date?
    let currentDeviceTime: Date?
    let localizedRepeatSummary: String?
    let nextNotifications: [PhysicalNotificationPresentation]
    let alertGroups: [AlertGroupSchedulingPresentation]
    let scheduledThrough: Date?
    let requestDiagnostics: [MaterializedRequestDiagnosticPresentation]

    init(
        item: ReminderListItemPresentation,
        notes: String? = nil,
        url: URL? = nil,
        repeatEndSummary: String? = nil,
        earlyReminderSummary: String? = nil,
        sourceTime: Date?,
        currentDeviceTime: Date?,
        localizedRepeatSummary: String?,
        nextNotifications: [PhysicalNotificationPresentation],
        alertGroups: [AlertGroupSchedulingPresentation],
        scheduledThrough: Date?,
        requestDiagnostics: [MaterializedRequestDiagnosticPresentation]
    ) {
        self.item = item
        self.notes = notes
        self.url = url
        self.repeatEndSummary = repeatEndSummary
        self.earlyReminderSummary = earlyReminderSummary
        self.sourceTime = sourceTime
        self.currentDeviceTime = currentDeviceTime
        self.localizedRepeatSummary = localizedRepeatSummary
        self.nextNotifications = nextNotifications
        self.alertGroups = alertGroups
        self.scheduledThrough = scheduledThrough
        self.requestDiagnostics = requestDiagnostics
    }

    var deviceSchedulingStatusForDisplay: DeviceSchedulingStatus? {
        item.deviceSchedulingStatus == .notApplicable ? nil : item.deviceSchedulingStatus
    }

    var directOSFire: (authoritative: Date, foundationPreview: Date?)? {
        guard case let .directOSFire(authoritative, preview) = item.nextPresentation else {
            return nil
        }
        return (authoritative, preview)
    }
}
