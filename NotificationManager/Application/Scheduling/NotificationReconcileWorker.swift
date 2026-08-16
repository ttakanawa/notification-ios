import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import UserNotifications

public protocol NotificationPlanning: Sendable {
    func makePlan(_ input: PlannerInput) throws -> LogicalPlan
}

extension LogicalNotificationPlanner: NotificationPlanning {
    public func makePlan(_ input: PlannerInput) throws -> LogicalPlan {
        try plan(input)
    }
}

public protocol NotificationRequestMaterializing: Sendable {
    func makeRequest(
        _ logical: LogicalNotificationRequest,
        input: MaterializationInput
    ) throws -> UNNotificationRequest
}

extension NotificationRequestMaterializer: NotificationRequestMaterializing {
    public func makeRequest(
        _ logical: LogicalNotificationRequest,
        input: MaterializationInput
    ) throws -> UNNotificationRequest {
        try materialize(logical, input: input)
    }
}

public struct NotificationTriggerInspection: Sendable, Equatable {
    public let repeats: Bool
    public let nextTriggerDate: Date?

    public init(repeats: Bool, nextTriggerDate: Date?) {
        self.repeats = repeats
        self.nextTriggerDate = nextTriggerDate
    }

    public static func live(_ request: UNNotificationRequest) -> Self? {
        guard let trigger = request.trigger as? UNCalendarNotificationTrigger else { return nil }
        return Self(repeats: trigger.repeats, nextTriggerDate: trigger.nextTriggerDate())
    }
}

public struct NotificationReconcileClock: Sendable {
    public let now: @Sendable () -> Date
    public let sleep: @Sendable (TimeInterval) async throws -> Void

    public init(
        now: @escaping @Sendable () -> Date,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void
    ) {
        self.now = now
        self.sleep = sleep
    }

    public static let continuous = NotificationReconcileClock(
        now: { Date() },
        sleep: { seconds in
            guard seconds > 0 else { return }
            try await Task.sleep(for: .seconds(seconds))
        }
    )
}

public struct NotificationReconcileTimerState: Sendable, Equatable {
    public let retryScheduled: Bool
    public let foregroundReplenishmentScheduled: Bool
    public let retryAttempt: Int
}

