import Foundation

#if canImport(SwiftUI)
    import SwiftUI
#endif

public struct ReminderLiveActivityEvent: Sendable, Equatable, Identifiable {
    public static let maximumActivityDuration: TimeInterval = 8 * 60 * 60

    public let reminderID: UUID
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let notificationDate: Date

    public init(
        reminderID: UUID, title: String, startDate: Date, endDate: Date,
        notificationDate: Date? = nil
    ) {
        self.reminderID = reminderID
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.notificationDate = notificationDate ?? startDate
    }

    public var id: String {
        "\(reminderID.uuidString.lowercased())/\(notificationDate.timeIntervalSince1970)"
    }

    public var activityEndDate: Date {
        min(endDate, startDate.addingTimeInterval(Self.maximumActivityDuration))
    }

    public var isValid: Bool {
        startDate.timeIntervalSince1970.isFinite
            && endDate.timeIntervalSince1970.isFinite
            && notificationDate.timeIntervalSince1970.isFinite
            && endDate > startDate
            && notificationDate >= startDate && notificationDate <= endDate
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

#if canImport(SwiftUI)
    /// Timing inputs for system-rendered Live Activity text.
    public enum ReminderLiveActivityTimePresentation {
        public static func countdown(
            startDate: Date, notificationDate: Date
        ) -> SystemFormatStyle.Timer {
            .init(
                countingDownIn: startDate..<notificationDate, showsHours: false,
                maxFieldCount: 2, maxPrecision: .seconds(1))
        }

        public static func elapsedInterval(
            since notificationDate: Date
        ) -> ClosedRange<Date> {
            // Keep counting if the app cannot execute its scheduled cleanup. This
            // finite span covers ActivityKit's 8h activity + 4h Lock Screen lifetime,
            // even for an activity recovered late within its 8h display window.
            // The service still removes the activity at its configured activityEndDate.
            notificationDate...notificationDate.addingTimeInterval(24 * 60 * 60)
        }
    }
#endif

public enum ReminderLiveActivitySelection {
    /// Scheduled activities share the system's activity limit with active ones.
    public static let maximumActivities = 3

    public static func select(
        events: [ReminderLiveActivityEvent],
        at date: Date,
        supportsScheduling: Bool,
        suppressedIDs: Set<String> = [],
        limit: Int = maximumActivities
    ) -> [ReminderLiveActivityEvent] {
        guard date.timeIntervalSince1970.isFinite, limit > 0 else { return [] }
        var seen: Set<String> = []
        return events.filter { event in
            event.isValid && event.activityEndDate > date
                && (supportsScheduling || event.startDate <= date)
                && !suppressedIDs.contains(event.id)
        }
        .sorted {
            if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
            return $0.id < $1.id
        }
        .filter { seen.insert($0.id).inserted }
        .prefix(limit)
        .map { $0 }
    }
}
