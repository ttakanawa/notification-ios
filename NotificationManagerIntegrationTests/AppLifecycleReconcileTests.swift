import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import Testing
@preconcurrency import UserNotifications
@testable import NotificationManager

@Suite("App lifecycle reconciliation")
struct AppLifecycleReconcileTests {
    @MainActor
    @Test func launchAndForegroundRefreshCurrentStateBeforeReconcile() async {
        let trace = LifecycleTraceRecorder()
        let coordinator = makeCoordinator(trace: trace)

        await coordinator.handle(.launch)
        await coordinator.handle(.foreground)

        #expect(await trace.events == [
            .deviceStateRefreshed,
            .modelSnapshotRefreshed,
            .reconcile(.foreground),
            .deviceStateRefreshed,
            .modelSnapshotRefreshed,
            .reconcile(.foreground)
        ])
    }

    @MainActor
    @Test func backgroundInvalidatesASuspendedForegroundBeforeItCanReconcile() async {
        let gate = FirstLifecycleDeviceRefreshGate()
        let trace = LifecycleTraceRecorder()
        let coordinator = AppLifecycleCoordinator(
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            requestReconcile: { reason in
                await trace.record(.reconcile(reason))
            },
            enterBackground: {
                await trace.record(.backgroundEntered)
            },
            refreshDeviceState: {
                await gate.refresh()
            },
            refreshModelSnapshot: {
                await trace.record(.modelSnapshotRefreshed)
            }
        )
        let foreground = Task { @MainActor in
            await coordinator.handle(.foreground)
        }
        await gate.waitForCallCount(1)

        await coordinator.handle(.background)
        await gate.releaseFirstRefresh()
        await foreground.value

        #expect(await trace.events == [.backgroundEntered])
    }

    @MainActor
    @Test func notificationCompletionsOnlyReconcileWhileSceneIsForeground() async {
        let trace = LifecycleTraceRecorder()
        let coordinator = makeCoordinator(trace: trace)

        await coordinator.handle(.launch)
        await coordinator.handle(.notificationPresentationCompleted)
        await coordinator.handle(.background)
        await coordinator.handle(.notificationPresentationCompleted)
        await coordinator.handle(.notificationResponseCompleted)
        await coordinator.backgroundRefresh()
        await coordinator.handle(.notificationResponseCompleted)
        await coordinator.handle(.foreground)
        await coordinator.handle(.notificationResponseCompleted)

        #expect(await trace.reconcileReasons == [
            .foreground,
            .foreground,
            .modelChanged,
            .foreground,
            .foreground
        ])
    }

    @MainActor
    @Test func launchRunsBeforeDelayedStateObservationSoBackgroundStaysLatest() async {
        let observerGate = LifecycleObserverStartGate()
        let trace = LifecycleTraceRecorder()
        let coordinator = makeCoordinator(trace: trace)
        let startup = Task { @MainActor in
            await AppEnvironmentStartSequence.run(
                startSchedulingStateObservation: {
                    await observerGate.start()
                },
                handleLaunch: {
                    await coordinator.handle(.launch)
                }
            )
        }

        await observerGate.waitUntilStarted()
        await coordinator.handle(.background)
        await observerGate.release()
        await startup.value

        #expect(await trace.events == [
            .deviceStateRefreshed,
            .modelSnapshotRefreshed,
            .reconcile(.foreground),
            .backgroundEntered
        ])
    }

    @MainActor
    @Test func newerForegroundInvalidatesAnOlderSuspendedForeground() async {
        let gate = FirstLifecycleDeviceRefreshGate()
        let trace = LifecycleTraceRecorder()
        let coordinator = AppLifecycleCoordinator(
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            requestReconcile: { reason in
                await trace.record(.reconcile(reason))
            },
            enterBackground: {},
            refreshDeviceState: {
                await gate.refresh()
            },
            refreshModelSnapshot: {
                await trace.record(.modelSnapshotRefreshed)
            }
        )
        let older = Task { @MainActor in
            await coordinator.handle(.foreground)
        }
        await gate.waitForCallCount(1)

        await coordinator.handle(.foreground)
        await gate.waitForCallCount(2)
        await gate.releaseFirstRefresh()
        await older.value

        #expect(await trace.events == [
            .modelSnapshotRefreshed,
            .reconcile(.foreground)
        ])
    }

    @MainActor
    @Test func everyStateChangingTriggerInvalidatesEligibilityBeforeRefresh() async {
        let reminderID = UUID(
            uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        )!
        for trigger in [
            AppLifecycleTrigger.modelSnapshotChanged,
            .significantTimeChanged,
            .timeZoneChanged,
            .localeChanged,
            .authorizationOrPreferenceChanged,
            .backgroundRefresh
        ] {
            let index = ForegroundEligibilityIndexStore()
            index.publish(eligibleReminderIDs: [reminderID])
            let observed = EligibilityObservationRecorder()
            let coordinator = AppLifecycleCoordinator(
                eligibilityIndexStore: index,
                requestReconcile: { _ in },
                enterBackground: {},
                refreshDeviceState: {},
                refreshModelSnapshot: {
                    await observed.record(index.snapshot())
                }
            )

            await coordinator.handle(trigger)

            #expect(await observed.snapshots.count == 1)
            #expect(await observed.snapshots.first?.isStale == true)
        }
    }

    @MainActor
    @Test func triggersMapToExistingWorkerReasonsAndBackgroundCancellation() async {
        let trace = LifecycleTraceRecorder()
        let coordinator = makeCoordinator(trace: trace)

        await coordinator.handle(.foreground)
        await coordinator.handle(.notificationPresentationCompleted)
        await coordinator.handle(.notificationResponseCompleted)
        await coordinator.handle(.modelSnapshotChanged)
        await coordinator.handle(.significantTimeChanged)
        await coordinator.handle(.timeZoneChanged)
        await coordinator.handle(.localeChanged)
        await coordinator.handle(.authorizationOrPreferenceChanged)
        await coordinator.handle(.background)
        await coordinator.backgroundRefresh()

        #expect(await trace.reconcileReasons == [
            .foreground,
            .foreground,
            .foreground,
            .modelChanged,
            .modelChanged,
            .modelChanged,
            .modelChanged,
            .deviceSettingsChanged,
            .modelChanged
        ])
        #expect(await trace.backgroundEntryCount == 2)
        #expect(await trace.events.suffix(3) == [
            .backgroundEntered,
            .modelSnapshotRefreshed,
            .reconcile(.modelChanged)
        ])
    }

    @MainActor
    @Test func systemAndModelImportNotificationsUseTheSameCoordinatorBoundary() async {
        let center = NotificationCenter()
        let names = AppLifecycleNotificationNames(
            significantTimeChanged: Notification.Name("test.significant-time"),
            timeZoneChanged: Notification.Name("test.time-zone"),
            localeChanged: Notification.Name("test.locale"),
            modelImported: Notification.Name("test.model-import")
        )
        let trace = LifecycleTraceRecorder()
        let coordinator = makeCoordinator(
            trace: trace,
            notificationCenter: center,
            notificationNames: names
        )
        coordinator.startObservingSystemChanges()

        center.post(name: names.significantTimeChanged, object: nil)
        center.post(name: names.timeZoneChanged, object: nil)
        center.post(name: names.localeChanged, object: nil)
        center.post(name: names.modelImported, object: nil)
        await trace.waitForReconcileCount(4)

        #expect(await trace.reconcileReasons == [
            .modelChanged,
            .modelChanged,
            .modelChanged,
            .modelChanged
        ])

        coordinator.stopObservingSystemChanges()
        center.post(name: names.modelImported, object: nil)
        await Task.yield()
        #expect(await trace.reconcileReasons.count == 4)
    }

    @MainActor
    @Test func systemNotificationStalesEligibilityBeforePostReturns() {
        let center = NotificationCenter()
        let names = AppLifecycleNotificationNames(
            significantTimeChanged: Notification.Name("test.immediate-significant-time"),
            timeZoneChanged: Notification.Name("test.immediate-time-zone"),
            localeChanged: Notification.Name("test.immediate-locale"),
            modelImported: Notification.Name("test.immediate-model-import")
        )
        let reminderID = UUID(
            uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        )!
        let index = ForegroundEligibilityIndexStore()
        index.publish(eligibleReminderIDs: [reminderID])
        let coordinator = AppLifecycleCoordinator(
            eligibilityIndexStore: index,
            notificationCenter: center,
            notificationNames: names,
            requestReconcile: { _ in },
            enterBackground: {}
        )
        coordinator.startObservingSystemChanges()

        center.post(name: names.modelImported, object: nil)

        #expect(index.snapshot().isStale)
        coordinator.stopObservingSystemChanges()
    }

    @MainActor
    @Test func latestSchedulingStateEventuallyRefreshesThePresentationProjection() async {
        let stateStore = DeviceSchedulingStateStore()
        let recorder = SchedulingPresentationRecorder()
        let observer = SchedulingStatePresentationObserver(
            stateStore: stateStore,
            refreshPresentation: { snapshot in
                await recorder.record(snapshot)
            }
        )

        await observer.start()
        await recorder.waitForCount(1)
        await stateStore.setReconcileInProgressOrQueued(true)
        await stateStore.publishFailure(.inventory)
        await stateStore.setReconcileInProgressOrQueued(false)
        await recorder.waitForFinalFailureState()
        observer.stop()

        let snapshots = await recorder.snapshots
        #expect(snapshots.first?.generation == 0)
        #expect(snapshots.last?.generation == 1)
        #expect(snapshots.last?.reconcileInProgressOrQueued == false)
        #expect(snapshots.last?.globalFailure == .inventory)
    }

    @MainActor
    @Test func modelImportObserverSignalsInitialAndEachChangedFingerprintOnce() async {
        let recorder = ModelImportRecorder()
        let observer = ModelImportChangeObserver<Int> {
            await recorder.recordImport()
        }

        await observer.observe(1)
        await observer.observe(1)
        #expect(await recorder.count == 1)

        await observer.observe(2)
        await observer.observe(3)

        #expect(await recorder.count == 3)
    }

    @MainActor
    @Test func newerPresentationRefreshWinsAndRebuildsTheSavedForm() async {
        let reminderID = UUID(
            uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        )!
        let gate = PresentationSnapshotGate<String>()
        let recorder = PresentationProjectionRecorder(reminderID: reminderID)
        recorder.router.register(form: lifecycleFormModel(
            reminderID: reminderID,
            title: "Unsaved draft"
        ))

        // A successful save removes the detached editor before its refresh begins.
        recorder.router.reminderFormWasSaved(reminderID)
        #expect(recorder.router.formModel(for: reminderID) == nil)

        let coordinator = LatestPresentationRefreshCoordinator<String, Int>(
            loadSnapshot: {
                await gate.load()
            },
            publish: { snapshot, state in
                recorder.publish(snapshot: snapshot, state: state)
            }
        )
        let saveHookRefresh = Task { @MainActor in
            await coordinator.refresh(state: 1)
        }
        await gate.waitForPendingCount(1)
        let newerStateRefresh = Task { @MainActor in
            await coordinator.refresh(state: 2)
        }
        await gate.waitForPendingCount(2)

        await gate.resolve(attempt: 1, value: "Saved current value")
        await newerStateRefresh.value
        #expect(recorder.projections == [
            PresentationProjection(snapshot: "Saved current value", state: 2)
        ])
        #expect(recorder.router.formModel(for: reminderID)?.title == "Saved current value")

        await gate.resolve(attempt: 0, value: "Stale pre-import value")
        await saveHookRefresh.value

        #expect(recorder.projections == [
            PresentationProjection(snapshot: "Saved current value", state: 2)
        ])
        #expect(recorder.router.formModel(for: reminderID)?.title == "Saved current value")
    }

    @MainActor
    @Test func repeatingProjectionUsesAuthoritativeOSFireAndFoundationPreview() throws {
        let reminderID = UUID(
            uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        )!
        let components = RepeatingTriggerComponents(
            timeZoneIdentifier: "America/New_York",
            hour: 9,
            minute: 30,
            second: 0
        )
        let identifier = try NotificationIdentifierCodec().repeatingIdentifier(
            reminderID: reminderID,
            components: components
        )
        let authoritative = Date(timeIntervalSince1970: 2_230_000_000)
        let preview = Date(timeIntervalSince1970: 2_229_996_400)
        let physical = PhysicalNotificationPresentation(
            alertInstant: preview,
            reasons: [PhysicalNotificationReasonPresentation(
                role: .primary,
                kind: .main,
                baseOccurrenceInstant: preview
            )],
            sourceTime: preview,
            deviceLocalTime: preview
        )
        let state = DeviceSchedulingStateSnapshot(
            generation: 1,
            reconcileInProgressOrQueued: false,
            globalFailure: nil,
            deviceNotificationsEnabled: true,
            authorization: NotificationAuthorizationSnapshot(
                state: .allowed,
                diagnostic: nil
            ),
            outcomes: [:],
            scheduledThrough: [:],
            materializedKinds: [identifier: .repeating],
            nextTriggerDates: [identifier: authoritative],
            pendingOrAddedIdentifiers: [identifier]
        )

        let projected = ReminderNextPresentationProjector.project(
            reminderID: reminderID,
            foundationNotifications: [physical],
            state: state
        )

        #expect(projected == .directOSFire(
            authoritative: authoritative,
            foundationPreview: preview
        ))
    }

    @Test func workerPublishesAuthoritativeNextOSFireIntoPresentationState() async throws {
        let reminderID = UUID(
            uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        )!
        let components = RepeatingTriggerComponents(
            timeZoneIdentifier: "America/New_York",
            hour: 9,
            minute: 30,
            second: 0
        )
        let identifier = try NotificationIdentifierCodec().repeatingIdentifier(
            reminderID: reminderID,
            components: components
        )
        let groupID = AlertGroupID(
            reminderID: reminderID,
            baseOccurrenceInstant: Date(timeIntervalSince1970: 2_229_996_400)
        )
        let request = LogicalNotificationRequest(
            identifier: identifier,
            reminderID: reminderID,
            payload: .repeating(
                components: components,
                contributors: [RepeatingTriggerContributor(
                    kind: .main,
                    sourceComponents: components
                )]
            ),
            contributingGroupIDs: [groupID]
        )
        let reminder = ReminderSnapshot(
            id: reminderID,
            title: "Direct",
            notes: nil,
            urlString: nil,
            enabled: true,
            schedule: .corrupt(originalData: Data([0xff])),
            tagIDs: [],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let stateStore = DeviceSchedulingStateStore()
        let authoritative = Date(timeIntervalSince1970: 2_230_000_000)
        let worker = NotificationReconcileWorker(
            snapshotLoader: LifecycleSnapshotLoader(snapshot: CompleteReminderSnapshot(
                reminders: [reminder],
                tags: []
            )),
            preferenceStore: LifecyclePreferenceStore(),
            authorizationProvider: LifecycleAuthorizationProvider(),
            notificationCenter: LifecycleNotificationCenter(),
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            stateStore: stateStore,
            planner: LifecycleNotificationPlanner(plan: LogicalPlan(
                requests: [request],
                outcomes: [groupID: .scheduled],
                selectedGroupIDs: [groupID],
                scheduledThrough: [:],
                reminderStatuses: [:]
            )),
            materializer: LifecycleNotificationMaterializer(),
            clock: NotificationReconcileClock(
                now: { Date(timeIntervalSince1970: 2_200_000_000) },
                sleep: { _ in }
            ),
            retryDelays: [],
            triggerInspector: { _ in
                NotificationTriggerInspection(
                    repeats: true,
                    nextTriggerDate: authoritative
                )
            }
        )

        await worker.requestReconcile(.foreground)
        await worker.waitUntilIdle()

        let state = await stateStore.snapshot()
        #expect(state.materializedKinds[identifier] == .repeating)
        #expect(state.nextTriggerDates == [identifier: authoritative])
        #expect(state.pendingOrAddedIdentifiers == [identifier])
    }

    @MainActor
    private func makeCoordinator(
        trace: LifecycleTraceRecorder,
        notificationCenter: NotificationCenter = NotificationCenter(),
        notificationNames: AppLifecycleNotificationNames = .system
    ) -> AppLifecycleCoordinator {
        AppLifecycleCoordinator(
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            notificationCenter: notificationCenter,
            notificationNames: notificationNames,
            requestReconcile: { reason in
                await trace.record(.reconcile(reason))
            },
            enterBackground: {
                await trace.record(.backgroundEntered)
            },
            refreshDeviceState: {
                await trace.record(.deviceStateRefreshed)
            },
            refreshModelSnapshot: {
                await trace.record(.modelSnapshotRefreshed)
            }
        )
    }

    @MainActor
    private func lifecycleFormModel(
        reminderID: UUID,
        title: String
    ) -> ReminderFormModel {
        let model = ReminderFormModel(
            newReminderID: reminderID,
            now: Date(timeIntervalSince1970: 1),
            actions: ReminderFormActions(
                save: { draft, _, _ in .saved(draft.id) },
                delete: { _ in }
            )
        )
        model.title = title
        return model
    }
}

