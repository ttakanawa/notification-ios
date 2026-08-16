import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import Observation
import Testing

@testable import NotificationManager

@MainActor
struct ReminderFormConfirmationCoordinatorTests {
    @Test func directExpiredSavePresentsAlertAndConfirmationClosesRoute() async {
        let id = reminderID
        let recorder = CoordinatorSaveActionRecorder(outcomes: [
            .requiresExpiredScheduleConfirmation(expiredWarning(id: id)),
            .saved(id)
        ])
        let (model, router) = makeExistingScenario(
            save: { draft, capacityConsent, expiredConsent in
                try await recorder.save(
                    draft: draft,
                    capacityConsent: capacityConsent,
                    expiredConsent: expiredConsent
                )
            }
        )
        model.title = "Changed title"
        let coordinator = ReminderFormConfirmationCoordinator()

        coordinator.save(model: model, router: router)
        await waitUntilSettled(coordinator)

        #expect(coordinator.alertKind == .expiredSchedule)
        #expect(router.compactPath == [.reminderEdit(id)])

        coordinator.confirmAlert()
        coordinator.dismissAlertFromSystem()
        await waitUntilSettled(coordinator)

        #expect(router.compactPath.isEmpty)
        #expect(router.selectedReminderID == nil)
        #expect(router.formModel(for: id) == nil)
        #expect(
            await recorder.recordedConsents() == [
                CoordinatorSaveConsent(.notProvided, .notProvided),
                CoordinatorSaveConsent(.notProvided, .acknowledged)
            ])
    }

    @Test func capacityConfirmationWaitsForSheetDismissalThenPresentsExpiredAlert() async {
        let id = reminderID
        let recorder = CoordinatorSaveActionRecorder(outcomes: [
            .requiresCapacityConfirmation(capacityWarning(id: id)),
            .requiresExpiredScheduleConfirmation(expiredWarning(id: id)),
            .saved(id)
        ])
        let (model, router) = makeExistingScenario(
            save: { draft, capacityConsent, expiredConsent in
                try await recorder.save(
                    draft: draft,
                    capacityConsent: capacityConsent,
                    expiredConsent: expiredConsent
                )
            }
        )
        model.title = "Changed title"
        let coordinator = ReminderFormConfirmationCoordinator()

        coordinator.save(model: model, router: router)
        await waitUntilSettled(coordinator)
        #expect(coordinator.capacityWarning == capacityWarning(id: id))

        model.urlString = model.urlString
        model.enabled = model.enabled
        model.tagIDs = model.tagIDs
        model.sourceDate = model.sourceDate
        model.sourceTime = model.sourceTime
        model.timeZoneIdentifier = model.timeZoneIdentifier
        model.repeatRule = model.repeatRule
        model.repeatEnd = model.repeatEnd
        model.earlyReminder = model.earlyReminder
        coordinator.confirmCapacity()
        coordinator.dismissCapacityFromSystem()

        #expect(coordinator.capacityWarning == nil)
        #expect(coordinator.isPersistenceOperationInFlight)
        #expect(
            await recorder.recordedConsents() == [
                CoordinatorSaveConsent(.notProvided, .notProvided)
            ])

        coordinator.capacitySheetDidDismiss()
        await waitUntilSettled(coordinator)

        #expect(coordinator.alertKind == .expiredSchedule)
        #expect(
            await recorder.recordedConsents() == [
                CoordinatorSaveConsent(.notProvided, .notProvided),
                CoordinatorSaveConsent(.acknowledged, .notProvided)
            ])

        model.notes = model.notes
        coordinator.confirmAlert()
        await waitUntilSettled(coordinator)

        #expect(router.compactPath.isEmpty)
        #expect(
            await recorder.recordedConsents() == [
                CoordinatorSaveConsent(.notProvided, .notProvided),
                CoordinatorSaveConsent(.acknowledged, .notProvided),
                CoordinatorSaveConsent(.acknowledged, .acknowledged)
            ])
    }

    @Test func deleteConfirmationClosesRouteAfterSuccessfulDeletion() async {
        let recorder = CoordinatorDeleteActionRecorder()
        let (model, router) = makeExistingScenario(
            delete: { id in await recorder.delete(id) }
        )
        let coordinator = ReminderFormConfirmationCoordinator()

        coordinator.requestDelete(model: model, router: router)
        #expect(coordinator.alertKind == .delete)

        coordinator.confirmAlert()
        coordinator.dismissAlertFromSystem()
        await waitUntilSettled(coordinator)

        #expect(await recorder.deletedIDs() == [reminderID])
        #expect(router.compactPath.isEmpty)
        #expect(router.formModel(for: reminderID) == nil)
    }

    @Test func failedDeletionLeavesRouteAndFormSessionOpen() async {
        let (model, router) = makeExistingScenario(
            delete: { _ in throw CoordinatorProbeError.failed }
        )
        let coordinator = ReminderFormConfirmationCoordinator()

        coordinator.requestDelete(model: model, router: router)
        coordinator.confirmAlert()
        await waitUntilSettled(coordinator)

        #expect(model.saveState == .failed(.delete))
        #expect(router.compactPath == [.reminderEdit(reminderID)])
        #expect(router.formModel(for: reminderID) === model)
        #expect(coordinator.alertKind == nil)
    }

    @Test func failedInitialSaveReleasesGateAndRetainsRouteAndFormSession() async {
        let (model, router) = makeExistingScenario(
            save: { _, _, _ in throw CoordinatorProbeError.failed }
        )
        model.title = "Changed title"
        let coordinator = ReminderFormConfirmationCoordinator()

        coordinator.save(model: model, router: router)
        await waitUntilSettled(coordinator)

        #expect(model.saveState == .failed(.save))
        #expect(router.compactPath == [.reminderEdit(reminderID)])
        #expect(router.formModel(for: reminderID) === model)
        #expect(coordinator.alertKind == nil)
        #expect(coordinator.capacityWarning == nil)
        #expect(!coordinator.isPersistenceOperationInFlight)
    }

    @Test func failedCapacityConfirmedSaveReleasesGateAndRetainsRouteAndFormSession() async {
        let recorder = CoordinatorSaveActionRecorder(outcomes: [
            .requiresCapacityConfirmation(capacityWarning(id: reminderID))
        ])
        let (model, router) = makeExistingScenario(
            save: { draft, capacityConsent, expiredConsent in
                try await recorder.save(
                    draft: draft,
                    capacityConsent: capacityConsent,
                    expiredConsent: expiredConsent
                )
            }
        )
        model.title = "Changed title"
        let coordinator = ReminderFormConfirmationCoordinator()
        coordinator.save(model: model, router: router)
        await waitUntilSettled(coordinator)

        coordinator.confirmCapacity()
        coordinator.capacitySheetDidDismiss()
        await waitUntilSettled(coordinator)

        #expect(model.saveState == .failed(.save))
        #expect(router.compactPath == [.reminderEdit(reminderID)])
        #expect(router.formModel(for: reminderID) === model)
        #expect(coordinator.alertKind == nil)
        #expect(coordinator.capacityWarning == nil)
        #expect(!coordinator.isPersistenceOperationInFlight)
    }

    @Test func failedExpiredConfirmedSaveReleasesGateAndRetainsRouteAndFormSession() async {
        let recorder = CoordinatorSaveActionRecorder(outcomes: [
            .requiresExpiredScheduleConfirmation(expiredWarning(id: reminderID))
        ])
        let (model, router) = makeExistingScenario(
            save: { draft, capacityConsent, expiredConsent in
                try await recorder.save(
                    draft: draft,
                    capacityConsent: capacityConsent,
                    expiredConsent: expiredConsent
                )
            }
        )
        model.title = "Changed title"
        let coordinator = ReminderFormConfirmationCoordinator()
        coordinator.save(model: model, router: router)
        await waitUntilSettled(coordinator)

        coordinator.confirmAlert()
        await waitUntilSettled(coordinator)

        #expect(model.saveState == .failed(.save))
        #expect(router.compactPath == [.reminderEdit(reminderID)])
        #expect(router.formModel(for: reminderID) === model)
        #expect(coordinator.alertKind == nil)
        #expect(coordinator.capacityWarning == nil)
        #expect(!coordinator.isPersistenceOperationInFlight)
    }

    @Test func successfulSaveReleasesRetainedModelAndRouterContexts() async throws {
        var (model, router): (ReminderFormModel?, AppRouter?) = makeExistingScenario()
        weak let retainedModel = model
        weak let retainedRouter = router
        model?.title = "Changed title"
        let coordinator = ReminderFormConfirmationCoordinator()

        coordinator.save(model: try #require(model), router: try #require(router))
        await waitUntilSettled(coordinator)
        model = nil
        router = nil

        #expect(retainedModel == nil)
        #expect(retainedRouter == nil)
    }

    @Test func failedSaveReleasesRetainedModelAndRouterContexts() async throws {
        var (model, router): (ReminderFormModel?, AppRouter?) = makeExistingScenario(
            save: { _, _, _ in throw CoordinatorProbeError.failed }
        )
        weak let retainedModel = model
        weak let retainedRouter = router
        model?.title = "Changed title"
        let coordinator = ReminderFormConfirmationCoordinator()

        coordinator.save(model: try #require(model), router: try #require(router))
        await waitUntilSettled(coordinator)
        model = nil
        router = nil

        #expect(retainedModel == nil)
        #expect(retainedRouter == nil)
    }

    @Test func alertCancellationReleasesRetainedModelAndRouterContexts() async throws {
        let warning = expiredWarning(id: reminderID)
        var (model, router): (ReminderFormModel?, AppRouter?) = makeExistingScenario(
            save: { _, _, _ in .requiresExpiredScheduleConfirmation(warning) }
        )
        weak let retainedModel = model
        weak let retainedRouter = router
        model?.title = "Changed title"
        let coordinator = ReminderFormConfirmationCoordinator()

        coordinator.save(model: try #require(model), router: try #require(router))
        await waitUntilSettled(coordinator)
        coordinator.cancelAlert()
        model = nil
        router = nil

        #expect(retainedModel == nil)
        #expect(retainedRouter == nil)
    }

    @Test func secondSaveIsRejectedWhileExpiredAlertIsPresented() async {
        let warning = expiredWarning(id: reminderID)
        let recorder = CoordinatorSaveActionRecorder(outcomes: [
            .requiresExpiredScheduleConfirmation(warning),
            .saved(reminderID)
        ])
        let (model, router) = makeExistingScenario(
            save: { draft, capacityConsent, expiredConsent in
                try await recorder.save(
                    draft: draft,
                    capacityConsent: capacityConsent,
                    expiredConsent: expiredConsent
                )
            }
        )
        model.title = "Changed title"
        let coordinator = ReminderFormConfirmationCoordinator()
        coordinator.save(model: model, router: router)
        await waitUntilSettled(coordinator)

        coordinator.save(model: model, router: router)
        await waitUntilSettled(coordinator)

        #expect(await recorder.recordedConsents().count == 1)
        #expect(coordinator.alertKind == .expiredSchedule)
        #expect(router.compactPath == [.reminderEdit(reminderID)])
        #expect(router.formModel(for: reminderID) === model)
    }

    @Test func secondSaveIsRejectedWhileCapacitySheetIsPresented() async {
        let warning = capacityWarning(id: reminderID)
        let recorder = CoordinatorSaveActionRecorder(outcomes: [
            .requiresCapacityConfirmation(warning),
            .saved(reminderID)
        ])
        let (model, router) = makeExistingScenario(
            save: { draft, capacityConsent, expiredConsent in
                try await recorder.save(
                    draft: draft,
                    capacityConsent: capacityConsent,
                    expiredConsent: expiredConsent
                )
            }
        )
        model.title = "Changed title"
        let coordinator = ReminderFormConfirmationCoordinator()
        coordinator.save(model: model, router: router)
        await waitUntilSettled(coordinator)

        coordinator.save(model: model, router: router)
        await waitUntilSettled(coordinator)

        #expect(await recorder.recordedConsents().count == 1)
        #expect(coordinator.capacityWarning == warning)
        #expect(router.compactPath == [.reminderEdit(reminderID)])
        #expect(router.formModel(for: reminderID) === model)
    }

    @Test func saveIsRejectedWhileDeleteAlertIsPresented() async {
        let recorder = CoordinatorSaveActionRecorder(outcomes: [.saved(reminderID)])
        let (model, router) = makeExistingScenario(
            save: { draft, capacityConsent, expiredConsent in
                try await recorder.save(
                    draft: draft,
                    capacityConsent: capacityConsent,
                    expiredConsent: expiredConsent
                )
            }
        )
        let coordinator = ReminderFormConfirmationCoordinator()
        coordinator.requestDelete(model: model, router: router)

        coordinator.save(model: model, router: router)
        await waitUntilSettled(coordinator)

        #expect(await recorder.recordedConsents().isEmpty)
        #expect(coordinator.alertKind == .delete)
        #expect(router.compactPath == [.reminderEdit(reminderID)])
        #expect(router.formModel(for: reminderID) === model)
    }

    @Test func saveIsRejectedWhileDiscardAlertIsPresented() async {
        let recorder = CoordinatorSaveActionRecorder(outcomes: [.saved(reminderID)])
        let (model, router) = makeExistingScenario(
            save: { draft, capacityConsent, expiredConsent in
                try await recorder.save(
                    draft: draft,
                    capacityConsent: capacityConsent,
                    expiredConsent: expiredConsent
                )
            }
        )
        model.title = "Changed title"
        let coordinator = ReminderFormConfirmationCoordinator()
        coordinator.requestDiscard(model: model, router: router)

        coordinator.save(model: model, router: router)
        await waitUntilSettled(coordinator)

        #expect(await recorder.recordedConsents().isEmpty)
        #expect(coordinator.alertKind == .discardChanges)
        #expect(model.title == "Changed title")
        #expect(router.compactPath == [.reminderEdit(reminderID)])
        #expect(router.formModel(for: reminderID) === model)
    }

    @Test func cancellingDiscardPreservesChangesAndRoute() {
        let (model, router) = makeExistingScenario()
        model.title = "Changed title"
        let coordinator = ReminderFormConfirmationCoordinator()

        coordinator.requestDiscard(model: model, router: router)
        #expect(coordinator.alertKind == .discardChanges)

        coordinator.cancelAlert()
        coordinator.dismissAlertFromSystem()

        #expect(model.title == "Changed title")
        #expect(model.hasChanges)
        #expect(router.compactPath == [.reminderEdit(reminderID)])
        #expect(coordinator.alertKind == nil)
    }

    @Test func confirmingDiscardRestoresBaselineBeforeClosingRoute() {
        let (model, router) = makeExistingScenario()
        model.title = "Changed title"
        let coordinator = ReminderFormConfirmationCoordinator()

        coordinator.requestDiscard(model: model, router: router)
        coordinator.confirmAlert()

        #expect(model.title == "Original title")
        #expect(!model.hasChanges)
        #expect(router.compactPath.isEmpty)
        #expect(router.formModel(for: reminderID) === model)
        #expect(coordinator.alertKind == nil)
    }

    @Test func requestingDiscardOnCleanFormClosesRouteWithoutAnAlert() {
        let (model, router) = makeExistingScenario()
        let coordinator = ReminderFormConfirmationCoordinator()

        coordinator.requestDiscard(model: model, router: router)

        #expect(coordinator.alertKind == nil)
        #expect(router.compactPath.isEmpty)
        #expect(router.formModel(for: reminderID) === model)
    }

    @Test(arguments: CoordinatorCancellationTrigger.allCases)
    func cancellingExpiredConfirmationClearsTheModelState(
        trigger: CoordinatorCancellationTrigger
    ) async {
        let warning = expiredWarning(id: reminderID)
        let (model, router) = makeExistingScenario(
            save: { _, _, _ in .requiresExpiredScheduleConfirmation(warning) }
        )
        model.title = "Changed title"
        let coordinator = ReminderFormConfirmationCoordinator()
        coordinator.save(model: model, router: router)
        await waitUntilSettled(coordinator)

        switch trigger {
        case .explicit:
            coordinator.cancelAlert()
        case .system:
            coordinator.dismissAlertFromSystem()
        }

        #expect(model.saveState == .idle)
        #expect(coordinator.alertKind == nil)
        #expect(router.compactPath == [.reminderEdit(reminderID)])
    }

    @Test(arguments: CoordinatorCancellationTrigger.allCases)
    func cancellingDeleteConfirmationClearsTheModelRequest(
        trigger: CoordinatorCancellationTrigger
    ) {
        let (model, router) = makeExistingScenario()
        let coordinator = ReminderFormConfirmationCoordinator()
        coordinator.requestDelete(model: model, router: router)

        switch trigger {
        case .explicit:
            coordinator.cancelAlert()
        case .system:
            coordinator.dismissAlertFromSystem()
        }

        #expect(!model.isDeleteConfirmationPresented)
        #expect(coordinator.alertKind == nil)
        #expect(router.compactPath == [.reminderEdit(reminderID)])
    }

    @Test(arguments: CoordinatorCancellationTrigger.allCases)
    func cancellingCapacityConfirmationClearsTheModelState(
        trigger: CoordinatorCancellationTrigger
    ) async {
        let warning = capacityWarning(id: reminderID)
        let (model, router) = makeExistingScenario(
            save: { _, _, _ in .requiresCapacityConfirmation(warning) }
        )
        model.title = "Changed title"
        let coordinator = ReminderFormConfirmationCoordinator()
        coordinator.save(model: model, router: router)
        await waitUntilSettled(coordinator)

        switch trigger {
        case .explicit:
            coordinator.cancelCapacity()
        case .system:
            coordinator.dismissCapacityFromSystem()
        }

        #expect(model.saveState == .idle)
        #expect(coordinator.capacityWarning == nil)
        #expect(router.compactPath == [.reminderEdit(reminderID)])
    }

    @Test func secondRequestIsRejectedWhileSynchronousGateIsHeld() async {
        let saveAction = CoordinatorSuspendedSaveAction()
        let (model, router) = makeExistingScenario(
            save: { draft, _, _ in await saveAction.save(draft) }
        )
        model.title = "Changed title"
        let coordinator = ReminderFormConfirmationCoordinator()

        coordinator.save(model: model, router: router)
        coordinator.requestDiscard(model: model, router: router)

        #expect(coordinator.isPersistenceOperationInFlight)
        #expect(coordinator.alertKind == nil)
        #expect(model.title == "Changed title")
        #expect(router.compactPath == [.reminderEdit(reminderID)])

        await saveAction.waitUntilCalled()
        await saveAction.resolve(.saved(reminderID))
        await waitUntilSettled(coordinator)

        #expect(router.compactPath.isEmpty)
    }

    private var reminderID: UUID {
        UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    }

    private func makeExistingScenario(
        save:
            @escaping @Sendable (
                ReminderDraft,
                CapacityConsent,
                ExpiredScheduleConsent
            ) async throws -> SaveReminderOutcome = { draft, _, _ in .saved(draft.id) },
        delete: @escaping @Sendable (UUID) async throws -> Void = { _ in }
    ) -> (ReminderFormModel, AppRouter) {
        let router = AppRouter(
            actions: ReminderActionCoordinator(
                handlers: ReminderActionHandlers(
                    setEnabled: { command in .saved(command.reminderID) },
                    delete: { _ in }
                )
            ))
        let schedule = ScheduleDefinition(
            source: SourceWallClock(
                year: 2040,
                month: 8,
                day: 31,
                hour: 9,
                minute: 30,
                timeZoneIdentifier: "America/New_York"
            ),
            rule: .daily(interval: 1),
            end: .never,
            early: nil
        )
        let model = ReminderFormModel(
            snapshot: ReminderSnapshot(
                id: reminderID,
                title: "Original title",
                notes: nil,
                urlString: nil,
                enabled: true,
                schedule: .valid(schedule, sourceVersion: 1, originalData: Data([1])),
                tagIDs: [],
                createdAt: date("2040-01-01T00:00:00Z"),
                updatedAt: date("2040-08-01T00:00:00Z")
            ),
            savedRepeatPresentation: .standard(localizedSummary: "Every day"),
            now: date("2040-08-01T00:00:00Z"),
            actions: ReminderFormActions(save: save, delete: delete)
        )
        router.register(form: model)
        router.showReminder(reminderID)
        return (model, router)
    }

    private func capacityWarning(id: UUID) -> CapacityWarning {
        CapacityWarning(
            reminderID: id,
            earliestGroupID: AlertGroupID(
                reminderID: id,
                baseOccurrenceInstant: date("2040-08-31T13:30:00Z")
            ),
            planningCapacity: 60
        )
    }

    private func expiredWarning(id: UUID) -> ExpiredScheduleWarning {
        ExpiredScheduleWarning(
            reminderID: id,
            evaluationNow: date("2040-08-31T13:30:00Z")
        )
    }

    private func waitUntilSettled(
        _ coordinator: ReminderFormConfirmationCoordinator
    ) async {
        guard coordinator.isPersistenceOperationInFlight else { return }
        await withCheckedContinuation { continuation in
            observeUntilSettled(coordinator, continuation: continuation)
        }
    }

    private func observeUntilSettled(
        _ coordinator: ReminderFormConfirmationCoordinator,
        continuation: CheckedContinuation<Void, Never>
    ) {
        guard coordinator.isPersistenceOperationInFlight else {
            continuation.resume()
            return
        }
        withObservationTracking {
            _ = coordinator.isPersistenceOperationInFlight
        } onChange: {
            Task { @MainActor in
                observeUntilSettled(coordinator, continuation: continuation)
            }
        }
    }

    private func date(_ value: String) -> Date {
        guard let date = ISO8601DateFormatter().date(from: value) else {
            preconditionFailure("Invalid ISO-8601 test fixture: \(value)")
        }
        return date
    }
}

private struct CoordinatorSaveConsent: Sendable, Equatable {
    let capacity: CapacityConsent
    let expired: ExpiredScheduleConsent

    init(_ capacity: CapacityConsent, _ expired: ExpiredScheduleConsent) {
        self.capacity = capacity
        self.expired = expired
    }
}

private actor CoordinatorSaveActionRecorder {
    private var outcomes: [SaveReminderOutcome]
    private var consents: [CoordinatorSaveConsent] = []

    init(outcomes: [SaveReminderOutcome]) {
        self.outcomes = outcomes
    }

    func save(
        draft: ReminderDraft,
        capacityConsent: CapacityConsent,
        expiredConsent: ExpiredScheduleConsent
    ) throws -> SaveReminderOutcome {
        consents.append(CoordinatorSaveConsent(capacityConsent, expiredConsent))
        guard !outcomes.isEmpty else { throw CoordinatorProbeError.failed }
        return outcomes.removeFirst()
    }

    func recordedConsents() -> [CoordinatorSaveConsent] {
        consents
    }
}

private actor CoordinatorDeleteActionRecorder {
    private var ids: [UUID] = []

    func delete(_ id: UUID) {
        ids.append(id)
    }

    func deletedIDs() -> [UUID] {
        ids
    }
}

private actor CoordinatorSuspendedSaveAction {
    private var resultContinuation: CheckedContinuation<SaveReminderOutcome, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func save(_ draft: ReminderDraft) async -> SaveReminderOutcome {
        let pendingWaiters = waiters
        waiters.removeAll()
        for waiter in pendingWaiters {
            waiter.resume()
        }
        return await withCheckedContinuation { resultContinuation = $0 }
    }

    func waitUntilCalled() async {
        guard resultContinuation == nil else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func resolve(_ outcome: SaveReminderOutcome) {
        resultContinuation?.resume(returning: outcome)
        resultContinuation = nil
    }
}

private enum CoordinatorProbeError: Error {
    case failed
}

enum CoordinatorCancellationTrigger: Sendable, CaseIterable {
    case explicit
    case system
}
