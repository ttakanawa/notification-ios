import Foundation
import NotificationManagerDomain

public struct EncodedReminderMutation: Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let notes: String?
    public let urlString: String?
    public let enabled: Bool
    public let scheduleData: Data
    public let tagIDs: Set<UUID>
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        title: String,
        notes: String?,
        urlString: String?,
        enabled: Bool,
        scheduleData: Data,
        tagIDs: Set<UUID>,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.urlString = urlString
        self.enabled = enabled
        self.scheduleData = scheduleData
        self.tagIDs = tagIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(_ aggregate: ValidatedReminderAggregate) {
        self.init(
            id: aggregate.id,
            title: aggregate.title,
            notes: aggregate.notes,
            urlString: aggregate.urlString,
            enabled: aggregate.enabled,
            scheduleData: aggregate.scheduleData,
            tagIDs: aggregate.tagIDs,
            createdAt: aggregate.createdAt,
            updatedAt: aggregate.updatedAt
        )
    }
}

public struct EncodedTagMutation: Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let normalizedName: String
    public let normalizationVersion: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        name: String,
        normalizedName: String,
        normalizationVersion: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.normalizedName = normalizedName
        self.normalizationVersion = normalizationVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public protocol ReminderRepository: Sendable {
    func fetchCompleteSnapshot() async throws -> CompleteReminderSnapshot
    func reminder(id: UUID) async throws -> ReminderSnapshot?
    func save(_ mutation: EncodedReminderMutation) async throws -> ReminderSnapshot
    func delete(id: UUID) async throws
    func saveTag(_ mutation: EncodedTagMutation) async throws -> TagSnapshot
    func deleteTag(id: UUID) async throws
}
