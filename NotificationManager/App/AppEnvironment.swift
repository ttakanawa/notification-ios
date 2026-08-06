import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import NotificationManagerPersistence
import SwiftData
import UIKit

@MainActor
final class AppEnvironment {
    let container: ModelContainer?
    let repository: SwiftDataReminderRepository?
    let eligibilityIndexStore: ForegroundEligibilityIndexStore
    let listModel: ReminderListModel
    let router: AppRouter
    let notificationSettingsModel: NotificationSettingsModel?
    let tagManagementModel: TagManagementModel?
    let lifecycleCoordinator: AppLifecycleCoordinator?

    private let stateStore: DeviceSchedulingStateStore?
    private let formActions: ReminderFormActions
    private let presentationRefreshCoordinator:
        LatestPresentationRefreshCoordinator<
            CompleteReminderSnapshot,
            DeviceSchedulingStateSnapshot
        >?
    private var schedulingStateObserver: SchedulingStatePresentationObserver?
    private var snapshotGeneration: UInt64 = 0
    private var hasStarted = false

    /// Identity-only environment used by bootstrap state-machine tests.
    init() {
        let actions = ReminderActionCoordinator(handlers: ReminderActionHandlers(
            setEnabled: { command in .saved(command.reminderID) },
            delete: { _ in }
        ))
        let listModel = ReminderListModel(
            snapshot: ReminderListSnapshot(
                generation: 0,
                items: [],
                availableTags: []
            ),
            actions: actions
        )
        container = nil
        repository = nil
        eligibilityIndexStore = ForegroundEligibilityIndexStore()
        self.listModel = listModel
        router = AppRouter(actions: actions)
        notificationSettingsModel = nil
        tagManagementModel = nil
        lifecycleCoordinator = nil
        stateStore = nil
        formActions = ReminderFormActions(
            save: { draft, _, _ in .saved(draft.id) },
            delete: { _ in }
        )
        presentationRefreshCoordinator = nil
        schedulingStateObserver = nil
    }

    private init(
        container: ModelContainer,
        repository: SwiftDataReminderRepository,
        eligibilityIndexStore: ForegroundEligibilityIndexStore,
        listModel: ReminderListModel,
        router: AppRouter,
        notificationSettingsModel: NotificationSettingsModel,
        tagManagementModel: TagManagementModel,
        lifecycleCoordinator: AppLifecycleCoordinator,
        stateStore: DeviceSchedulingStateStore,
        formActions: ReminderFormActions,
        presentationRefreshCoordinator: LatestPresentationRefreshCoordinator<
            CompleteReminderSnapshot,
            DeviceSchedulingStateSnapshot
        >
    ) {
        self.container = container
        self.repository = repository
        self.eligibilityIndexStore = eligibilityIndexStore
        self.listModel = listModel
        self.router = router
        self.notificationSettingsModel = notificationSettingsModel
        self.tagManagementModel = tagManagementModel
        self.lifecycleCoordinator = lifecycleCoordinator
        self.stateStore = stateStore
        self.formActions = formActions
        self.presentationRefreshCoordinator = presentationRefreshCoordinator
        schedulingStateObserver = nil
    }

