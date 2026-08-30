import Foundation
import NotificationManagerDomain
import NotificationManagerWidgetSupport

enum WidgetSnapshotProjectionError: Error, Sendable, Equatable {
    case globalSchedulingFailure(SchedulingGlobalFailure)
}

struct WidgetSnapshotProjector: Sendable {
    func project(
        reminders: [ReminderSnapshot],
        items: [ReminderListItemPresentation],
        deviceState: DeviceSchedulingStateSnapshot,
        generatedAt: Date
    ) throws -> WidgetSnapshot {
        if let failure = deviceState.globalFailure {
            throw WidgetSnapshotProjectionError.globalSchedulingFailure(failure)
        }

        var itemsByID: [UUID: ReminderListItemPresentation] = [:]
        for item in items where itemsByID[item.id] == nil {
            itemsByID[item.id] = item
        }
        let staticRepeatingReminderIDs = staticRepeatingReminderIDs(in: deviceState)
        var candidates: [WidgetReminderEvent] = []

        for reminder in reminders {
            guard
                case .valid(let schedule, _, _) = reminder.schedule,
                let item = itemsByID[reminder.id],
                item.reminderStatus.primary == .active,
                item.deviceSchedulingStatus == .scheduled,
                let authoritative = item.nextPresentation?.authoritativeAlertInstant,
                authoritative > generatedAt
            else {
                continue
            }

            let isStaticRepeating = staticRepeatingReminderIDs.contains(reminder.id)
            var dates = [authoritative]
            if isStaticRepeating || schedule.rule == .none || item.scheduledThrough != nil {
                dates = try projectedDates(
                    reminderID: reminder.id,
                    schedule: schedule,
                    generatedAt: generatedAt,
                    authoritative: authoritative,
                    scheduledThrough: isStaticRepeating ? nil : item.scheduledThrough
                )
            }

            candidates.append(
                contentsOf: dates.prefix(WidgetSnapshotConstants.maximumEventCount + 1).map {
                    WidgetReminderEvent(
                        reminderID: reminder.id,
                        title: item.title,
                        fireDate: $0
                    )
                })
        }

        var seen = Set<EventKey>()
        let ordered = candidates.sorted(by: eventPrecedes).filter { event in
            seen.insert(EventKey(reminderID: event.reminderID, fireDate: event.fireDate)).inserted
        }
        let isTruncated = ordered.count > WidgetSnapshotConstants.maximumEventCount
        return try WidgetSnapshot(
            generatedAt: generatedAt,
            isTruncated: isTruncated,
            events: Array(ordered.prefix(WidgetSnapshotConstants.maximumEventCount))
        )
    }

    private func projectedDates(
        reminderID: UUID,
        schedule: ScheduleDefinition,
        generatedAt: Date,
        authoritative: Date,
        scheduledThrough: Date?
    ) throws -> [Date] {
        let candidateLimit = WidgetSnapshotConstants.maximumEventCount + 1
        var cursor = generatedAt
        var dates = [authoritative]
        var consumedFirstPrediction = false

        while dates.count < candidateLimit {
            let result = try NextNotificationProvider().nextPhysicalNotifications(
                for: reminderID,
                schedule: schedule,
                after: cursor,
                limit: 3,
                environment: FoundationRecurrenceEnvironment()
            )
            guard !result.notifications.isEmpty else { break }

            var reachedRollingBoundary = false
            for notification in result.notifications {
                if !consumedFirstPrediction {
                    consumedFirstPrediction = true
                    if let scheduledThrough, notification.alertInstant > scheduledThrough {
                        reachedRollingBoundary = true
                    }
                    continue
                }
                if let scheduledThrough, notification.alertInstant > scheduledThrough {
                    reachedRollingBoundary = true
                    break
                }
                if notification.alertInstant <= authoritative {
                    continue
                }
                dates.append(notification.alertInstant)
                if dates.count == candidateLimit { break }
            }
            if reachedRollingBoundary || result.exhausted || dates.count == candidateLimit {
                break
            }
            guard let lastDate = result.notifications.last?.alertInstant, lastDate > cursor else {
                break
            }
            cursor = lastDate
        }

        return dates
    }

    private func staticRepeatingReminderIDs(
        in deviceState: DeviceSchedulingStateSnapshot
    ) -> Set<UUID> {
        let codec = NotificationIdentifierCodec()
        return Set(
            deviceState.pendingOrAddedIdentifiers.compactMap { identifier in
                guard deviceState.materializedKinds[identifier] == .repeating,
                    case .currentRepeating(let reminderID, _) = codec.classify(identifier)
                else {
                    return nil
                }
                return reminderID
            })
    }

    private func eventPrecedes(_ lhs: WidgetReminderEvent, _ rhs: WidgetReminderEvent) -> Bool {
        if lhs.fireDate != rhs.fireDate {
            return lhs.fireDate < rhs.fireDate
        }
        return lhs.reminderID.uuidString.lowercased() < rhs.reminderID.uuidString.lowercased()
    }
}

private struct EventKey: Hashable {
    let reminderID: UUID
    let fireDate: Date
}
