import Foundation
import NotificationManagerDomain
import NotificationManagerWidgetSupport

struct ReminderLiveActivityProjector: Sendable {
    func nextRangeEnd(
        reminders: [ReminderSnapshot],
        after now: Date,
        environment: any RecurrenceEnvironment = FoundationRecurrenceEnvironment()
    ) throws -> Date? {
        guard now.timeIntervalSinceReferenceDate.isFinite else { return nil }
        var nextEnd: Date?
        for reminder in reminders where reminder.enabled {
            guard case .valid(let schedule, _, _) = reminder.schedule,
                let duration = schedule.durationSeconds,
                ReminderAggregateValidator().scheduleIssues(for: schedule).isEmpty
            else { continue }
            let anchor = try SourceWallClockResolver().resolve(
                schedule.source, environment: environment)
            let lowerBound = max(anchor, now.addingTimeInterval(-Double(duration)))
            let upperBound = Date(
                timeIntervalSinceReferenceDate: now.timeIntervalSinceReferenceDate.nextUp)
            guard lowerBound < upperBound else { continue }
            let occurrences = try FoundationRecurrenceEngine().baseOccurrences(
                for: schedule, in: lowerBound..<upperBound, environment: environment)
            for occurrence in occurrences {
                let end = occurrence.instant.addingTimeInterval(Double(duration))
                guard end > now else { continue }
                nextEnd = nextEnd.map { min($0, end) } ?? end
                break
            }
        }
        return nextEnd
    }

    /// A bounded queue is replenished whenever the app receives execution time.
    func project(
        reminders: [ReminderSnapshot],
        notificationsEnabled: Bool,
        now: Date,
        environment: any RecurrenceEnvironment = FoundationRecurrenceEnvironment()
    ) throws -> [ReminderLiveActivityEvent] {
        guard notificationsEnabled, now.timeIntervalSince1970.isFinite else { return [] }
        var events: [ReminderLiveActivityEvent] = []
        for reminder in reminders where reminder.enabled {
            guard case .valid(let schedule, _, _) = reminder.schedule,
                let duration = schedule.durationSeconds,
                ReminderAggregateValidator().scheduleIssues(for: schedule).isEmpty,
                let timeZone = environment.timeZone(identifier: schedule.source.timeZoneIdentifier)
            else { continue }
            let calendar = environment.gregorianCalendar(in: timeZone)
            guard
                let upperBound = calendar.date(from: DateComponents(year: 10_000, month: 1, day: 1))
            else { continue }
            let lowerBound = now.addingTimeInterval(
                -ReminderLiveActivityEvent.maximumActivityDuration)
            guard lowerBound < upperBound else { continue }
            let occurrences = try FoundationRecurrenceEngine().baseOccurrences(
                for: schedule,
                in: lowerBound..<upperBound,
                environment: environment
            )
            var count = 0
            for occurrence in occurrences {
                let event = ReminderLiveActivityEvent(
                    reminderID: reminder.id,
                    title: reminder.title,
                    startDate: occurrence.instant,
                    endDate: occurrence.instant.addingTimeInterval(TimeInterval(duration))
                )
                guard event.isValid, event.activityEndDate > now else { continue }
                events.append(event)
                count += 1
                if count == ReminderLiveActivitySelection.maximumActivities { break }
            }
        }
        return events.sorted {
            if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
            return $0.id < $1.id
        }
    }
}