    static func production(
        container: ModelContainer,
        notificationDelegate: NotificationApplicationDelegate,
        preferenceStore: UserDefaultsDeviceNotificationPreferenceStore,
        authorizationService: NotificationAuthorizationService,
        notificationCenter: SystemNotificationCenterClient,
        cleanupService: NotificationCleanupService
    ) -> AppEnvironment {
        let repository = SwiftDataReminderRepository(container: container)
        let eligibilityIndexStore = notificationDelegate.eligibilityIndex
        let stateStore = DeviceSchedulingStateStore()
        let worker = NotificationReconcileWorker(
            snapshotLoader: CompleteSchedulingSnapshotLoader(repository: repository),
            preferenceStore: preferenceStore,
            authorizationProvider: authorizationService,
            notificationCenter: notificationCenter,
            eligibilityIndexStore: eligibilityIndexStore,
            stateStore: stateStore
        )
        let saveUseCase = SaveReminderUseCase(
            repository: repository,
            scheduleCodec: SchedulePayloadCodec(),
            preferenceStore: preferenceStore,
            authorizationState: {
                await authorizationService.currentAuthorization().state
            },
            reconcileRequester: worker
        )
        let deleteUseCase = DeleteReminderUseCase(
            repository: repository,
            notificationCleanup: cleanupService,
            reconcileRequester: worker
        )
        let tagUseCase = TagManagementUseCase(
            repository: repository,
            normalizer: TagNameNormalizerV1()
        )
        let relay = AppEnvironmentRelay()
        let presentationRefreshCoordinator = LatestPresentationRefreshCoordinator(
            loadSnapshot: {
                try? await repository.fetchCompleteSnapshot()
            },
            publish: { snapshot, deviceState in
                relay.publish(snapshot, deviceState: deviceState)
            }
        )
        let formActions = ReminderFormActions(
            save: { draft, capacity, expired in
                try await saveUseCase.execute(
                    draft: draft,
                    capacityConsent: capacity,
                    expiredScheduleConsent: expired
                )
            },
            delete: { reminderID in
                try await deleteUseCase.execute(reminderID: reminderID)
                await relay.refreshPresentation()
            }
        )
        let actions = ReminderActionCoordinator(handlers: ReminderActionHandlers(
            setEnabled: { command in
                guard let snapshot = try await repository.reminder(id: command.reminderID)
                else {
                    throw AppEnvironmentError.reminderNotFound(command.reminderID)
                }
                var draft = ReminderDraft(snapshot: snapshot)
                draft.enabled = command.enabled
                let outcome = try await saveUseCase.execute(
                    draft: draft,
                    capacityConsent: command.capacityConsent
                )
                if case .saved = outcome {
                    await relay.refreshPresentation()
                }
                return outcome
            },
            delete: { reminderID in
                try await deleteUseCase.execute(reminderID: reminderID)
                await relay.refreshPresentation()
            }
        ))
        let listModel = ReminderListModel(
            snapshot: ReminderListSnapshot(
                generation: 0,
                items: [],
                availableTags: []
            ),
            actions: actions
        )
        let settingsModel = NotificationSettingsModel(
            preferenceStore: preferenceStore,
            authorizationProvider: authorizationService,
            authorizationRequester: authorizationService,
            pendingCleaner: cleanupService,
            reconciler: worker
        )
        let tagModel = TagManagementModel(
            repository: repository,
            useCase: tagUseCase
        )
        let router = AppRouter(
            actions: actions,
            notificationSettingsModel: settingsModel,
            tagManagementModel: tagModel,
            createForm: {
                ReminderFormModel(
                    newReminderID: UUID(),
                    now: Date(),
                    actions: formActions,
                    availableTags: listModel.availableTags
                )
            },
            reminderSaved: { _ in
                await relay.refreshPresentation()
            }
        )
        let lifecycle = AppLifecycleCoordinator(
            eligibilityIndexStore: eligibilityIndexStore,
            requestReconcile: { reason in
                await worker.requestReconcile(reason)
            },
            enterBackground: {
                await worker.enterBackground()
            },
            refreshDeviceState: {
                await settingsModel.load()
            },
            refreshModelSnapshot: {
                await relay.refreshPresentation()
            }
        )
        let environment = AppEnvironment(
            container: container,
            repository: repository,
            eligibilityIndexStore: eligibilityIndexStore,
            listModel: listModel,
            router: router,
            notificationSettingsModel: settingsModel,
            tagManagementModel: tagModel,
            lifecycleCoordinator: lifecycle,
            stateStore: stateStore,
            formActions: formActions,
            presentationRefreshCoordinator: presentationRefreshCoordinator
        )
        relay.environment = environment
        environment.schedulingStateObserver = SchedulingStatePresentationObserver(
            stateStore: stateStore,
            refreshPresentation: { [weak environment] state in
                await environment?.refreshPresentation(deviceState: state)
            }
        )
        notificationDelegate.bind(
            reminderLookup: { reminderID in
                let reminder = try await repository.reminder(id: reminderID)
                if let reminder {
                    await relay.prepareForRouting(reminder)
                }
                return reminder
            },
            routeResponse: { destination in
                switch destination {
                case let .reminderDetail(reminderID):
                    router.showReminder(reminderID)
                case .notificationUnavailable:
                    router.showNotificationUnavailable()
                }
            },
            openURL: { url in
                UIApplication.shared.open(url)
            },
            reconcileAfterNotification: { trigger in
                await lifecycle.handle(trigger)
            }
        )
        return environment
    }

