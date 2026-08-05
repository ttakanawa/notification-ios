public struct CompleteReminderSnapshot: Sendable, Equatable {
    public let reminders: [ReminderSnapshot]
    public let tags: [TagSnapshot]

    public init(reminders: [ReminderSnapshot], tags: [TagSnapshot]) {
        self.reminders = reminders
        self.tags = tags
    }
}
