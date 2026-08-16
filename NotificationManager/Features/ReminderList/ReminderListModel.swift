import Foundation
import NotificationManagerApplication
import Observation

struct SetReminderEnabledCommand: Sendable, Equatable {
    let reminderID: UUID
    let enabled: Bool
    let capacityConsent: CapacityConsent
}

struct ReminderActionHandlers: Sendable {
    let setEnabled: @Sendable (SetReminderEnabledCommand) async throws -> SaveReminderOutcome
    let delete: @Sendable (UUID) async throws -> Void
}

enum ReminderActionFailure: Sendable, Equatable {
    case enabledChange
    case delete
}

enum ReminderActionState: Sendable, Equatable {
    case idle
    case working(UUID)
    case requiresCapacityConfirmation(UUID, Bool, CapacityWarning)
    case failed(UUID, ReminderActionFailure)
    case deleted(UUID)
}

@MainActor
@Observable
final class ReminderActionCoordinator {
    private(set) var pendingDeleteID: UUID?
    private(set) var state: ReminderActionState = .idle

    @ObservationIgnored private let handlers: ReminderActionHandlers
    private var enabledOverrides: [UUID: EnabledOverride] = [:]
    private var latestEnabledObservations: [UUID: EnabledObservation] = [:]
    private var pendingEnabledCapacityChange: PendingEnabledCapacityChange?
    private var confirmedDeleteID: UUID?
    private var actionGeneration: UInt64 = 0
    private var latestSnapshotGeneration: UInt64?

    init(handlers: ReminderActionHandlers) {
        self.handlers = handlers
    }

    var enabledCapacityConfirmation: (reminderID: UUID, warning: CapacityWarning)? {
        guard case .requiresCapacityConfirmation(let id, _, let warning) = state else {
            return nil
        }
        return (id, warning)
    }

    func enabledValue(for id: UUID, fallback: Bool) -> Bool {
        enabledOverrides[id]?.value ?? latestEnabledObservations[id]?.value ?? fallback
    }

    func isWorking(_ id: UUID) -> Bool {
        switch state {
        case .working(id), .requiresCapacityConfirmation(id, _, _):
            true
        default:
            false
        }
    }

    @discardableResult
    func setEnabled(_ enabled: Bool, for id: UUID, fallback: Bool) async -> Bool {
        guard !isBusy else { return false }
        actionGeneration &+= 1
        let generation = actionGeneration
        let previousOverride = enabledOverrides[id]
        enabledOverrides[id] = EnabledOverride(
            value: enabled,
            generation: generation,
            isCompleted: false,
            completionSnapshotGeneration: nil
        )
        state = .working(id)
        return await performEnabledChange(
            SetReminderEnabledCommand(
                reminderID: id,
                enabled: enabled,
                capacityConsent: .notProvided
            ),
            generation: generation,
            previousOverride: previousOverride
        )
    }

    @discardableResult
    func confirmEnabledCapacityChange(_ id: UUID) async -> Bool {
        guard let pending = pendingEnabledCapacityChange,
            pending.command.reminderID == id,
            case .requiresCapacityConfirmation(id, _, _) = state
        else {
            return false
        }
        pendingEnabledCapacityChange = nil
        state = .working(id)
        return await performEnabledChange(
            SetReminderEnabledCommand(
                reminderID: id,
                enabled: pending.command.enabled,
                capacityConsent: .acknowledged
            ),
            generation: pending.generation,
            previousOverride: pending.previousOverride
        )
    }

    func cancelEnabledCapacityChange(_ id: UUID) {
        guard let pending = pendingEnabledCapacityChange,
            pending.command.reminderID == id,
            case .requiresCapacityConfirmation(id, _, _) = state
        else {
            return
        }
        restoreEnabledOverride(
            for: id,
            generation: pending.generation,
            previousOverride: pending.previousOverride
        )
        pendingEnabledCapacityChange = nil
        state = .idle
    }

    func requestDelete(_ id: UUID) {
        guard !isBusy else { return }
        pendingDeleteID = id
    }

    func cancelDelete(_ id: UUID) {
        if pendingDeleteID == id { pendingDeleteID = nil }
    }

    func consumeDeleteConfirmation(_ id: UUID) -> Bool {
        guard pendingDeleteID == id, !isBusy else { return false }
        pendingDeleteID = nil
        confirmedDeleteID = id
        state = .working(id)
        return true
    }

    @discardableResult
    func performConfirmedDelete(_ id: UUID) async -> Bool {
        guard confirmedDeleteID == id, state == .working(id) else { return false }
        confirmedDeleteID = nil
        do {
            try await handlers.delete(id)
            enabledOverrides.removeValue(forKey: id)
            state = .deleted(id)
            return true
        } catch {
            state = .failed(id, .delete)
            return false
        }
    }

    @discardableResult
    func confirmDelete(_ id: UUID) async -> Bool {
        guard consumeDeleteConfirmation(id) else { return false }
        return await performConfirmedDelete(id)
    }

