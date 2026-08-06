import Foundation
import Observation

enum AppRouterLayout: Sendable, Equatable {
    case compact
    case regular
}

enum AppRouterDestination: Sendable, Hashable {
    case reminderDetail(UUID)
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
    private var detailsByID: [UUID: ReminderDetailModel] = [:]
    private var formsByID: [UUID: ReminderFormModel] = [:]
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

    func register(detail: ReminderDetailModel) {
        detailsByID[detail.id] = detail
    }

    func register(form: ReminderFormModel) {
        formsByID[form.detachedDraft.id] = form
    }

    func registerFormIfAbsent(_ form: ReminderFormModel) {
        guard formsByID[form.detachedDraft.id] == nil else { return }
        register(form: form)
    }

    func detailModel(for reminderID: UUID) -> ReminderDetailModel? {
        detailsByID[reminderID]
    }

    func formModel(for reminderID: UUID) -> ReminderFormModel? {
        formsByID[reminderID]
    }

    func showReminder(_ reminderID: UUID) {
        selectedReminderID = reminderID
        route(to: .reminderDetail(reminderID))
    }

    func showEdit(_ reminderID: UUID) {
        route(to: .reminderEdit(reminderID))
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
        compactPath = path
        selectedReminderID = path.reversed().lazy.compactMap(\.detailReminderID).first
    }

    func reminderWasDeleted(_ reminderID: UUID) {
        detailsByID.removeValue(forKey: reminderID)
        formsByID.removeValue(forKey: reminderID)
        if selectedReminderID == reminderID {
            selectedReminderID = nil
        }
        compactPath.removeAll { $0.reminderID == reminderID }
        if regularDestination?.reminderID == reminderID {
            regularDestination = nil
        }
    }

    func reminderFormWasSaved(_ reminderID: UUID) {
        formsByID.removeValue(forKey: reminderID)
        compactPath.removeAll { $0.formReminderID == reminderID }
        if regularDestination?.formReminderID == reminderID {
            regularDestination = nil
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
            regularDestination = compactPath.last
                ?? selectedReminderID.map(AppRouterDestination.reminderDetail)
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
}

private extension AppRouterDestination {
    var reminderID: UUID? {
        switch self {
        case let .reminderDetail(id), let .reminderEdit(id), let .reminderCreate(id):
            id
        case .settings, .notificationUnavailable:
            nil
        }
    }

    var formReminderID: UUID? {
        switch self {
        case .reminderDetail:
            nil
        case let .reminderEdit(id), let .reminderCreate(id):
            id
        case .settings, .notificationUnavailable:
            nil
        }
    }

    var detailReminderID: UUID? {
        guard case let .reminderDetail(id) = self else { return nil }
        return id
    }
}