private enum LifecycleTraceEvent: Sendable, Equatable {
    case deviceStateRefreshed
    case modelSnapshotRefreshed
    case backgroundEntered
    case reconcile(ReconcileReason)
}

private actor LifecycleTraceRecorder {
    private(set) var events: [LifecycleTraceEvent] = []

    var reconcileReasons: [ReconcileReason] {
        events.compactMap { event in
            guard case let .reconcile(reason) = event else { return nil }
            return reason
        }
    }

    var backgroundEntryCount: Int {
        events.filter { $0 == .backgroundEntered }.count
    }

    func record(_ event: LifecycleTraceEvent) {
        events.append(event)
    }

    func waitForReconcileCount(_ count: Int) async {
        while reconcileReasons.count < count {
            await Task.yield()
        }
    }
}

private actor EligibilityObservationRecorder {
    private(set) var snapshots: [ForegroundEligibilityIndex] = []

    func record(_ snapshot: ForegroundEligibilityIndex) {
        snapshots.append(snapshot)
    }
}

private actor FirstLifecycleDeviceRefreshGate {
    private var callCount = 0
    private var callWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var firstRelease: CheckedContinuation<Void, Never>?

    func refresh() async {
        callCount += 1
        let ready = callWaiters.filter { callCount >= $0.0 }
        callWaiters.removeAll { callCount >= $0.0 }
        ready.forEach { $0.1.resume() }
        guard callCount == 1 else { return }
        await withCheckedContinuation { continuation in
            firstRelease = continuation
        }
    }

    func waitForCallCount(_ count: Int) async {
        guard callCount < count else { return }
        await withCheckedContinuation { continuation in
            callWaiters.append((count, continuation))
        }
    }

    func releaseFirstRefresh() {
        firstRelease?.resume()
        firstRelease = nil
    }
}