    func start() async {
        guard !hasStarted, let lifecycleCoordinator else { return }
        hasStarted = true
        lifecycleCoordinator.startObservingSystemChanges()
        await schedulingStateObserver?.start()
        await lifecycleCoordinator.handle(.launch)
    }

    func enterForeground() async {
        guard let lifecycleCoordinator else { return }
        if !hasStarted {
            await start()
        } else {
            await lifecycleCoordinator.handle(.foreground)
        }
    }

    func enterBackground() async {
        await lifecycleCoordinator?.handle(.background)
    }

    func backgroundRefresh() async {
        await lifecycleCoordinator?.backgroundRefresh()
    }

    func modelSnapshotChanged() async {
        await lifecycleCoordinator?.handle(.modelSnapshotChanged)
    }

    func refreshPresentation() async {
        guard let stateStore, let presentationRefreshCoordinator else { return }
        await presentationRefreshCoordinator.refresh(stateProvider: {
            await stateStore.snapshot()
        })
    }

    private func refreshPresentation(
        deviceState: DeviceSchedulingStateSnapshot
    ) async {
        await presentationRefreshCoordinator?.refresh(state: deviceState)
    }

    func prepareForRouting(_ reminder: ReminderSnapshot) async {
        guard let stateStore else { return }
        let complete = try? await repository?.fetchCompleteSnapshot()
        let tags = complete?.tags ?? []
        let deviceState = await stateStore.snapshot()
        register(
            reminder,
            tags: tags,
            deviceState: deviceState,
            now: Date()
        )
    }

    fileprivate func publish(
        _ snapshot: CompleteReminderSnapshot,
        deviceState: DeviceSchedulingStateSnapshot
    ) {
        let now = Date()
        let previousIDs = Set(listModel.items.map(\.id))
        let currentIDs = Set(snapshot.reminders.map(\.id))
        for deletedID in previousIDs.subtracting(currentIDs) {
            router.reminderWasDeleted(deletedID)
        }

        let items = snapshot.reminders.map {
            register($0, tags: snapshot.tags, deviceState: deviceState, now: now)
        }
        snapshotGeneration &+= 1
        listModel.publish(ReminderListSnapshot(
            generation: snapshotGeneration,
            items: items,
            availableTags: snapshot.tags.map(Self.tagPresentation)
        ))
    }

