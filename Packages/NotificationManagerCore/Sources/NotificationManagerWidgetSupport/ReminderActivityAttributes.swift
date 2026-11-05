#if canImport(ActivityKit) && os(iOS)
    import ActivityKit
    import Foundation

    public struct ReminderActivityAttributes: ActivityAttributes, Sendable {
        public struct ContentState: Codable, Hashable, Sendable {
            public static let currentDisplayVersion = 8
            public let title: String
            public let startDate: Date
            public let endDate: Date
            public let activityEndDate: Date
            public let notificationDate: Date
            public let displayVersion: Int
            public let notificationHasOccurred: Bool

            public init(event: ReminderLiveActivityEvent, notificationHasOccurred: Bool = false) {
                title = event.title
                startDate = event.startDate
                endDate = event.endDate
                activityEndDate = event.activityEndDate
                notificationDate = event.notificationDate
                displayVersion = Self.currentDisplayVersion
                self.notificationHasOccurred = notificationHasOccurred
            }

            public init(from decoder: any Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                title = try values.decode(String.self, forKey: .title)
                startDate = try values.decode(Date.self, forKey: .startDate)
                endDate = try values.decode(Date.self, forKey: .endDate)
                activityEndDate = try values.decode(Date.self, forKey: .activityEndDate)
                notificationDate =
                    try values.decodeIfPresent(Date.self, forKey: .notificationDate) ?? startDate
                displayVersion = try values.decodeIfPresent(Int.self, forKey: .displayVersion) ?? 1
                notificationHasOccurred =
                    try values.decodeIfPresent(Bool.self, forKey: .notificationHasOccurred) ?? false
            }

            private enum CodingKeys: String, CodingKey {
                case title, startDate, endDate, activityEndDate, notificationDate, displayVersion
                case notificationHasOccurred
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