private actor LifecycleObserverStartGate {
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func start() async {
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor SchedulingPresentationRecorder {
    private(set) var snapshots: [DeviceSchedulingStateSnapshot] = []

    func record(_ snapshot: DeviceSchedulingStateSnapshot) {
        snapshots.append(snapshot)
    }

    func waitForCount(_ count: Int) async {
        while snapshots.count < count {
            await Task.yield()
        }
    }

    func waitForFinalFailureState() async {
        while snapshots.last?.generation != 1
            || snapshots.last?.reconcileInProgressOrQueued != false
            || snapshots.last?.globalFailure != .inventory
        {
            await Task.yield()
        }
    }
}

private actor ModelImportRecorder {
    private(set) var count = 0

    func recordImport() {
        count += 1
    }
}

private struct PresentationProjection: Sendable, Equatable {
    let snapshot: String
    let state: Int
}

@MainActor
private final class PresentationProjectionRecorder {
    let router: AppRouter
    private(set) var projections: [PresentationProjection] = []

    private let reminderID: UUID

    init(reminderID: UUID) {
        self.reminderID = reminderID
        router = AppRouter(actions: ReminderActionCoordinator(
            handlers: ReminderActionHandlers(
                setEnabled: { command in .saved(command.reminderID) },
                delete: { _ in }
            )
        ))
    }

    func publish(snapshot: String, state: Int) {
        projections.append(PresentationProjection(snapshot: snapshot, state: state))
        let form = ReminderFormModel(
            newReminderID: reminderID,
            now: Date(timeIntervalSince1970: 1),
            actions: ReminderFormActions(
                save: { draft, _, _ in .saved(draft.id) },
                delete: { _ in }
            )
        )
        form.title = snapshot
        router.registerFormIfAbsent(form)
    }
}

private actor PresentationSnapshotGate<Value: Sendable> {
    private var nextAttempt = 0
    private var pending: [Int: CheckedContinuation<Value, Never>] = [:]

    func load() async -> Value {
        let attempt = nextAttempt
        nextAttempt += 1
        return await withCheckedContinuation { continuation in
            pending[attempt] = continuation
        }
    }

    func waitForPendingCount(_ count: Int) async {
        while pending.count < count {
            await Task.yield()
        }
    }

    func resolve(attempt: Int, value: Value) {
        pending.removeValue(forKey: attempt)?.resume(returning: value)
    }
}

private struct LifecycleSnapshotLoader: CompleteSchedulingSnapshotLoading {
    let snapshot: CompleteReminderSnapshot

    func loadCompleteSnapshot() async throws -> CompleteReminderSnapshot {
        snapshot
    }
}

private actor LifecyclePreferenceStore: DeviceNotificationPreferenceStore {
    func isEnabled() -> Bool { true }
    func setEnabled(_ enabled: Bool) {}
}

private struct LifecycleAuthorizationProvider: NotificationAuthorizationProviding {
    func currentAuthorization() async -> NotificationAuthorizationSnapshot {
        NotificationAuthorizationSnapshot(state: .allowed, diagnostic: nil)
    }
}

private final class LifecycleNotificationCenter: NotificationCenterClient,
    @unchecked Sendable
{
    func pendingNotificationInventory() async throws -> [NotificationInventoryItem] { [] }
    func deliveredNotificationInventory() async -> [NotificationInventoryItem] { [] }
    func add(_ request: UNNotificationRequest) async throws {}
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {}
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {}
}

private struct LifecycleNotificationPlanner: NotificationPlanning {
    let plan: LogicalPlan
    func makePlan(_ input: PlannerInput) throws -> LogicalPlan { plan }
}

private struct LifecycleNotificationMaterializer: NotificationRequestMaterializing {
    func makeRequest(
        _ logical: LogicalNotificationRequest,
        input: MaterializationInput
    ) throws -> UNNotificationRequest {
        UNNotificationRequest(
            identifier: logical.identifier,
            content: UNMutableNotificationContent(),
            trigger: nil
        )
    }
}