    @discardableResult
    private func register(
        _ reminder: ReminderSnapshot,
        tags: [TagSnapshot],
        deviceState: DeviceSchedulingStateSnapshot,
        now: Date
    ) -> ReminderListItemPresentation {
        let tagByID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        let presentations = reminder.tagIDs.compactMap { tagByID[$0] }
            .map(Self.tagPresentation)
        let status = (try? ReminderStatusCalculator().status(
            schedule: reminder.schedule,
            enabled: reminder.enabled,
            after: now,
            environment: FoundationRecurrenceEnvironment()
        )) ?? ReminderStatus(primary: .invalidSchedule, secondary: [])
        let schedule = reminder.validSchedule
        let physical = schedule.flatMap {
            try? NextNotificationProvider().nextPhysicalNotifications(
                for: reminder.id,
                schedule: $0,
                after: now,
                limit: 3,
                environment: FoundationRecurrenceEnvironment()
            ).notifications
        } ?? []
        let next = physical.map {
            PhysicalNotificationPresentation(
                notification: $0,
                sourceTimeZoneIdentifier: schedule?.source.timeZoneIdentifier,
                deviceLocalTime: $0.alertInstant
            )
        }
        let repeatSummary = schedule.map {
            LocalizedRepeatFormatter().summary(for: $0, locale: .current)
        }
        let groupValues = deviceState.outcomes
            .filter { $0.key.reminderID == reminder.id }
            .sorted { $0.key.baseOccurrenceInstant < $1.key.baseOccurrenceInstant }
        let earliestOutcome = groupValues.first?.value
        let displayedEarliestOutcome = deviceState.globalFailure == nil
            ? earliestOutcome
            : .unscheduledError
        let deviceStatus = DeviceSchedulingStatus.resolve(DeviceSchedulingStatusInput(
            lifecycleStatus: status.primary,
            deviceNotificationsEnabled: deviceState.deviceNotificationsEnabled,
            authorization: deviceState.authorization.state,
            earliestGroupOutcome: displayedEarliestOutcome,
            laterGroupOutcomes: groupValues.dropFirst().map(\.value),
            reconcileInProgressOrQueued: deviceState.reconcileInProgressOrQueued,
            earliestRequestPresentOrLatestAddSucceeded:
                displayedEarliestOutcome == .scheduled
        ))
        let item = ReminderListItemPresentation(
            id: reminder.id,
            title: reminder.title,
            reminderStatus: status,
            deviceSchedulingStatus: deviceStatus,
            nextPresentation: ReminderNextPresentationProjector.project(
                reminderID: reminder.id,
                foundationNotifications: next,
                state: deviceState
            ),
            nextReason: next.first?.reasons.first?.kind,
            sourceWallClock: schedule?.source,
            localizedRepeatSummary: repeatSummary,
            tags: presentations,
            enabled: reminder.enabled,
            scheduledThrough: deviceState.scheduledThrough[reminder.id],
            earliestGroupOutcome: displayedEarliestOutcome,
            updatedAt: reminder.updatedAt
        )
        let url = reminder.urlString
            .flatMap { try? CanonicalHTTPURL($0) }
            .flatMap { URL(string: $0.string) }
        router.register(detail: ReminderDetailModel(
            item: item,
            notes: reminder.notes,
            url: url,
            sourceTime: next.first?.sourceTime,
            currentDeviceTime: next.first?.deviceLocalTime,
            localizedRepeatSummary: repeatSummary,
            nextNotifications: next,
            alertGroups: groupValues.map {
                AlertGroupSchedulingPresentation(groupID: $0.key, outcome: $0.value)
            },
            scheduledThrough: deviceState.scheduledThrough[reminder.id],
            requestDiagnostics: requestDiagnostics(
                reminderID: reminder.id,
                state: deviceState
            )
        ))
        if router.formModel(for: reminder.id) == nil {
            router.registerFormIfAbsent(ReminderFormModel(
                snapshot: reminder,
                savedRepeatPresentation: repeatSummary.map(SavedRepeatPresentation.standard),
                now: now,
                actions: formActions,
                availableTags: presentations
            ))
        }
        return item
    }

    private func requestDiagnostics(
        reminderID: UUID,
        state: DeviceSchedulingStateSnapshot
    ) -> [MaterializedRequestDiagnosticPresentation] {
        state.materializedKinds.compactMap { identifier, kind in
            let classification = NotificationIdentifierCodec().classify(identifier)
            let identifierReminderID: UUID?
            switch classification {
            case let .currentOneShot(id, _), let .currentRepeating(id, _):
                identifierReminderID = id
            case .appOwnedStale, .unrelated:
                identifierReminderID = nil
            }
            guard identifierReminderID == reminderID else { return nil }
            return MaterializedRequestDiagnosticPresentation(
                identifier: identifier,
                kind: kind == .oneShot ? .oneShot : .repeating
            )
        }.sorted { $0.identifier < $1.identifier }
    }

    private static func tagPresentation(_ tag: TagSnapshot) -> ReminderTagPresentation {
        ReminderTagPresentation(
            id: tag.id,
            name: tag.name,
            normalizedName: tag.normalizedName
        )
    }
}

@MainActor
final class LatestPresentationRefreshCoordinator<
    Snapshot: Sendable,
    State: Sendable
