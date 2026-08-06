import Foundation
import NotificationManagerDomain

public struct NotificationTextInput: Sendable, Equatable {
    public let title: String
    public let notes: String?
    public let schedule: ScheduleDefinition
    public let payload: LogicalNotificationPayload

    public init(
        title: String,
        notes: String?,
        schedule: ScheduleDefinition,
        payload: LogicalNotificationPayload
    ) {
        self.title = title
        self.notes = notes
        self.schedule = schedule
        self.payload = payload
    }
}

public struct NotificationText: Sendable, Equatable {
    public let title: String
    public let body: String
    public let ellipsis: String

    public init(title: String, body: String, ellipsis: String) {
        self.title = title
        self.body = body
        self.ellipsis = ellipsis
    }
}

public protocol LocalizedNotificationTextFormatting: Sendable {
    func content(for input: NotificationTextInput, locale: Locale) -> NotificationText
}
