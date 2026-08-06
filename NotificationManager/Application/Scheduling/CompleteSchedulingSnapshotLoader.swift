import NotificationManagerApplication
import NotificationManagerDomain

public enum CompleteSchedulingSnapshotLoadError: Error, Sendable, Equatable {
    case fetch
    case relationshipTraversal
    case classification
}

public protocol CompleteSchedulingSnapshotLoading: Sendable {
    func loadCompleteSnapshot() async throws -> CompleteReminderSnapshot
}

public struct CompleteSchedulingSnapshotLoader: CompleteSchedulingSnapshotLoading {
    private let repository: any ReminderRepository

    public init(repository: any ReminderRepository) {
        self.repository = repository
    }

    public func loadCompleteSnapshot() async throws -> CompleteReminderSnapshot {
        let snapshot: CompleteReminderSnapshot
        do {
            snapshot = try await repository.fetchCompleteSnapshot()
        } catch {
            throw CompleteSchedulingSnapshotLoadError.fetch
        }

        guard Set(snapshot.reminders.map(\.id)).count == snapshot.reminders.count,
              Set(snapshot.tags.map(\.id)).count == snapshot.tags.count
        else {
            throw CompleteSchedulingSnapshotLoadError.classification
        }

        let tagIDs = Set(snapshot.tags.map(\.id))
        guard snapshot.reminders.allSatisfy({ $0.tagIDs.isSubset(of: tagIDs) }) else {
            throw CompleteSchedulingSnapshotLoadError.relationshipTraversal
        }
        return snapshot
    }
}
