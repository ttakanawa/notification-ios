import Foundation
import NotificationManagerDomain

/// A save/export event is not a receipt. Implementations must compare the exact current
/// snapshot and its durable revision, scoped to the checked CloudKit account.
public protocol ReminderCloudCommitChecking: Sendable {
    func canPublish(_ snapshot: ReminderSnapshot) async -> Bool
    func changes() async -> AsyncStream<Void>
}

public protocol DisplayCustomizationRepository: Sendable {
    func globalDisplayCustomizationData() async throws -> Data?
    func saveGlobalDisplayCustomizationData(_ data: Data?) async throws
    func saveDisplayCustomizationData(_ data: Data?, reminderID: UUID) async throws
        -> ReminderSnapshot
}