    fileprivate func ingest(_ snapshot: ReminderListSnapshot) {
        if let latestSnapshotGeneration,
            snapshot.generation <= latestSnapshotGeneration
        {
            return
        }
        latestSnapshotGeneration = snapshot.generation
        latestEnabledObservations = Dictionary(
            uniqueKeysWithValues: snapshot.items.map { item in
                (item.id, EnabledObservation(value: item.enabled))
            }
        )
        for (id, override) in enabledOverrides where override.isCompleted {
            if let completionGeneration = override.completionSnapshotGeneration,
                snapshot.generation <= completionGeneration
            {
                continue
            }
            enabledOverrides.removeValue(forKey: id)
        }
    }

    private func performEnabledChange(
        _ command: SetReminderEnabledCommand,
        generation: UInt64,
        previousOverride: EnabledOverride?
    ) async -> Bool {
        do {
            let outcome = try await handlers.setEnabled(command)
            switch outcome {
            case .saved(let savedID) where savedID == command.reminderID:
                completeEnabledOverride(for: command.reminderID, generation: generation)
                pendingEnabledCapacityChange = nil
                state = .idle
                return true
            case .requiresCapacityConfirmation(let warning):
                pendingEnabledCapacityChange = PendingEnabledCapacityChange(
                    command: command,
                    generation: generation,
                    previousOverride: previousOverride
                )
                state = .requiresCapacityConfirmation(
                    command.reminderID,
                    command.enabled,
                    warning
                )
                return false
            case .saved, .requiresExpiredScheduleConfirmation:
                restoreEnabledOverride(
                    for: command.reminderID,
                    generation: generation,
                    previousOverride: previousOverride
                )
                pendingEnabledCapacityChange = nil
                state = .failed(command.reminderID, .enabledChange)
                return false
            }
        } catch {
            restoreEnabledOverride(
                for: command.reminderID,
                generation: generation,
                previousOverride: previousOverride
            )
            pendingEnabledCapacityChange = nil
            state = .failed(command.reminderID, .enabledChange)
            return false
        }
    }

    private func completeEnabledOverride(for id: UUID, generation: UInt64) {
        guard var override = enabledOverrides[id], override.generation == generation else {
            return
        }
        override.isCompleted = true
        override.completionSnapshotGeneration = latestSnapshotGeneration
        enabledOverrides[id] = override
    }

    private func restoreEnabledOverride(
        for id: UUID,
        generation: UInt64,
        previousOverride: EnabledOverride?
    ) {
        guard enabledOverrides[id]?.generation == generation else { return }
        enabledOverrides[id] = restorablePreviousOverride(previousOverride)
    }

    private func restorablePreviousOverride(
        _ previousOverride: EnabledOverride?
    ) -> EnabledOverride? {
        guard let previousOverride else { return nil }
        guard previousOverride.isCompleted, let latestSnapshotGeneration else {
            return previousOverride
        }
        guard let completionGeneration = previousOverride.completionSnapshotGeneration else {
            return nil
        }
        return latestSnapshotGeneration > completionGeneration ? nil : previousOverride
    }

    private var isBusy: Bool {
        switch state {
        case .working, .requiresCapacityConfirmation:
            true
        default:
            false
        }
    }
}

private struct EnabledOverride {
    let value: Bool
    let generation: UInt64
    var isCompleted: Bool
    var completionSnapshotGeneration: UInt64?
}

private struct EnabledObservation {
    let value: Bool
}

private struct PendingEnabledCapacityChange {
    let command: SetReminderEnabledCommand
    let generation: UInt64
    let previousOverride: EnabledOverride?
}

struct ReminderListSnapshot: Sendable, Equatable {
    let generation: UInt64
    let items: [ReminderListItemPresentation]
    let availableTags: [ReminderTagPresentation]
}

@MainActor
@Observable
final class ReminderListModel {
    private(set) var snapshot: ReminderListSnapshot
    var selectedTagID: UUID?

    @ObservationIgnored private let actions: ReminderActionCoordinator

    init(
        snapshot: ReminderListSnapshot,
        actions: ReminderActionCoordinator,
        selectedTagID: UUID? = nil
    ) {
        self.snapshot = snapshot
        self.actions = actions
        self.selectedTagID = selectedTagID
        actions.ingest(snapshot)
    }

    var items: [ReminderListItemPresentation] { snapshot.items }

    var availableTags: [ReminderTagPresentation] { snapshot.availableTags }

    var sections: ReminderListSections {
        ReminderListProjection.make(from: items, selectedTagID: selectedTagID)
    }

    var tagFilterChoices: [ReminderTagPresentation] {
        availableTags.sorted { lhs, rhs in
            if lhs.normalizedName != rhs.normalizedName {
                return lhs.normalizedName < rhs.normalizedName
            }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
        }
    }

    func publish(_ snapshot: ReminderListSnapshot) {
        guard snapshot.generation > self.snapshot.generation else { return }
        self.snapshot = snapshot
        actions.ingest(snapshot)
        if let selectedTagID,
            !snapshot.availableTags.contains(where: { $0.id == selectedTagID })
        {
            self.selectedTagID = nil
        }
    }
}
