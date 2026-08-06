import Foundation

public struct DeleteReminderUseCase: Sendable {
    private let repository: any ReminderRepository
    private let notificationCleanup: any NotificationCleanup
    private let reconcileRequester: any ReconcileRequesting

    public init(
        repository: any ReminderRepository,
        notificationCleanup: any NotificationCleanup,
        reconcileRequester: any ReconcileRequesting
    ) {
        self.repository = repository
        self.notificationCleanup = notificationCleanup
        self.reconcileRequester = reconcileRequester
    }

    public func execute(reminderID: UUID) async throws {
        try await repository.delete(id: reminderID)
        await notificationCleanup.removeNotifications(for: reminderID)
        await reconcileRequester.requestReconcile(.reminderDeleted(reminderID))
    }
}
