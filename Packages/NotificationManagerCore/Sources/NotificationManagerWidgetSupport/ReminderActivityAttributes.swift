#if canImport(ActivityKit) && os(iOS)
    import ActivityKit
    import Foundation

    public struct ReminderActivityAttributes: ActivityAttributes, Sendable {
        public struct ContentState: Codable, Hashable, Sendable {
            public let title: String
            public let startDate: Date
            public let endDate: Date
            public let activityEndDate: Date

            public init(event: ReminderLiveActivityEvent) {
                title = event.title
                startDate = event.startDate
                endDate = event.endDate
                activityEndDate = event.activityEndDate
            }
        }

        public let reminderID: UUID
        public let eventID: String

        public init(event: ReminderLiveActivityEvent) {
            reminderID = event.reminderID
            eventID = event.id
        }
    }
#endif
