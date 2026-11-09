import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import Observation
import Testing

@testable import NotificationManager

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ReminderMutationCoordinationTests {
    @Test func formSaveIsRejectedUntilListToggleFinishes() async {
        let suspension = ReminderMutationSuspension()
        let recorder = ReminderMutationRecorder()
        let actions = ReminderActionCoordinator(
            handlers: ReminderActionHandlers(
                setEnabled: { command in
                    await suspension.suspend()
                    return .saved(command.reminderID)
                },
                delete: { _ in }
            ))
        let (model, router) = makeScenario(
            actions: actions,
            save: { draft, capacity, _ in
                await recorder.recordSave(capacity)
                return .saved(draft.id)
            }
        )
        let coordinator = ReminderFormConfirmationCoordinator()
        let toggle = Task {
            await actions.setEnabled(false, for: model.detachedDraft.id, fallback: true)
        }
        await suspension.waitUntilEntered()

        coordinator.save(model: model, router: router)

        #expect(!coordinator.isPersistenceOperationInFlight)
        #expect(model.saveState == .idle)
        #expect(await recorder.saveConsents.isEmpty)
        #expect(model.title == "Edited title")
        #expect(router.formModel(for: model.detachedDraft.id) === model)

        await suspension.release()
        #expect(await toggle.value)
        coordinator.save(model: model, router: router)
        await waitUntilSettled(coordinator)

        #expect(await recorder.saveConsents == [.notProvided])
        #expect(model.saveState == .saved(model.detachedDraft.id))
        #expect(!actions.isBusy)
    }

    @Test(arguments: [false, true])
    func formSaveBlocksListMutationsAndReleasesGateAfterSettling(fails: Bool) async {
        let suspension = ReminderMutationSuspension()
        let recorder = ReminderMutationRecorder()
        let actions = makeListActions(recorder: recorder)
        let (model, router) = makeScenario(
            actions: actions,
            save: { draft, _, _ in
                await suspension.suspend()
                if fails { throw ReminderMutationProbeError.failed }
                return .saved(draft.id)
            }
        )
        let coordinator = ReminderFormConfirmationCoordinator()

        coordinator.save(model: model, router: router)
        #expect(actions.isBusy)
        await suspension.waitUntilEntered()
        await expectListMutationsAreBlocked(actions, recorder: recorder)

        await suspension.release()
        await waitUntilSettled(coordinator)

        #expect(!actions.isBusy)
        #expect(
            model.saveState == (fails ? .failed(.save) : .saved(model.detachedDraft.id)))
        await expectListMutationsCanResume(actions, recorder: recorder)
    }

    @Test(arguments: [false, true])
    func formDeletionBlocksListMutationsAndReleasesGateAfterSettling(fails: Bool) async {
        let suspension = ReminderMutationSuspension()
        let recorder = ReminderMutationRecorder()
        let actions = makeListActions(recorder: recorder)
        let (model, router) = makeScenario(
            actions: actions,
            delete: { _ in
                await suspension.suspend()
                if fails { throw ReminderMutationProbeError.failed }
            }
        )
        let coordinator = ReminderFormConfirmationCoordinator()
        coordinator.requestDelete(model: model, router: router)

        coordinator.confirmAlert()
        #expect(actions.isBusy)
        await suspension.waitUntilEntered()
        await expectListMutationsAreBlocked(actions, recorder: recorder)

        await suspension.release()
        await waitUntilSettled(coordinator)

        #expect(!actions.isBusy)
        #expect(model.saveState == (fails ? .failed(.delete) : .deleted))
        await expectListMutationsCanResume(actions, recorder: recorder)
    }

    @Test func capacityConfirmationKeepsListLockedAcrossSheetDismissal() async {
        let suspension = ReminderMutationSuspension()
        let recorder = ReminderMutationRecorder()
        let actions = makeListActions(recorder: recorder)
        let warning = capacityWarning
        let (model, router) = makeScenario(
            actions: actions,
            save: { draft, capacity, _ in
                await recorder.recordSave(capacity)
                if capacity == .notProvided {
                    return .requiresCapacityConfirmation(warning)
                }
                await suspension.suspend()
                return .saved(draft.id)
            }
        )
        let coordinator = ReminderFormConfirmationCoordinator()
        coordinator.save(model: model, router: router)
        await waitUntilSettled(coordinator)
        #expect(coordinator.capacityWarning == warning)
        #expect(!actions.isBusy)

        coordinator.confirmCapacity()
        coordinator.dismissCapacityFromSystem()

        #expect(actions.isBusy)
        #expect(coordinator.isPersistenceOperationInFlight)
        #expect(coordinator.capacityWarning == nil)
        #expect(await recorder.saveConsents == [.notProvided])
        await expectListMutationsAreBlocked(actions, recorder: recorder)

        coordinator.capacitySheetDidDismiss()
        await suspension.waitUntilEntered()
        #expect(await recorder.saveConsents == [.notProvided, .acknowledged])
        await expectListMutationsAreBlocked(actions, recorder: recorder)

        await suspension.release()
        await waitUntilSettled(coordinator)

        #expect(model.saveState == .saved(model.detachedDraft.id))
        #expect(!actions.isBusy)
        await expectListMutationsCanResume(actions, recorder: recorder)
    }

    @Test func confirmedFormDeletionIsRejectedWhileListToggleRuns() async {
        let suspension = ReminderMutationSuspension()
        let recorder = ReminderMutationRecorder()
        let actions = ReminderActionCoordinator(
            handlers: ReminderActionHandlers(
                setEnabled: { command in
                    await suspension.suspend()
                    return .saved(command.reminderID)
                },
                delete: { _ in }
            ))
        let (model, router) = makeScenario(
            actions: actions,
            delete: { id in await recorder.recordDeletion(id) }
        )
        let coordinator = ReminderFormConfirmationCoordinator()
        coordinator.requestDelete(model: model, router: router)
        let toggle = Task {
            await actions.setEnabled(false, for: model.detachedDraft.id, fallback: true)
        }
        await suspension.waitUntilEntered()

        coordinator.confirmAlert()

        #expect(!coordinator.isPersistenceOperationInFlight)
        #expect(coordinator.alertKind == .delete)
        #expect(model.isDeleteConfirmationPresented)
        #expect(await recorder.deletedIDs.isEmpty)

        await suspension.release()
        #expect(await toggle.value)
        coordinator.confirmAlert()
        await waitUntilSettled(coordinator)

        #expect(await recorder.deletedIDs == [model.detachedDraft.id])
        #expect(model.saveState == .deleted)
        #expect(!actions.isBusy)
    }

    @Test func invalidatedDeleteConfirmationReleasesTheSharedGate() async {
        let recorder = ReminderMutationRecorder()
        let actions = makeListActions(recorder: recorder)
        let (model, router) = makeScenario(actions: actions)
        let coordinator = ReminderFormConfirmationCoordinator()
        coordinator.requestDelete(model: model, router: router)
        model.cancelDeleteConfirmation()

        coordinator.confirmAlert()

        #expect(!coordinator.isPersistenceOperationInFlight)
        #expect(coordinator.alertKind == nil)
        #expect(!actions.isBusy)
        await expectListMutationsCanResume(actions, recorder: recorder)
    }

    private var reminderID: UUID {
        UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    }

    private var capacityWarning: CapacityWarning {
        CapacityWarning(
            reminderID: reminderID,
            earliestGroupID: AlertGroupID(
                reminderID: reminderID,
                baseOccurrenceInstant: Date(timeIntervalSince1970: 2_230_000_000)
            ),
            planningCapacity: 60
        )
    }

    private func makeListActions(recorder: ReminderMutationRecorder) -> ReminderActionCoordinator {
        ReminderActionCoordinator(
            handlers: ReminderActionHandlers(
                setEnabled: { command in
                    await recorder.recordToggle()
                    return .saved(command.reminderID)
                },
                delete: { id in await recorder.recordDeletion(id) }
            ))
    }

    private func makeScenario(
        actions: ReminderActionCoordinator,
        save:
            @escaping @Sendable (
                ReminderDraft, CapacityConsent, ExpiredScheduleConsent
            ) async throws -> SaveReminderOutcome = { draft, _, _ in .saved(draft.id) },
        delete: @escaping @Sendable (UUID) async throws -> Void = { _ in }
    ) -> (ReminderFormModel, AppRouter) {
        let now = Date(timeIntervalSince1970: 2_200_000_000)
        let schedule = ScheduleDefinition(
            source: SourceWallClock(
                year: 2040, month: 8, day: 31, hour: 9, minute: 30,
                timeZoneIdentifier: "America/New_York"
            ),
            rule: .daily(interval: 1), end: .never, early: nil
        )
        let model = ReminderFormModel(
            snapshot: ReminderSnapshot(
                id: reminderID, title: "Original title", notes: nil, urlString: nil,
                enabled: true,
                schedule: .valid(schedule, sourceVersion: 1, originalData: Data([1])),
                tagIDs: [], createdAt: now, updatedAt: now
            ),
            savedRepeatPresentation: nil, now: now,
            actions: ReminderFormActions(save: save, delete: delete)
        )
        let router = AppRouter(actions: actions)
        router.register(form: model)
        router.synchronizeLayout(.regular)
        router.showReminder(reminderID)
        model.title = "Edited title"
        return (model, router)
    }

    private func expectListMutationsAreBlocked(
        _ actions: ReminderActionCoordinator,
        recorder: ReminderMutationRecorder
    ) async {
        #expect(await actions.setEnabled(false, for: reminderID, fallback: true) == false)
        actions.requestDelete(reminderID)
        #expect(actions.pendingDeleteID == nil)
        #expect(await actions.confirmDelete(reminderID) == false)
        #expect(await recorder.toggleCount == 0)
        #expect(await recorder.deletedIDs.isEmpty)
    }

    private func expectListMutationsCanResume(
        _ actions: ReminderActionCoordinator,
        recorder: ReminderMutationRecorder
    ) async {
        #expect(await actions.setEnabled(false, for: reminderID, fallback: true))
        actions.requestDelete(reminderID)
        #expect(await actions.confirmDelete(reminderID))
        #expect(await recorder.toggleCount == 1)
        #expect(await recorder.deletedIDs == [reminderID])
        #expect(!actions.isBusy)
    }

    private func waitUntilSettled(_ coordinator: ReminderFormConfirmationCoordinator) async {
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
}

private enum ReminderMutationProbeError: Error {
    case failed
}

private actor ReminderMutationRecorder {
    private(set) var saveConsents: [CapacityConsent] = []
    private(set) var toggleCount = 0
    private(set) var deletedIDs: [UUID] = []

    func recordSave(_ capacity: CapacityConsent) {
        saveConsents.append(capacity)
    }

    func recordToggle() {
        toggleCount += 1
    }

    func recordDeletion(_ id: UUID) {
        deletedIDs.append(id)
    }
}

private actor ReminderMutationSuspension {
    private var operation: CheckedContinuation<Void, Never>?
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        await withCheckedContinuation { continuation in
            operation = continuation
            for waiter in entryWaiters { waiter.resume() }
            entryWaiters.removeAll()
        }
    }

    func waitUntilEntered() async {
        guard operation == nil else { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func release() {
        operation?.resume()
        operation = nil
    }
}