> {
    typealias LoadSnapshot = @MainActor @Sendable () async -> Snapshot?
    typealias Publish = @MainActor @Sendable (Snapshot, State) -> Void
    typealias StateProvider = @MainActor @Sendable () async -> State?

    private let loadSnapshot: LoadSnapshot
    private let publish: Publish
    private var generation: UInt64 = 0

    init(
        loadSnapshot: @escaping LoadSnapshot,
        publish: @escaping Publish
    ) {
        self.loadSnapshot = loadSnapshot
        self.publish = publish
    }

    func refresh(state: State) async {
        let refreshGeneration = beginRefresh()
        await loadAndPublish(state: state, generation: refreshGeneration)
    }

    func refresh(stateProvider: @escaping StateProvider) async {
        let refreshGeneration = beginRefresh()
        guard let state = await stateProvider(),
              refreshGeneration == generation
        else {
            return
        }
        await loadAndPublish(state: state, generation: refreshGeneration)
    }

    private func loadAndPublish(
        state: State,
        generation refreshGeneration: UInt64
    ) async {
        guard let snapshot = await loadSnapshot(),
              refreshGeneration == generation
        else {
            return
        }
        publish(snapshot, state)
    }

    private func beginRefresh() -> UInt64 {
        generation &+= 1
        return generation
    }
}

@MainActor
final class SchedulingStatePresentationObserver {
    typealias Refresh = @MainActor @Sendable (
        DeviceSchedulingStateSnapshot
    ) async -> Void

    private let stateStore: DeviceSchedulingStateStore
    private let refreshPresentation: Refresh
    private var observationTask: Task<Void, Never>?

    init(
        stateStore: DeviceSchedulingStateStore,
        refreshPresentation: @escaping Refresh
    ) {
        self.stateStore = stateStore
        self.refreshPresentation = refreshPresentation
    }

    deinit {
        observationTask?.cancel()
    }

    func start() async {
        guard observationTask == nil else { return }
        let updates = await stateStore.updates()
        let refreshPresentation = self.refreshPresentation
        observationTask = Task { @MainActor in
            for await snapshot in updates {
                guard !Task.isCancelled else { return }
                await refreshPresentation(snapshot)
            }
        }
    }

    func stop() {
        observationTask?.cancel()
        observationTask = nil
    }
}

private enum AppEnvironmentError: Error {
    case reminderNotFound(UUID)
}

@MainActor
private final class AppEnvironmentRelay {
    weak var environment: AppEnvironment?

    func refreshPresentation() async {
        await environment?.refreshPresentation()
    }

    func prepareForRouting(_ reminder: ReminderSnapshot) async {
        await environment?.prepareForRouting(reminder)
    }

    func publish(
        _ snapshot: CompleteReminderSnapshot,
        deviceState: DeviceSchedulingStateSnapshot
    ) {
        environment?.publish(snapshot, deviceState: deviceState)
    }
}

private extension ReminderSnapshot {
    var validSchedule: ScheduleDefinition? {
        guard case let .valid(schedule, _, _) = self.schedule else { return nil }
        return schedule
    }
}

enum ReminderNextPresentationProjector {
    static func project(
        reminderID: UUID,
        foundationNotifications: [PhysicalNotificationPresentation],
        state: DeviceSchedulingStateSnapshot
    ) -> ReminderNextPresentation? {
        let codec = NotificationIdentifierCodec()
        let authoritative = state.nextTriggerDates.compactMap { identifier, date -> Date? in
            guard state.materializedKinds[identifier] == .repeating,
                  state.pendingOrAddedIdentifiers.contains(identifier),
                  case let .currentRepeating(identifierReminderID, _) = codec.classify(identifier),
                  identifierReminderID == reminderID
            else {
                return nil
            }
            return date
        }.min()

        if let authoritative {
            return .directOSFire(
                authoritative: authoritative,
                foundationPreview: foundationNotifications.first?.alertInstant
            )
        }
        return foundationNotifications.first.map(ReminderNextPresentation.rolling)
    }
}
