import Foundation
import NotificationManagerDomain

struct ReminderTagPresentation: Sendable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let normalizedName: String
}

enum PhysicalNotificationReasonRole: Sendable, Equatable {
    case primary
    case secondary
}

struct PhysicalNotificationReasonPresentation: Sendable, Equatable {
    let role: PhysicalNotificationReasonRole
    let kind: AlertKind
    let baseOccurrenceInstant: Date
}

struct PhysicalNotificationPresentation: Sendable, Equatable, Identifiable {
    var id: Date { alertInstant }

    let alertInstant: Date
    let reasons: [PhysicalNotificationReasonPresentation]
    let sourceTime: Date
    let sourceTimeZoneIdentifier: String?
    let deviceLocalTime: Date

    init(
        notification: PhysicalNotification,
        sourceTimeZoneIdentifier: String? = nil,
        deviceLocalTime: Date
    ) {
        alertInstant = notification.alertInstant
        reasons = notification.reasons.enumerated().map { index, reason in
            PhysicalNotificationReasonPresentation(
                role: index == 0 ? .primary : .secondary,
                kind: reason.kind,
                baseOccurrenceInstant: reason.baseOccurrence.instant
            )
        }
        sourceTime = notification.primaryReason.baseOccurrence.instant
        self.sourceTimeZoneIdentifier = sourceTimeZoneIdentifier
        self.deviceLocalTime = deviceLocalTime
    }

    init(
        alertInstant: Date,
        reasons: [PhysicalNotificationReasonPresentation],
        sourceTime: Date,
        sourceTimeZoneIdentifier: String? = nil,
        deviceLocalTime: Date
    ) {
        precondition(reasons.first?.role == .primary)
        self.alertInstant = alertInstant
        self.reasons = reasons
        self.sourceTime = sourceTime
        self.sourceTimeZoneIdentifier = sourceTimeZoneIdentifier
        self.deviceLocalTime = deviceLocalTime
    }

}

enum ReminderNextPresentation: Sendable, Equatable {
    case directOSFire(authoritative: Date, foundationPreview: Date?)
    case rolling(PhysicalNotificationPresentation)

    var authoritativeAlertInstant: Date {
        switch self {
        case let .directOSFire(authoritative, _): authoritative
        case let .rolling(notification): notification.alertInstant
        }
    }
}

struct ReminderListItemPresentation: Sendable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let reminderStatus: ReminderStatus
    let deviceSchedulingStatus: DeviceSchedulingStatus
    let nextPresentation: ReminderNextPresentation?
    let nextReason: AlertKind?
    let sourceWallClock: SourceWallClock?
    let localizedRepeatSummary: String?
    let tags: [ReminderTagPresentation]
    let enabled: Bool
    let scheduledThrough: Date?
    let earliestGroupOutcome: AlertGroupSchedulingOutcome?
    let updatedAt: Date

    init(
        id: UUID,
        title: String,
        reminderStatus: ReminderStatus,
        deviceSchedulingStatus: DeviceSchedulingStatus,
        nextPresentation: ReminderNextPresentation?,
        nextReason: AlertKind? = nil,
        sourceWallClock: SourceWallClock? = nil,
        localizedRepeatSummary: String? = nil,
        tags: [ReminderTagPresentation] = [],
        enabled: Bool = true,
        scheduledThrough: Date? = nil,
        earliestGroupOutcome: AlertGroupSchedulingOutcome? = nil,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.reminderStatus = reminderStatus
        self.deviceSchedulingStatus = deviceSchedulingStatus
        self.nextPresentation = nextPresentation
        self.nextReason = nextReason
        self.sourceWallClock = sourceWallClock
        self.localizedRepeatSummary = localizedRepeatSummary
        self.tags = tags
        self.enabled = enabled
        self.scheduledThrough = scheduledThrough
        self.earliestGroupOutcome = earliestGroupOutcome
        self.updatedAt = updatedAt
    }

    var lifecycleStatus: LifecycleStatus { reminderStatus.primary }
}

struct ReminderListSections: Sendable, Equatable {
    let upcoming: [ReminderListItemPresentation]
    let needsAttention: [ReminderListItemPresentation]
    let inactive: [ReminderListItemPresentation]
}

enum ReminderListProjection {
    static func make(
        from items: [ReminderListItemPresentation],
        selectedTagID: UUID?
    ) -> ReminderListSections {
        let filtered = items.filter { item in
            guard let selectedTagID else { return true }
            return item.tags.contains { $0.id == selectedTagID }
        }

        return ReminderListSections(
            upcoming: filtered.filter { $0.lifecycleStatus == .active }.sorted(by: upcomingOrder),
            needsAttention: filtered.filter {
                $0.lifecycleStatus == .updateRequired || $0.lifecycleStatus == .invalidSchedule
            }.sorted(by: updatedOrder),
            inactive: filtered.filter {
                $0.lifecycleStatus == .disabled || $0.lifecycleStatus == .expired
            }.sorted(by: updatedOrder)
        )
    }

    private static func upcomingOrder(
        _ lhs: ReminderListItemPresentation,
        _ rhs: ReminderListItemPresentation
    ) -> Bool {
        switch (lhs.nextPresentation, rhs.nextPresentation) {
        case let (.some(lhsNext), .some(rhsNext)):
            if lhsNext.authoritativeAlertInstant != rhsNext.authoritativeAlertInstant {
                return lhsNext.authoritativeAlertInstant < rhsNext.authoritativeAlertInstant
            }
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            break
        }
        return stableID(lhs.id) < stableID(rhs.id)
    }

    private static func updatedOrder(
        _ lhs: ReminderListItemPresentation,
        _ rhs: ReminderListItemPresentation
    ) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return stableID(lhs.id) < stableID(rhs.id)
    }

    private static func stableID(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }
}
