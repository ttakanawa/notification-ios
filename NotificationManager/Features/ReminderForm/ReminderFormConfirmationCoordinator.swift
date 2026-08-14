import NotificationManagerApplication
import Observation

enum ReminderFormConfirmationAlertKind: Sendable, Equatable {
    case expiredSchedule
    case delete
    case discardChanges
}

@MainActor
@Observable
final class ReminderFormConfirmationCoordinator {
    private(set) var alertKind: ReminderFormConfirmationAlertKind?
    private(set) var capacityWarning: CapacityWarning?
    private(set) var isPersistenceOperationInFlight = false

    @ObservationIgnored private var alertContext: Context?
    @ObservationIgnored private var capacityContext: Context?
    @ObservationIgnored private var pendingCapacityConfirmationContext: Context?

    func save(model: ReminderFormModel, router: AppRouter) {
        guard canAcceptRequest, beginPersistenceOperation() else { return }
        let context = Context(model: model, router: router)
        Task { @MainActor in
            await router.performReminderSave(model.detachedDraft.id) {
                await model.save()
            }
            synchronizePresentation(for: context)
        }
    }

    func requestDelete(model: ReminderFormModel, router: AppRouter) {
        guard canAcceptRequest else { return }
        model.requestDeleteConfirmation()
        guard model.isDeleteConfirmationPresented else { return }
        alertContext = Context(model: model, router: router)
        alertKind = .delete
    }

    func requestDiscard(model: ReminderFormModel, router: AppRouter) {
        guard canAcceptRequest else { return }
        guard model.hasChanges else {
            model.discardChanges()
            router.dismissReminder(model.detachedDraft.id)
            return
        }
        alertContext = Context(model: model, router: router)
        alertKind = .discardChanges
    }

    func confirmAlert() {
        guard let context = alertContext, let alertKind else { return }

        switch alertKind {
        case .expiredSchedule:
            guard beginPersistenceOperation() else { return }
            guard context.model.consumeExpiredScheduleConfirmation() else {
                finishWithoutPresentation()
                return
            }
            clearAlertPresentation()
            Task { @MainActor in
                await context.router.performReminderSave(context.model.detachedDraft.id) {
                    await context.model.performConfirmedExpiredScheduleSave()
                }
                synchronizePresentation(for: context)
            }
        case .delete:
            guard beginPersistenceOperation() else { return }
            guard context.model.consumeDeleteConfirmation() else {
                finishWithoutPresentation()
                return
            }
            clearAlertPresentation()
            Task { @MainActor in
                await context.router.performReminderDeletion(context.model.detachedDraft.id) {
                    await context.model.performConfirmedDelete()
                }
                synchronizePresentation(for: context)
            }
        case .discardChanges:
            clearAlertPresentation()
            context.model.discardChanges()
            context.router.dismissReminder(context.model.detachedDraft.id)
        }
    }

    func cancelAlert() {
        cancelPresentedAlert()
    }

    func dismissAlertFromSystem() {
        cancelPresentedAlert()
    }

    func confirmCapacity() {
        guard let context = capacityContext,
              beginPersistenceOperation()
        else {
            return
        }
        pendingCapacityConfirmationContext = context
        capacityContext = nil
        capacityWarning = nil
    }

    func cancelCapacity() {
        cancelPresentedCapacity()
    }

    func dismissCapacityFromSystem() {
        cancelPresentedCapacity()
    }

    func capacitySheetDidDismiss() {
        guard let context = pendingCapacityConfirmationContext else { return }
        pendingCapacityConfirmationContext = nil
        Task { @MainActor in
            await context.router.performReminderSave(context.model.detachedDraft.id) {
                await context.model.confirmCapacitySave()
            }
            synchronizePresentation(for: context)
        }
    }

    private var canAcceptRequest: Bool {
        !isPersistenceOperationInFlight
            && alertKind == nil
            && capacityWarning == nil
            && pendingCapacityConfirmationContext == nil
    }

    private func beginPersistenceOperation() -> Bool {
        guard !isPersistenceOperationInFlight else { return false }
        isPersistenceOperationInFlight = true
        return true
    }

    private func synchronizePresentation(for context: Context) {
        isPersistenceOperationInFlight = false
        capacityWarning = nil
        alertKind = nil
        capacityContext = nil
        alertContext = nil
        pendingCapacityConfirmationContext = nil
        switch context.model.saveState {
        case let .requiresCapacityConfirmation(warning):
            capacityContext = context
            capacityWarning = warning
        case .requiresExpiredScheduleConfirmation:
            alertContext = context
            alertKind = .expiredSchedule
        default:
            break
        }
    }

    private func cancelPresentedAlert() {
        guard let context = alertContext, let alertKind else { return }
        clearAlertPresentation()
        switch alertKind {
        case .expiredSchedule:
            context.model.dismissPendingConfirmation()
        case .delete:
            context.model.cancelDeleteConfirmation()
        case .discardChanges:
            break
        }
    }

    private func clearAlertPresentation() {
        alertKind = nil
        alertContext = nil
    }

    private func cancelPresentedCapacity() {
        guard let context = capacityContext else { return }
        capacityContext = nil
        capacityWarning = nil
        context.model.dismissPendingConfirmation()
    }

    private func finishWithoutPresentation() {
        isPersistenceOperationInFlight = false
        clearAlertPresentation()
    }

    private struct Context {
        let model: ReminderFormModel
        let router: AppRouter
    }
}
