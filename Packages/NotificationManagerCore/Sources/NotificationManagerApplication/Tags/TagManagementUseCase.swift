import Foundation
import NotificationManagerDomain

public struct TagManagementUseCase: Sendable {
    private let repository: any ReminderRepository
    private let normalizer: any TagNameNormalizing
    private let now: @Sendable () -> Date

    public init(
        repository: any ReminderRepository,
        normalizer: any TagNameNormalizing,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.normalizer = normalizer
        self.now = now
    }

    public func create(name: String, id: UUID = UUID()) async throws -> TagSnapshot {
        let displayName = TagNameNormalizerV1.trimmedDisplayName(name)
        let normalizedName = try normalizer.normalize(name)
        let timestamp = Self.integralSecond(now())
        return try await repository.saveTag(
            EncodedTagMutation(
                id: id,
                name: displayName,
                normalizedName: normalizedName,
                normalizationVersion: TagLimits.normalizationVersion,
                createdAt: timestamp,
                updatedAt: timestamp,
                command: .create
            ))
    }

    public func rename(tagID: UUID, name: String) async throws -> TagSnapshot {
        let displayName = TagNameNormalizerV1.trimmedDisplayName(name)
        let normalizedName = try normalizer.normalize(name)
        let snapshot = try await repository.fetchCompleteSnapshot()
        guard let current = snapshot.tags.first(where: { $0.id == tagID }) else {
            throw TagRepositoryError.notFound(tagID)
        }
        return try await repository.saveTag(
            EncodedTagMutation(
                id: current.id,
                name: displayName,
                normalizedName: normalizedName,
                normalizationVersion: TagLimits.normalizationVersion,
                createdAt: current.createdAt,
                updatedAt: Self.integralSecond(now()),
                command: .update
            ))
    }

    public func delete(tagID: UUID) async throws {
        try await repository.deleteTag(id: tagID)
    }

    private static func integralSecond(_ date: Date) -> Date {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite else { return date }
        return Date(timeIntervalSince1970: seconds.rounded(.down))
    }
}
