import Foundation
import Observation

struct ReminderActionHandlers: Sendable {
    let setEnabled: @Sendable (UUID, Bool) async throws -> Void
    let delete: @Sendable (UUID) async throws -> Void
}

enum ReminderActionFailure: Sendable, Equatable {
    case enabledChange
    case delete
}

enum ReminderActionState: Sendable, Equatable {
    case idle
    case working(UUID)
    case failed(UUID, ReminderActionFailure)
    case deleted(UUID)
}

@MainActor
@Observable
final class ReminderActionCoordinator {
    private(set) var pendingDeleteID: UUID?
    private(set) var state: ReminderActionState = .idle

    @ObservationIgnored private let handlers: ReminderActionHandlers
    private var enabledOverrides: [UUID: Bool] = [:]
    private var confirmedDeleteID: UUID?

    init(handlers: ReminderActionHandlers) {
        self.handlers = handlers
    }

    func enabledValue(for id: UUID, fallback: Bool) -> Bool {
        enabledOverrides[id] ?? fallback
    }

    func isWorking(_ id: UUID) -> Bool {
        state == .working(id)
    }

    func setEnabled(_ enabled: Bool, for id: UUID, fallback: Bool) async {
        guard !isBusy else { return }
        let previousOverride = enabledOverrides[id]
        enabledOverrides[id] = enabled
        state = .working(id)
        do {
            try await handlers.setEnabled(id, enabled)
            state = .idle
        } catch {
            if let previousOverride {
                enabledOverrides[id] = previousOverride
            } else {
                enabledOverrides.removeValue(forKey: id)
            }
            state = .failed(id, .enabledChange)
        }
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

    func synchronize(with items: [ReminderListItemPresentation]) {
        for item in items where enabledOverrides[item.id] == item.enabled {
            enabledOverrides.removeValue(forKey: item.id)
        }
    }

    private var isBusy: Bool {
        if case .working = state { true } else { false }
    }
}

@MainActor
@Observable
final class ReminderListModel {
    private(set) var items: [ReminderListItemPresentation]
    private(set) var availableTags: [ReminderTagPresentation]
    var selectedTagID: UUID?

    init(
        items: [ReminderListItemPresentation] = [],
        availableTags: [ReminderTagPresentation] = [],
        selectedTagID: UUID? = nil
    ) {
        self.items = items
        self.availableTags = availableTags
        self.selectedTagID = selectedTagID
    }

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

    func replace(
        items: [ReminderListItemPresentation],
        availableTags: [ReminderTagPresentation]
    ) {
        self.items = items
        self.availableTags = availableTags
        if let selectedTagID,
           !availableTags.contains(where: { $0.id == selectedTagID })
        {
            self.selectedTagID = nil
        }
    }
}