public actor NotificationReconcileWorker: ReconcileRequesting {
    private struct MaterializedRequest {
        let logical: LogicalNotificationRequest
        let request: UNNotificationRequest
    }

    private let snapshotLoader: any CompleteSchedulingSnapshotLoading
    private let preferenceStore: any DeviceNotificationPreferenceStore
    private let authorizationProvider: any NotificationAuthorizationProviding
    private let notificationCenter: any NotificationCenterClient
    private let eligibilityIndexStore: ForegroundEligibilityIndexStore
    private let stateStore: DeviceSchedulingStateStore
    private let planner: any NotificationPlanning
    private let materializer: any NotificationRequestMaterializing
    private let recurrenceEnvironmentProvider: @Sendable () -> any RecurrenceEnvironment
    private let localeProvider: @Sendable () -> Locale
    private let clock: NotificationReconcileClock
    private let retryDelays: [TimeInterval]
    private let triggerInspector:
        @Sendable (
            UNNotificationRequest
        ) -> NotificationTriggerInspection?

    private var isLoopRunning = false
    private var isForeground = false
    private var pendingReasons: Set<ReconcileReason> = []
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private var retryTask: Task<Void, Never>?
    private var foregroundTimerTask: Task<Void, Never>?
    private var retryTimerToken: UInt64 = 0
    private var foregroundTimerToken: UInt64 = 0
    private var statePublicationRevision: UInt64 = 0
    private var retryAttempt = 0

    public init(
        snapshotLoader: any CompleteSchedulingSnapshotLoading,
        preferenceStore: any DeviceNotificationPreferenceStore,
        authorizationProvider: any NotificationAuthorizationProviding,
        notificationCenter: any NotificationCenterClient,
        eligibilityIndexStore: ForegroundEligibilityIndexStore,
        stateStore: DeviceSchedulingStateStore,
        planner: any NotificationPlanning = LogicalNotificationPlanner(),
        materializer: any NotificationRequestMaterializing = NotificationRequestMaterializer(),
        recurrenceEnvironmentProvider: @escaping @Sendable () -> any RecurrenceEnvironment = {
            FoundationRecurrenceEnvironment()
        },
        localeProvider: @escaping @Sendable () -> Locale = { .current },
        clock: NotificationReconcileClock = .continuous,
        retryDelays: [TimeInterval] = [1, 2, 4, 8, 16, 32, 60],
        triggerInspector:
            @escaping @Sendable (
                UNNotificationRequest
            ) -> NotificationTriggerInspection? = { NotificationTriggerInspection.live($0) }
    ) {
        self.snapshotLoader = snapshotLoader
        self.preferenceStore = preferenceStore
        self.authorizationProvider = authorizationProvider
        self.notificationCenter = notificationCenter
        self.eligibilityIndexStore = eligibilityIndexStore
        self.stateStore = stateStore
        self.planner = planner
        self.materializer = materializer
        self.recurrenceEnvironmentProvider = recurrenceEnvironmentProvider
        self.localeProvider = localeProvider
        self.clock = clock
        self.retryDelays = retryDelays
        self.triggerInspector = triggerInspector
    }

    deinit {
        retryTask?.cancel()
        foregroundTimerTask?.cancel()
    }

    public func requestReconcile(_ reason: ReconcileReason) async {
        if reason == .foreground {
            isForeground = true
            finishForegroundReconcileLinearization()
        } else {
            if reason.observesModelChange {
                eligibilityIndexStore.markStale()
            }
            enqueue(reason)
        }
        let revision = nextStatePublicationRevision()
        await stateStore.setReconcileInProgressOrQueued(true, revision: revision)
    }

    func requestForegroundReconcile(
        ifValid permit: ForegroundReconcilePermit
    ) async {
        // Keep validation, foreground mutation, and enqueue in one actor turn.
        guard permit.isValidAtWorkerIngress() else { return }
        isForeground = true
        finishForegroundReconcileLinearization()
        let revision = nextStatePublicationRevision()
        await stateStore.setReconcileInProgressOrQueued(true, revision: revision)
    }

    func enterBackground(ifValid permit: BackgroundReconcilePermit) {
        guard permit.isValidAtWorkerIngress() else { return }
        finishBackgroundTransition()
    }

    func enterBackground() {
        finishBackgroundTransition()
    }

    private func finishBackgroundTransition() {
        isForeground = false
        invalidateRetryTimer()
        invalidateForegroundTimer()
    }

    public func timerState() -> NotificationReconcileTimerState {
        NotificationReconcileTimerState(
            retryScheduled: retryTask != nil,
            foregroundReplenishmentScheduled: foregroundTimerTask != nil,
            retryAttempt: retryAttempt
        )
    }

    public func waitUntilIdle() async {
        guard isLoopRunning else { return }
        await withCheckedContinuation { continuation in
            idleWaiters.append(continuation)
        }
    }

    private func enqueue(_ reason: ReconcileReason) {
        pendingReasons.insert(reason)
        guard !isLoopRunning else { return }
        isLoopRunning = true
        Task { [weak self] in
            await self?.runLoop()
        }
    }

    private func finishForegroundReconcileLinearization() {
        invalidateRetryTimer()
        retryAttempt = 0
        enqueue(.foreground)
    }

    private func runLoop() async {
        var revision = nextStatePublicationRevision()
        await stateStore.setReconcileInProgressOrQueued(true, revision: revision)
        while true {
            while !pendingReasons.isEmpty {
                pendingReasons.removeAll()
                if await performPass() {
                    pendingReasons.insert(.foreground)
                }
            }
            revision = nextStatePublicationRevision()
            await stateStore.setReconcileInProgressOrQueued(false, revision: revision)
            guard pendingReasons.isEmpty else {
                revision = nextStatePublicationRevision()
                await stateStore.setReconcileInProgressOrQueued(true, revision: revision)
                continue
            }
            isLoopRunning = false
            let waiters = idleWaiters
            idleWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
            return
        }
    }

    private func nextStatePublicationRevision() -> UInt64 {
        statePublicationRevision &+= 1
        return statePublicationRevision
    }

    /// Returns true when dispatch crossed a one-shot boundary and the latest state must be planned.
    private func performPass() async -> Bool {
        let snapshot: CompleteReminderSnapshot
        do {
            snapshot = try await snapshotLoader.loadCompleteSnapshot()
        } catch {
            eligibilityIndexStore.markStale()
            await stateStore.publishFailure(.snapshot)
            scheduleRetryIfPossible()
            return false
        }

        let evaluationNow = clock.now()
        let deviceEnabled = await preferenceStore.isEnabled()
        let authorization = await authorizationProvider.currentAuthorization()
        let environment = recurrenceEnvironmentProvider()
        let locale = localeProvider()

        let logicalPlan: LogicalPlan
        do {
            logicalPlan = try planner.makePlan(
                PlannerInput(
                    snapshot: snapshot,
                    evaluationNow: evaluationNow,
                    deviceNotificationsEnabled: deviceEnabled,
                    authorizationAllowsScheduling: authorization.allowsScheduling,
                    capacity: 60,
                    recurrenceEnvironment: environment
                ))
        } catch {
            eligibilityIndexStore.markStale()
            await stateStore.publishFailure(.planning)
            scheduleRetryIfPossible()
            return false
        }

        let remindersByID = Dictionary(uniqueKeysWithValues: snapshot.reminders.map { ($0.id, $0) })
        var outcomes = logicalPlan.outcomes
        var materialized: [MaterializedRequest] = []
        var materializedKinds: [String: MaterializedNotificationKind] = [:]
        for logical in logicalPlan.requests {
            guard let reminder = remindersByID[logical.reminderID] else {
                markError(logical.contributingGroupIDs, outcomes: &outcomes)
                continue
            }
            do {
                let request = try materializer.makeRequest(
                    logical,
                    input: MaterializationInput(
                        reminder: reminder,
                        locale: locale,
                        evaluationNow: evaluationNow,
                        recurrenceEnvironment: environment
                    )
                )
                materialized.append(MaterializedRequest(logical: logical, request: request))
                materializedKinds[logical.identifier] =
                    logical.isRepeating
                    ? .repeating : .oneShot
            } catch {
                markError(logical.contributingGroupIDs, outcomes: &outcomes)
            }
        }

        // Membership comes from a fully classified snapshot and a matching materialized request,
        // not from the later lifecycle projection at the instant a one-shot fires.
        eligibilityIndexStore.publish(
            eligibleReminderIDs: Set(
                materialized.map(\.logical.reminderID)
            ))

        let pending: [NotificationInventoryItem]
        do {
            pending = try await notificationCenter.pendingNotificationInventory()
        } catch {
            await stateStore.publishFailure(.inventory)
            scheduleRetryIfPossible()
            return false
        }

        let desiredIdentifiers = Set(materialized.map(\.logical.identifier))
        let staleIdentifiers = pending.compactMap { item -> String? in
            switch NotificationIdentifierCodec().classify(item.identifier) {
            case .currentOneShot, .currentRepeating, .appOwnedStale:
                desiredIdentifiers.contains(item.identifier) ? nil : item.identifier
            case .unrelated:
                nil
            }
        }
        if !staleIdentifiers.isEmpty {
            await notificationCenter.removePendingNotificationRequests(
                withIdentifiers: staleIdentifiers
            )
        }

        var crossedBoundary = false
        var successfulAdds: Set<String> = []
        var inspectedNextTriggerDates: [String: Date] = [:]
        for value in materialized {
            let dispatchNow = clock.now()
            guard let inspection = triggerInspector(value.request) else {
                markError(value.logical.contributingGroupIDs, outcomes: &outcomes)
                continue
            }

            switch value.logical.payload {
            case .oneShot(let alertInstant, _):
                guard alertInstant > dispatchNow else {
                    crossedBoundary = true
                    continue
                }
                guard !inspection.repeats, inspection.nextTriggerDate == alertInstant else {
                    markError(value.logical.contributingGroupIDs, outcomes: &outcomes)
                    continue
                }
                inspectedNextTriggerDates[value.logical.identifier] = alertInstant
            case .repeating:
                guard inspection.repeats, let nextTriggerDate = inspection.nextTriggerDate else {
                    markError(value.logical.contributingGroupIDs, outcomes: &outcomes)
                    continue
                }
                inspectedNextTriggerDates[value.logical.identifier] = nextTriggerDate
            }

            do {
                try await notificationCenter.add(value.request)
                successfulAdds.insert(value.logical.identifier)
            } catch {
                markError(value.logical.contributingGroupIDs, outcomes: &outcomes)
            }
        }

        let pendingDesired = Set(pending.map(\.identifier)).intersection(desiredIdentifiers)
        let pendingOrAdded = pendingDesired.union(successfulAdds)
        let publishedNextTriggerDates = inspectedNextTriggerDates.filter {
            pendingOrAdded.contains($0.key)
        }
        await stateStore.publish(
            deviceNotificationsEnabled: deviceEnabled,
            authorization: authorization,
            outcomes: outcomes,
            scheduledThrough: logicalPlan.scheduledThrough,
            materializedKinds: materializedKinds,
            nextTriggerDates: publishedNextTriggerDates,
            pendingOrAddedIdentifiers: pendingOrAdded
        )

        if outcomes.values.contains(.unscheduledError) {
            scheduleRetryIfPossible()
        } else {
            invalidateRetryTimer()
            retryAttempt = 0
        }
        if crossedBoundary {
            invalidateForegroundTimer()
        } else {
            scheduleForegroundReplenishment(for: materialized)
        }
        return crossedBoundary
    }

    private func markError(
        _ groups: Set<AlertGroupID>,
        outcomes: inout [AlertGroupID: AlertGroupSchedulingOutcome]
    ) {
        for group in groups {
            outcomes[group] = .unscheduledError
        }
    }

    private func scheduleRetryIfPossible() {
        guard isForeground,
            retryTask == nil,
            retryAttempt < retryDelays.count
        else {
            return
        }
        let delay = retryDelays[retryAttempt]
        retryAttempt += 1
        retryTimerToken &+= 1
        let token = retryTimerToken
        retryTask = Task { [weak self, clock] in
            do {
                try await clock.sleep(delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.retryTimerFired(token: token)
        }
    }

    private func retryTimerFired(token: UInt64) {
        guard !Task.isCancelled,
            isForeground,
            token == retryTimerToken
        else {
            return
        }
        retryTimerToken &+= 1
        retryTask = nil
        enqueue(.foreground)
    }

    private func scheduleForegroundReplenishment(for requests: [MaterializedRequest]) {
        invalidateForegroundTimer()
        guard isForeground,
            let alertInstant = requests.compactMap(\.logical.oneShotAlertInstant).min()
        else {
            return
        }
        let target = alertInstant.addingTimeInterval(1)
        let delay = max(0, target.timeIntervalSince(clock.now()))
        let token = foregroundTimerToken
        foregroundTimerTask = Task { [weak self, clock] in
            do {
                try await clock.sleep(delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.foregroundTimerFired(token: token)
        }
    }

    private func foregroundTimerFired(token: UInt64) {
        guard !Task.isCancelled,
            isForeground,
            token == foregroundTimerToken
        else {
            return
        }
        foregroundTimerToken &+= 1
        foregroundTimerTask = nil
        enqueue(.foreground)
    }

    private func invalidateRetryTimer() {
        retryTimerToken &+= 1
        retryTask?.cancel()
        retryTask = nil
    }

    private func invalidateForegroundTimer() {
        foregroundTimerToken &+= 1
        foregroundTimerTask?.cancel()
        foregroundTimerTask = nil
    }
}

extension ReconcileReason {
    fileprivate var observesModelChange: Bool {
        switch self {
        case .reminderSaved, .reminderDeleted, .modelChanged, .deviceSettingsChanged:
            true
        case .foreground:
            false
        }
    }
}
