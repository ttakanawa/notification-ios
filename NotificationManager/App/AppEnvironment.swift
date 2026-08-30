import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import NotificationManagerPersistence
import NotificationManagerWidgetSupport
import OSLog
import SwiftData
import UIKit

@MainActor
final class AppEnvironment {
    typealias NotificationHandlingActivation = @MainActor @Sendable () -> Void
    typealias DeepLinkReminderPreparation =
        @MainActor @Sendable (UUID) async -> ReminderSnapshot?
    typealias WidgetSnapshotPublication =
        @Sendable (WidgetSnapshot, UInt64) async -> Void

    private static let widgetSnapshotLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "org.tknw.punctual",
        category: "WidgetSnapshotPublication"
    )

    let container: ModelContainer?
    let repository: SwiftDataReminderRepository?
    let eligibilityIndexStore: ForegroundEligibilityIndexStore
    let listModel: ReminderListModel
    let router: AppRouter
    let notificationSettingsModel: NotificationSettingsModel?
    let tagManagementModel: TagManagementModel?
    let appIconSelectionModel: AppIconSelectionModel?
    let lifecycleCoordinator: AppLifecycleCoordinator?

    private let stateStore: DeviceSchedulingStateStore?
    private let formActions: ReminderFormActions
    private let assistedRepeatInterpreter: any AssistedRepeatInterpreting
    private let notificationHandlingActivation: NotificationHandlingActivation
    private let deepLinkReminderPreparation: DeepLinkReminderPreparation
    private let widgetSnapshotProjector: WidgetSnapshotProjector
    private let widgetSnapshotPublication: WidgetSnapshotPublication
    private let presentationRefreshCoordinator:
        LatestPresentationRefreshCoordinator<
            CompleteReminderSnapshot,
            DeviceSchedulingStateSnapshot
        >?
    private var schedulingStateObserver: SchedulingStatePresentationObserver?
    private var snapshotGeneration: UInt64 = 0
    private var hasStarted = false
    private var notificationHandlingIsActive = false

    /// Identity-only environment used by bootstrap state-machine tests.
    init(
        notificationHandlingActivation: @escaping NotificationHandlingActivation = {},
        deepLinkReminderPreparation: @escaping DeepLinkReminderPreparation = { _ in nil },
        widgetSnapshotPublication: @escaping WidgetSnapshotPublication = { _, _ in }
    ) {
        let actions = ReminderActionCoordinator(
            handlers: ReminderActionHandlers(
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
        appIconSelectionModel = nil
        lifecycleCoordinator = nil
        stateStore = nil
        formActions = ReminderFormActions(
            save: { draft, _, _ in .saved(draft.id) },
            delete: { _ in }
        )
        assistedRepeatInterpreter = AssistedRepeatInterpreterFactory.make()
        self.notificationHandlingActivation = notificationHandlingActivation
        self.deepLinkReminderPreparation = deepLinkReminderPreparation
        widgetSnapshotProjector = WidgetSnapshotProjector()
        self.widgetSnapshotPublication = widgetSnapshotPublication
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
        appIconSelectionModel: AppIconSelectionModel,
        lifecycleCoordinator: AppLifecycleCoordinator,
        stateStore: DeviceSchedulingStateStore,
        formActions: ReminderFormActions,
        assistedRepeatInterpreter: any AssistedRepeatInterpreting,
        notificationHandlingActivation: @escaping NotificationHandlingActivation,
        deepLinkReminderPreparation: @escaping DeepLinkReminderPreparation,
        widgetSnapshotPublication: @escaping WidgetSnapshotPublication,
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
        self.appIconSelectionModel = appIconSelectionModel
        self.lifecycleCoordinator = lifecycleCoordinator
        self.stateStore = stateStore
        self.formActions = formActions
        self.assistedRepeatInterpreter = assistedRepeatInterpreter
        self.notificationHandlingActivation = notificationHandlingActivation
        self.deepLinkReminderPreparation = deepLinkReminderPreparation
        widgetSnapshotProjector = WidgetSnapshotProjector()
        self.widgetSnapshotPublication = widgetSnapshotPublication
        self.presentationRefreshCoordinator = presentationRefreshCoordinator
        schedulingStateObserver = nil
    }

    static func production(
        container: ModelContainer,
        notificationDelegate: NotificationApplicationDelegate,
        preferenceStore: UserDefaultsNotificationPreferenceStore,
        authorizationService: NotificationAuthorizationService,
        notificationCenter: SystemNotificationCenterClient,
        cleanupService: NotificationCleanupService,
        widgetSnapshotPublication: @escaping WidgetSnapshotPublication
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
        let responseSnapshotPreparer = NotificationResponseSnapshotPreparer(
            prepareSnapshot: {
                await presentationRefreshCoordinator.refresh(stateProvider: {
                    await stateStore.snapshot()
                })
            },
            coalesceSnapshot: { generation in
                await presentationRefreshCoordinator.latestTerminalResult(
                    after: generation
                )
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
        let actions = ReminderActionCoordinator(
            handlers: ReminderActionHandlers(
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
        let iCloudSyncStatusModel = ICloudSyncStatusModel()
        let appIconModel = AppIconSelectionModel(
            service: UIApplicationAppIconService()
        )
        let tagModel = TagManagementModel(
            repository: repository,
            useCase: tagUseCase,
            associationRemovalCommitted: {
                await relay.refreshPresentation()
            }
        )
        let assistedRepeatInterpreter = AssistedRepeatInterpreterFactory.make()
        let router = AppRouter(
            actions: actions,
            notificationSettingsModel: settingsModel,
            iCloudSyncStatusModel: iCloudSyncStatusModel,
            tagManagementModel: tagModel,
            appIconSelectionModel: appIconModel,
            createForm: {
                ReminderFormModel(
                    newReminderID: UUID(),
                    now: Date(),
                    actions: formActions,
                    availableTags: listModel.availableTags,
                    assistedRepeatInterpreter: assistedRepeatInterpreter
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
            requestForegroundReconcile: { permit in
                await worker.requestForegroundReconcile(ifValid: permit)
            },
            enterBackground: { permit in
                await worker.enterBackground(ifValid: permit)
            },
            refreshDeviceState: {
                await settingsModel.load()
            },
            refreshModelSnapshot: {
                await relay.refreshPresentation()
            }
        )
        let notificationHandlingActivation: NotificationHandlingActivation = {
            notificationDelegate.bind(
                reminderLookup: { reminderID in
                    await responseSnapshotPreparer.prepare(reminderID: reminderID)
                },
                routeResponse: { destination in
                    switch destination {
                    case .reminderEdit(let reminderID):
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
        }
        let deepLinkReminderPreparation: DeepLinkReminderPreparation = { reminderID in
            await responseSnapshotPreparer.prepare(reminderID: reminderID)
        }
        let environment = AppEnvironment(
            container: container,
            repository: repository,
            eligibilityIndexStore: eligibilityIndexStore,
            listModel: listModel,
            router: router,
            notificationSettingsModel: settingsModel,
            tagManagementModel: tagModel,
            appIconSelectionModel: appIconModel,
            lifecycleCoordinator: lifecycle,
            stateStore: stateStore,
            formActions: formActions,
            assistedRepeatInterpreter: assistedRepeatInterpreter,
            notificationHandlingActivation: notificationHandlingActivation,
            deepLinkReminderPreparation: deepLinkReminderPreparation,
            widgetSnapshotPublication: widgetSnapshotPublication,
            presentationRefreshCoordinator: presentationRefreshCoordinator
        )
        relay.environment = environment
        environment.schedulingStateObserver = SchedulingStatePresentationObserver(
            stateStore: stateStore,
            refreshPresentation: { [weak environment] state in
                await environment?.refreshPresentation(deviceState: state)
            }
        )
        return environment
    }

    func activateNotificationHandling() {
        guard !notificationHandlingIsActive else { return }
        notificationHandlingIsActive = true
        notificationHandlingActivation()
    }

    func openDeepLink(_ deepLink: PunctualDeepLink) async {
        switch deepLink {
        case .list:
            router.showList()
        case .reminder(let reminderID):
            guard let reminder = await deepLinkReminderPreparation(reminderID) else {
                router.showNotificationUnavailable()
                return
            }
            let repeatSummary = Self.repeatSummary(for: reminder)
            let selectedTags = Self.selectedTagPresentations(
                for: reminder,
                from: listModel.availableTags
            )
            router.refreshFormIfClean(
                makeReminderForm(
                    reminder,
                    savedRepeatSummary: repeatSummary,
                    availableTags: selectedTags,
                    now: Date()
                ))
            router.showReminder(reminderID)
        }
    }

    func start() async {
        guard !hasStarted, let lifecycleCoordinator else { return }
        hasStarted = true
        router.iCloudSyncStatusModel?.start()
        lifecycleCoordinator.startObservingSystemChanges()
        await AppEnvironmentStartSequence.run(
            startSchedulingStateObservation: { [weak self] in
                await self?.schedulingStateObserver?.start()
            },
            handleLaunch: {
                await lifecycleCoordinator.handle(.launch)
            }
        )
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

    func publish(
        _ snapshot: CompleteReminderSnapshot,
        deviceState: DeviceSchedulingStateSnapshot
    ) {
        let now = Date()
        let currentIDs = Set(snapshot.reminders.map(\.id))
        router.prunePersistedReminders(keeping: currentIDs)

        let items = snapshot.reminders.map {
            register($0, tags: snapshot.tags, deviceState: deviceState, now: now)
        }
        snapshotGeneration &+= 1
        let generation = snapshotGeneration
        listModel.publish(
            ReminderListSnapshot(
                generation: generation,
                items: items,
                availableTags: snapshot.tags.map(Self.tagPresentation)
            ))

        do {
            let widgetSnapshot = try widgetSnapshotProjector.project(
                reminders: snapshot.reminders,
                items: items,
                deviceState: deviceState,
                generatedAt: now
            )
            let widgetSnapshotPublication = self.widgetSnapshotPublication
            Task {
                await widgetSnapshotPublication(widgetSnapshot, generation)
            }
        } catch {
            Self.widgetSnapshotLogger.error(
                "Widget snapshot projection failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    @discardableResult
    private func register(
        _ reminder: ReminderSnapshot,
        tags: [TagSnapshot],
        deviceState: DeviceSchedulingStateSnapshot,
        now: Date
    ) -> ReminderListItemPresentation {
        let presentations = Self.selectedTagPresentations(
            for: reminder,
            from: tags.map(Self.tagPresentation)
        )
        let status =
            (try? ReminderStatusCalculator().status(
                schedule: reminder.schedule,
                enabled: reminder.enabled,
                after: now,
                environment: FoundationRecurrenceEnvironment()
            )) ?? ReminderStatus(primary: .invalidSchedule, secondary: [])
        let schedule = reminder.validSchedule
        let physical =
            schedule.flatMap {
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
        let repeatSummary = Self.repeatSummary(for: reminder)
        let groupValues = deviceState.outcomes
            .filter { $0.key.reminderID == reminder.id }
            .sorted { $0.key.baseOccurrenceInstant < $1.key.baseOccurrenceInstant }
        let earliestOutcome = groupValues.first?.value
        let displayedEarliestOutcome =
            deviceState.globalFailure == nil
            ? earliestOutcome
            : .unscheduledError
        let deviceStatus = DeviceSchedulingStatus.resolve(
            DeviceSchedulingStatusInput(
                lifecycleStatus: status.primary,
                deviceNotificationsEnabled: deviceState.deviceNotificationsEnabled,
                authorization: deviceState.authorization.state,
                earliestGroupOutcome: displayedEarliestOutcome,
                laterGroupOutcomes: groupValues.dropFirst().map(\.value),
                reconcileInProgressOrQueued: deviceState.reconcileInProgressOrQueued,
                earliestRequestPresentOrAddSucceeded:
                    displayedEarliestOutcome == .scheduled
            ))
        let item = ReminderListItemPresentation(
            id: reminder.id,
            title: reminder.title,
            notes: reminder.notes,
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
            isRepeating: schedule.map { $0.rule != .none } ?? false,
            tags: presentations,
            enabled: reminder.enabled,
            scheduledThrough: deviceState.scheduledThrough[reminder.id],
            earliestGroupOutcome: displayedEarliestOutcome,
            updatedAt: reminder.updatedAt
        )
        if router.formModel(for: reminder.id) == nil {
            router.registerFormIfAbsent(
                makeReminderForm(
                    reminder,
                    savedRepeatSummary: repeatSummary,
                    availableTags: presentations,
                    now: now
                ))
        }
        return item
    }

    private func makeReminderForm(
        _ reminder: ReminderSnapshot,
        savedRepeatSummary: String?,
        availableTags: [ReminderTagPresentation],
        now: Date
    ) -> ReminderFormModel {
        ReminderFormModel(
            snapshot: reminder,
            savedRepeatPresentation: savedRepeatSummary.map(SavedRepeatPresentation.standard),
            now: now,
            actions: formActions,
            availableTags: availableTags,
            assistedRepeatInterpreter: assistedRepeatInterpreter
        )
    }

    private static func tagPresentation(_ tag: TagSnapshot) -> ReminderTagPresentation {
        ReminderTagPresentation(
            id: tag.id,
            name: tag.name,
            normalizedName: tag.normalizedName
        )
    }

    private static func selectedTagPresentations(
        for reminder: ReminderSnapshot,
        from availableTags: [ReminderTagPresentation]
    ) -> [ReminderTagPresentation] {
        let tagByID = Dictionary(uniqueKeysWithValues: availableTags.map { ($0.id, $0) })
        return reminder.tagIDs.compactMap { tagByID[$0] }
    }

    private static func repeatSummary(for reminder: ReminderSnapshot) -> String? {
        reminder.validSchedule.map {
            LocalizedRepeatFormatter().summary(for: $0, locale: .current)
        }
    }
}

@MainActor
final class NotificationResponseSnapshotPreparer {
    typealias PrepareSnapshot =
        @MainActor @Sendable () async ->
        LatestPresentationRefreshResult<CompleteReminderSnapshot>
    typealias CoalesceSnapshot =
        @MainActor @Sendable (
            PresentationRefreshGeneration
        ) async -> LatestPresentationRefreshTerminalResult<CompleteReminderSnapshot>

    private let prepareSnapshot: PrepareSnapshot
    private let coalesceSnapshot: CoalesceSnapshot

    init(
        prepareSnapshot: @escaping PrepareSnapshot,
        coalesceSnapshot: @escaping CoalesceSnapshot
    ) {
        self.prepareSnapshot = prepareSnapshot
        self.coalesceSnapshot = coalesceSnapshot
    }

    func prepare(reminderID: UUID) async -> ReminderSnapshot? {
        guard !Task.isCancelled else { return nil }
        let snapshot: CompleteReminderSnapshot
        switch await prepareSnapshot() {
        case .accepted(let value):
            snapshot = value
        case .unavailable:
            return nil
        case .superseded(let generation):
            guard !Task.isCancelled else { return nil }
            switch await coalesceSnapshot(generation) {
            case .accepted(let value):
                snapshot = value
            case .unavailable, .cancelled:
                return nil
            }
        }
        guard !Task.isCancelled else { return nil }
        return snapshot.reminders.first { $0.id == reminderID }
    }
}

struct PresentationRefreshGeneration: Sendable, Equatable {
    fileprivate let value: UInt64
}

enum LatestPresentationRefreshResult<Snapshot: Sendable>: Sendable {
    case accepted(Snapshot)
    case unavailable
    case superseded(PresentationRefreshGeneration)
}

enum LatestPresentationRefreshTerminalResult<Snapshot: Sendable>: Sendable {
    case accepted(Snapshot)
    case unavailable
    case cancelled
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
    private var latestTerminalResult:
        (
            generation: PresentationRefreshGeneration,
            result: LatestPresentationRefreshTerminalResult<Snapshot>
        )?
    private var terminalResultWaiters:
        [UUID: CheckedContinuation<
            LatestPresentationRefreshTerminalResult<Snapshot>,
            Never
        >] = [:]

    init(
        loadSnapshot: @escaping LoadSnapshot,
        publish: @escaping Publish
    ) {
        self.loadSnapshot = loadSnapshot
        self.publish = publish
    }

    @discardableResult
    func refresh(state: State) async -> LatestPresentationRefreshResult<Snapshot> {
        let refreshGeneration = beginRefresh()
        return await loadAndPublish(state: state, generation: refreshGeneration)
    }

    @discardableResult
    func refresh(
        stateProvider: @escaping StateProvider
    ) async -> LatestPresentationRefreshResult<Snapshot> {
        let refreshGeneration = beginRefresh()
        let state = await stateProvider()
        guard refreshGeneration.value == generation else {
            return .superseded(refreshGeneration)
        }
        guard let state else { return finishUnavailable(refreshGeneration) }
        return await loadAndPublish(state: state, generation: refreshGeneration)
    }

    /// Coalesces a superseded caller onto the newest in-flight refresh. Only the
    /// current generation's accepted or unavailable result resumes waiters, so
    /// repeated supersession does not start retry loads or create a livelock.
    /// Cancellation removes and resumes the waiter with `.cancelled`.
    func latestTerminalResult(
        after supersededGeneration: PresentationRefreshGeneration
    ) async -> LatestPresentationRefreshTerminalResult<Snapshot> {
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: .cancelled)
                } else if let result = currentTerminalResult(
                    after: supersededGeneration
                ) {
                    continuation.resume(returning: result)
                } else {
                    terminalResultWaiters[waiterID] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelTerminalResultWaiter(waiterID)
            }
        }
    }

    private func loadAndPublish(
        state: State,
        generation refreshGeneration: PresentationRefreshGeneration
    ) async -> LatestPresentationRefreshResult<Snapshot> {
        let snapshot = await loadSnapshot()
        guard refreshGeneration.value == generation else {
            return .superseded(refreshGeneration)
        }
        guard let snapshot else { return finishUnavailable(refreshGeneration) }
        publish(snapshot, state)
        finishTerminal(.accepted(snapshot), generation: refreshGeneration)
        return .accepted(snapshot)
    }

    private func beginRefresh() -> PresentationRefreshGeneration {
        generation &+= 1
        return PresentationRefreshGeneration(value: generation)
    }

    private func finishUnavailable(
        _ refreshGeneration: PresentationRefreshGeneration
    ) -> LatestPresentationRefreshResult<Snapshot> {
        finishTerminal(.unavailable, generation: refreshGeneration)
        return .unavailable
    }

    private func finishTerminal(
        _ result: LatestPresentationRefreshTerminalResult<Snapshot>,
        generation refreshGeneration: PresentationRefreshGeneration
    ) {
        latestTerminalResult = (refreshGeneration, result)
        let waiters = Array(terminalResultWaiters.values)
        terminalResultWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: result)
        }
    }

    private func currentTerminalResult(
        after supersededGeneration: PresentationRefreshGeneration
    ) -> LatestPresentationRefreshTerminalResult<Snapshot>? {
        guard let latestTerminalResult,
            latestTerminalResult.generation.value == generation,
            latestTerminalResult.generation != supersededGeneration
        else {
            return nil
        }
        return latestTerminalResult.result
    }

    private func cancelTerminalResultWaiter(_ waiterID: UUID) {
        terminalResultWaiters.removeValue(forKey: waiterID)?
            .resume(returning: .cancelled)
    }
}

@MainActor
final class SchedulingStatePresentationObserver {
    typealias Refresh =
        @MainActor @Sendable (
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

    func publish(
        _ snapshot: CompleteReminderSnapshot,
        deviceState: DeviceSchedulingStateSnapshot
    ) {
        environment?.publish(snapshot, deviceState: deviceState)
    }
}

extension ReminderSnapshot {
    fileprivate var validSchedule: ScheduleDefinition? {
        guard case .valid(let schedule, _, _) = self.schedule else { return nil }
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
                case .currentRepeating(let identifierReminderID, _) = codec.classify(identifier),
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
