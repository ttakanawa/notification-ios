@preconcurrency import ActivityKit
import Foundation
import Network
import NotificationManagerWidgetSupport
import OSLog

/// Coalesces refresh requests across suspension points without applying snapshots out of order.
@MainActor
final class ReminderLiveActivityRemoteRefreshGate {
    private var running = false
    private var requested = false

    func run(_ refresh: @MainActor () async -> Void) async {
        requested = true
        guard !running else { return }
        running = true
        defer { running = false }
        while requested {
            requested = false
            await refresh()
        }
    }
}

@MainActor
final class ReminderLiveActivityRemoteCoordinator {
    typealias Authorization = @MainActor @Sendable (ReminderLiveActivityEvent) async -> Bool

    private let outbox: LiveActivityEndOutbox?
    private let monitor = NWPathMonitor()
    private let logger = Logger(subsystem: "org.tknw.punctual", category: "LiveActivityEndAPI")
    private var events: [String: ReminderLiveActivityEvent] = [:]
    private var authorization: Authorization = { _ in false }
    private var generation: UInt64 = 0
    private var tokenTasks: [String: Task<Void, Never>] = [:]
    private var stateTasks: [String: Task<Void, Never>] = [:]
    private var activitiesTask: Task<Void, Never>?
    private var retryNotificationsTask: Task<Void, Never>?
    private var started = false
    private let refreshGate = ReminderLiveActivityRemoteRefreshGate()

    init(outbox: LiveActivityEndOutbox? = nil) {
        self.outbox = outbox
    }

    deinit {
        monitor.cancel()
        activitiesTask?.cancel()
        retryNotificationsTask?.cancel()
        for task in tokenTasks.values { task.cancel() }
        for task in stateTasks.values { task.cancel() }
    }

    func publish(
        events: [ReminderLiveActivityEvent], authorization: @escaping Authorization
    ) async {
        generation &+= 1
        self.events = Dictionary(
            events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.authorization = authorization
        start()
        await refresh()
    }

    private func start() {
        guard !started else { return }
        started = true
        activitiesTask = Task { [weak self] in
            for await activity in Activity<ReminderActivityAttributes>.activityUpdates {
                guard !Task.isCancelled else { return }
                self?.watch(activity)
                await self?.refresh()
            }
        }
        retryNotificationsTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: LiveActivityEndOutbox.reconciliationNeeded
            ).map { _ in () }
            for await _ in notifications {
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in await self?.refresh() }
        }
        monitor.start(queue: DispatchQueue(label: "org.tknw.punctual.end-api-connectivity"))
    }

    private func watch(_ activity: Activity<ReminderActivityAttributes>) {
        let id = activity.id
        if tokenTasks[id] == nil {
            tokenTasks[id] = Task { [weak self] in
                for await _ in activity.pushTokenUpdates {
                    guard !Task.isCancelled else { return }
                    await self?.refresh()
                }
            }
        }
        if stateTasks[id] == nil {
            stateTasks[id] = Task { [weak self] in
                for await _ in activity.activityStateUpdates {
                    guard !Task.isCancelled else { return }
                    await self?.refresh()
                }
            }
        }
    }

    private func refresh() async {
        await refreshGate.run { await self.refreshSnapshot() }
    }

    private func refreshSnapshot() async {
        let activeOutbox: LiveActivityEndOutbox?
        if let outbox {
            activeOutbox = outbox
        } else {
            activeOutbox = await LiveActivityEndRuntime.shared.outbox()
        }
        guard let outbox = activeOutbox else { return }
        let revision = generation
        let authorize = authorization
        var observations: [LiveActivityEndObservation] = []
        let activities = Activity<ReminderActivityAttributes>.activities
        for activity in activities {
            guard activity.activityState != .ended, activity.activityState != .dismissed,
                let event = events[activity.attributes.eventID]
            else { continue }
            watch(activity)
            let permitted = await authorize(event)
            // A watcher can be cancelled while it owns this drain; queued refreshes
            // still need to apply the coordinator's current generation.
            guard generation == revision else { return }
            let token = activity.pushToken.map(LiveActivityEndAPISigning.hex)
            observations.append(
                LiveActivityEndObservation(
                    activityID: activity.id, event: event, pushToken: token,
                    cloudCommitted: permitted))
        }
        guard generation == revision else { return }
        do {
            try await outbox.reconcile(observations)
            Task { await outbox.flush() }
        } catch {
            logger.error("Unable to persist the Live Activity end outbox")
        }
        let liveIDs = Set(observations.map(\.activityID))
        for id in Array(tokenTasks.keys) where !liveIDs.contains(id) {
            tokenTasks.removeValue(forKey: id)?.cancel()
            stateTasks.removeValue(forKey: id)?.cancel()
        }
    }
}
