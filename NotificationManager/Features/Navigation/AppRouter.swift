import Foundation
import Observation

enum AppRouterLayout: Sendable, Equatable {
    case compact
    case regular
}

enum AppRouterDestination: Sendable, Hashable {
    case reminderEdit(UUID)
    case reminderCreate(UUID)
    case settings
    case notificationUnavailable
}

@MainActor
@Observable
final class AppRouter {
    let actions: ReminderActionCoordinator
    let notificationSettingsModel: NotificationSettingsModel?
    let tagManagementModel: TagManagementModel?
    var compactPath: [AppRouterDestination] = []
    var regularDestination: AppRouterDestination?
    var selectedReminderID: UUID?

    private(set) var layout: AppRouterLayout = .compact
    private var formsByID: [UUID: ReminderFormModel] = [:]
    private var persistedReminderIDs: Set<UUID> = []
    @ObservationIgnored private let createForm: @MainActor () -> ReminderFormModel?
    @ObservationIgnored private let reminderSaved: @MainActor @Sendable (UUID) async -> Void

    init(
        actions: ReminderActionCoordinator,
        notificationSettingsModel: NotificationSettingsModel? = nil,
        tagManagementModel: TagManagementModel? = nil,
        createForm: @escaping @MainActor () -> ReminderFormModel? = { nil },
        reminderSaved: @escaping @MainActor @Sendable (UUID) async -> Void = { _ in }
    ) {
        self.actions = actions
        self.notificationSettingsModel = notificationSettingsModel
        self.tagManagementModel = tagManagementModel
        self.createForm = createForm
        self.reminderSaved = reminderSaved
    }

    func register(form: ReminderFormModel) {
        let id = form.detachedDraft.id
        formsByID[id] = form
        if form.canDelete {
            persistedReminderIDs.insert(id)
        }
    }

    func registerFormIfAbsent(_ form: ReminderFormModel) {
        guard formsByID[form.detachedDraft.id] == nil else { return }
        register(form: form)
    }

    func formModel(for reminderID: UUID) -> ReminderFormModel? {
        formsByID[reminderID]
    }

    func showReminder(_ reminderID: UUID) {
        guard persistedReminderIDs.contains(reminderID) else { return }
        selectedReminderID = reminderID
        route(to: .reminderEdit(reminderID))
    }

    func dismissReminder(_ reminderID: UUID) {
        compactPath.removeAll { $0 == .reminderEdit(reminderID) }
        if regularDestination == .reminderEdit(reminderID) {
            regularDestination = nil
        }
        if selectedReminderID == reminderID {
            selectedReminderID = nil
        }
    }

    func showCreate() {
        guard let form = createForm() else { return }
        register(form: form)
        route(to: .reminderCreate(form.detachedDraft.id))
    }

    func showSettings() {
        selectedReminderID = nil
        route(to: .settings)
    }

    func showNotificationUnavailable() {
        selectedReminderID = nil
        route(to: .notificationUnavailable)
    }

    func setCompactPathFromSystem(_ path: [AppRouterDestination]) {
        let validPath = path.filter(isRegisteredDestination)
        compactPath = validPath
        selectedReminderID = validPath.reversed()
            .compactMap(\.editReminderID)
            .first { persistedReminderIDs.contains($0) }
    }

    func reminderWasDeleted(_ reminderID: UUID) {
        compactPath.removeAll { $0.reminderID == reminderID }
        if regularDestination?.reminderID == reminderID {
            regularDestination = nil
        }
        if selectedReminderID == reminderID {
            selectedReminderID = nil
        }
        persistedReminderIDs.remove(reminderID)
        formsByID.removeValue(forKey: reminderID)
    }

    func prunePersistedReminders(keeping currentIDs: Set<UUID>) {
        let removedIDs = persistedReminderIDs.subtracting(currentIDs)
        for reminderID in removedIDs {
            reminderWasDeleted(reminderID)
        }
    }

    func reminderFormWasSaved(_ reminderID: UUID) {
        formsByID.removeValue(forKey: reminderID)
        compactPath.removeAll { $0.formReminderID == reminderID }
        if regularDestination?.formReminderID == reminderID {
            regularDestination = nil
        }
        if selectedReminderID == reminderID {
            selectedReminderID = nil
        }
    }

    @discardableResult
    func performReminderSave(
        _ reminderID: UUID,
        operation: @MainActor () async -> Bool
    ) async -> Bool {
        guard await operation() else { return false }
        reminderFormWasSaved(reminderID)
        await reminderSaved(reminderID)
        return true
    }

    @discardableResult
    func performReminderDeletion(
        _ reminderID: UUID,
        operation: @MainActor () async -> Bool
    ) async -> Bool {
        guard await operation() else { return false }
        reminderWasDeleted(reminderID)
        return true
    }

    func synchronizeLayout(_ newLayout: AppRouterLayout) {
        guard newLayout != layout else { return }
        switch newLayout {
        case .regular:
            regularDestination =
                compactPath.last
                ?? selectedReminderID.map(AppRouterDestination.reminderEdit)
            compactPath = []
        case .compact:
            compactPath = regularDestination.map { [$0] } ?? []
        }
        layout = newLayout
    }

    private func route(to destination: AppRouterDestination) {
        switch layout {
        case .compact:
            compactPath.append(destination)
        case .regular:
            regularDestination = destination
        }
    }

    private func isRegisteredDestination(_ destination: AppRouterDestination) -> Bool {
        switch destination {
        case .reminderEdit(let id):
            persistedReminderIDs.contains(id) && formsByID[id] != nil
        case .reminderCreate(let id):
            formsByID[id] != nil
        case .settings, .notificationUnavailable:
            true
        }
    }
}

extension AppRouterDestination {
    fileprivate var reminderID: UUID? {
        switch self {
        case .reminderEdit(let id), .reminderCreate(let id):
            id
        case .settings, .notificationUnavailable:
            nil
        }
    }

    fileprivate var formReminderID: UUID? {
        switch self {
        case .reminderEdit(let id), .reminderCreate(let id):
            id
        case .settings, .notificationUnavailable:
            nil
        }
    }

    fileprivate var editReminderID: UUID? {
        guard case .reminderEdit(let id) = self else { return nil }
        return id
    }
}
