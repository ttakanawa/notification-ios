import Foundation

public struct ReminderSnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
    public let notes: String?
    public let urlString: String?
    public let enabled: Bool
    public let schedule: ScheduleReadState
    public let tagIDs: Set<UUID>
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        title: String,
        notes: String?,
        urlString: String?,
        enabled: Bool,
        schedule: ScheduleReadState,
        tagIDs: Set<UUID>,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.urlString = urlString
        self.enabled = enabled
        self.schedule = schedule
        self.tagIDs = tagIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
