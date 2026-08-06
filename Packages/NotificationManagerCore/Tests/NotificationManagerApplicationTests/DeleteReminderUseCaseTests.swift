import Foundation
import Testing
@testable import NotificationManagerApplication

@Suite("DeleteReminderUseCase")
struct DeleteReminderUseCaseTests {
    @Test func persistsBeforeBestEffortNotificationCleanupAndReconcile() async throws {
        let trace = LockedApplicationTrace()
        let repository = InMemoryReminderRepository(trace: trace)
        let cleanup = RecordingNotificationCleanup(trace: trace)
        let reconciler = RecordingReconcileRequester(trace: trace)
        let useCase = DeleteReminderUseCase(
            repository: repository,
            notificationCleanup: cleanup,
            reconcileRequester: reconciler
        )

        try await useCase.execute(reminderID: TestApplicationValues.reminderID)

        #expect(trace.events == [
            .repositoryDeleted,
            .notificationsCleaned,
            .reconcileRequested
        ])
        #expect(await cleanup.reminderIDs == [TestApplicationValues.reminderID])
        #expect(await reconciler.reasons == [.reminderDeleted(TestApplicationValues.reminderID)])
    }

    @Test func persistenceFailurePreventsCleanupAndReconcile() async throws {
        let trace = LockedApplicationTrace()
        let repository = InMemoryReminderRepository(deleteError: .delete, trace: trace)
        let cleanup = RecordingNotificationCleanup(trace: trace)
        let reconciler = RecordingReconcileRequester(trace: trace)
        let useCase = DeleteReminderUseCase(
            repository: repository,
            notificationCleanup: cleanup,
            reconcileRequester: reconciler
        )

        await #expect(throws: RepositoryTestError.delete) {
            try await useCase.execute(reminderID: TestApplicationValues.reminderID)
        }

        #expect(trace.events == [.repositoryDeleted])
        #expect(await cleanup.reminderIDs.isEmpty)
        #expect(await reconciler.reasons.isEmpty)
    }

    @Test func deleteDoesNotNeedToDecodeAnOpaqueSchedule() async throws {
        let repository = InMemoryReminderRepository()
        let cleanup = RecordingNotificationCleanup()
        let reconciler = RecordingReconcileRequester()
        let useCase = DeleteReminderUseCase(
            repository: repository,
            notificationCleanup: cleanup,
            reconcileRequester: reconciler
        )

        try await useCase.execute(reminderID: TestApplicationValues.reminderID)

        #expect(await cleanup.reminderIDs == [TestApplicationValues.reminderID])
    }

    @Test func dataUnavailableCleanupPortCanRemoveAllPendingWithoutARepository() async {
        let cleanup = RecordingNotificationCleanup()

        await cleanup.removeAllPendingAppNotifications()

        #expect(await cleanup.removeAllPendingCount == 1)
        #expect(await cleanup.reminderIDs.isEmpty)
    }
}

private actor RecordingNotificationCleanup: NotificationCleanup {
    private(set) var reminderIDs: [UUID] = []
    private(set) var removeAllPendingCount = 0
    private let trace: LockedApplicationTrace?

    init(trace: LockedApplicationTrace? = nil) {
        self.trace = trace
    }

    func removeNotifications(for reminderID: UUID) async {
        trace?.record(.notificationsCleaned)
        reminderIDs.append(reminderID)
    }

    func removeAllPendingAppNotifications() async {
        removeAllPendingCount += 1
    }
}
