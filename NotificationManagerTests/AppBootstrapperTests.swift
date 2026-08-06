import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import Testing
import UserNotifications
@testable import NotificationManager

@Suite("App bootstrap")
struct AppBootstrapperTests {
    @MainActor
    @Test func notificationDelegateAndCategoriesAreInstalledBeforeContainerOpen() async {
        let trace = BootstrapTraceRecorder()
        let delegate = NotificationApplicationDelegate(
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            installHandler: { _, categories in
                trace.record(.notificationDelegateInstalled)
                #expect(categories.map(\.identifier) == [
                    NotificationApplicationDelegate.openLinkCategoryIdentifier
                ])
            }
        )
        let bootstrapper = AppBootstrapper(
            notificationDelegate: delegate,
            openEnvironment: {
                trace.record(.containerOpenStarted)
                throw BootstrapTestError.storeUnavailable
            },
            makeDataUnavailableActions: { retry in
                DataUnavailableActions(
                    preferenceStore: BootstrapPreferenceStore(),
                    authorizationProvider: BootstrapAuthorizationController(),
                    authorizationRequester: BootstrapAuthorizationController(),
                    pendingCleaner: BootstrapPendingCleaner(),
                    retry: retry
                )
            }
        )

        await bootstrapper.start()

        #expect(trace.events == [
            .notificationDelegateInstalled,
            .containerOpenStarted
        ])
        guard case .dataUnavailable = bootstrapper.state else {
            Issue.record("A failed store open must publish the recovery state")
            return
        }
    }

    @MainActor
    @Test func startIsOneShotAfterTheInitialAttemptCompletes() async {
        let attempts = BootstrapAttemptCounter()
        let bootstrapper = AppBootstrapper(
            notificationDelegate: NotificationApplicationDelegate(
                eligibilityIndexStore: ForegroundEligibilityIndexStore(),
                installHandler: { _, _ in }
            ),
            openEnvironment: {
                attempts.increment()
                throw BootstrapTestError.storeUnavailable
            },
            makeDataUnavailableActions: { retry in
                DataUnavailableActions(
                    preferenceStore: BootstrapPreferenceStore(),
                    authorizationProvider: BootstrapAuthorizationController(),
                    authorizationRequester: BootstrapAuthorizationController(),
                    pendingCleaner: BootstrapPendingCleaner(),
                    retry: retry
                )
            }
        )

        await bootstrapper.start()
        await bootstrapper.start()

        #expect(attempts.value == 1)
    }

    @MainActor
    @Test func staleFailureCannotReplaceANewerSuccessfulRetry() async {
        let gate = BootstrapAttemptGate()
        let freshEnvironment = AppEnvironment()
        let bootstrapper = makeBootstrapper {
            let attempt = await gate.begin()
            try await gate.wait(attempt)
            return freshEnvironment
        }

        let original = Task { @MainActor in await bootstrapper.start() }
        await gate.waitForAttempts(1)
        let retry = Task { @MainActor in await bootstrapper.retry() }
        await gate.waitForAttempts(2)

        await gate.resolve(2)
        await retry.value
        guard case let .ready(environment) = bootstrapper.state else {
            Issue.record("The newer retry should make the environment ready")
            return
        }
        #expect(environment === freshEnvironment)

        await gate.reject(1)
        await original.value
        guard case let .ready(environment) = bootstrapper.state else {
            Issue.record("A stale failure must not replace the newer success")
            return
        }
        #expect(environment === freshEnvironment)
    }

    @MainActor
    @Test func staleSuccessCannotReplaceANewerFailedRetry() async {
        let gate = BootstrapAttemptGate()
        let staleEnvironment = AppEnvironment()
        let bootstrapper = makeBootstrapper {
            let attempt = await gate.begin()
            try await gate.wait(attempt)
            return staleEnvironment
        }

        let original = Task { @MainActor in await bootstrapper.start() }
        await gate.waitForAttempts(1)
        let retry = Task { @MainActor in await bootstrapper.retry() }
        await gate.waitForAttempts(2)

        await gate.reject(2)
        await retry.value
        guard case .dataUnavailable = bootstrapper.state else {
            Issue.record("The newer failed retry should publish recovery")
            return
        }

        await gate.resolve(1)
        await original.value
        guard case .dataUnavailable = bootstrapper.state else {
            Issue.record("A stale success must not replace the newer failure")
            return
        }
    }

    @MainActor
    @Test func onlyWinningEnvironmentActivatesAndDrainsTheQueuedResponse() async {
        let gate = BootstrapAttemptGate()
        let staleRoutes = BootstrapNotificationRouteRecorder()
        let winningRoutes = BootstrapNotificationRouteRecorder()
        let delegate = NotificationApplicationDelegate(
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            installHandler: { _, _ in },
            responseHandlingInitiallyBound: false
        )
        let staleEnvironment = AppEnvironment(notificationHandlingActivation: {
            staleRoutes.recordActivation()
            Self.bind(delegate, routes: staleRoutes)
        })
        let winningEnvironment = AppEnvironment(notificationHandlingActivation: {
            winningRoutes.recordActivation()
            Self.bind(delegate, routes: winningRoutes)
        })
        let bootstrapper = AppBootstrapper(
            notificationDelegate: delegate,
            openEnvironment: {
                let attempt = await gate.begin()
                try await gate.wait(attempt)
                return attempt == 1 ? staleEnvironment : winningEnvironment
            },
            makeDataUnavailableActions: makeBootstrapFailureActions
        )
        let completion = BootstrapNotificationCompletionRecorder()
        delegate.receiveResponse(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            categoryIdentifier: "",
            userInfo: [
                NotificationApplicationDelegate.reminderIDKey:
                    Self.reminderID.uuidString.lowercased()
            ],
            completion: { completion.record() }
        )

        let original = Task { @MainActor in await bootstrapper.start() }
        await gate.waitForAttempts(1)
        let retry = Task { @MainActor in await bootstrapper.retry() }
        await gate.waitForAttempts(2)

        await gate.resolve(2)
        await retry.value
        await winningRoutes.waitForDestinationCount(1)

        await gate.resolve(1)
        await original.value

        #expect(completion.count == 1)
        #expect(staleRoutes.activationCount == 0)
        #expect(staleRoutes.destinations.isEmpty)
        #expect(winningRoutes.activationCount == 1)
        #expect(winningRoutes.destinations == [.reminderDetail(Self.reminderID)])
    }

    @MainActor
    private func makeBootstrapper(
        openEnvironment: @escaping AppBootstrapper.EnvironmentOpener
    ) -> AppBootstrapper {
        AppBootstrapper(
            notificationDelegate: NotificationApplicationDelegate(
                eligibilityIndexStore: ForegroundEligibilityIndexStore(),
                installHandler: { _, _ in }
            ),
            openEnvironment: openEnvironment,
            makeDataUnavailableActions: { retry in
                DataUnavailableActions(
                    preferenceStore: BootstrapPreferenceStore(),
                    authorizationProvider: BootstrapAuthorizationController(),
                    authorizationRequester: BootstrapAuthorizationController(),
                    pendingCleaner: BootstrapPendingCleaner(),
                    retry: retry
                )
            }
        )
    }

    private static let reminderID = UUID(
        uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    )!

    @MainActor
    private static func bind(
        _ delegate: NotificationApplicationDelegate,
        routes: BootstrapNotificationRouteRecorder
    ) {
        delegate.bind(
            reminderLookup: { reminderID in
                ReminderSnapshot(
                    id: reminderID,
                    title: "Current",
                    notes: nil,
                    urlString: nil,
                    enabled: true,
                    schedule: .corrupt(originalData: Data([0xff])),
                    tagIDs: [],
                    createdAt: Date(timeIntervalSince1970: 1),
                    updatedAt: Date(timeIntervalSince1970: 2)
                )
            },
            routeResponse: { routes.record($0) },
            openURL: { _ in },
            reconcileAfterNotification: { _ in }
        )
    }
}

@MainActor
private func makeBootstrapFailureActions(
    retry: @escaping @MainActor @Sendable () async -> Void
) -> DataUnavailableActions {
    DataUnavailableActions(
        preferenceStore: BootstrapPreferenceStore(),
        authorizationProvider: BootstrapAuthorizationController(),
        authorizationRequester: BootstrapAuthorizationController(),
        pendingCleaner: BootstrapPendingCleaner(),
        retry: retry
    )
}

private enum BootstrapTraceEvent: Equatable {
    case notificationDelegateInstalled
    case containerOpenStarted
}

@MainActor
private final class BootstrapTraceRecorder {
    private(set) var events: [BootstrapTraceEvent] = []

    func record(_ event: BootstrapTraceEvent) {
        events.append(event)
    }
}

@MainActor
private final class BootstrapAttemptCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

@MainActor
private final class BootstrapNotificationRouteRecorder {
    private(set) var activationCount = 0
    private(set) var destinations: [NotificationResponseDestination] = []

    func recordActivation() {
        activationCount += 1
    }

    func record(_ destination: NotificationResponseDestination) {
        destinations.append(destination)
    }

    func waitForDestinationCount(_ count: Int) async {
        while destinations.count < count {
            await Task.yield()
        }
    }
}

private final class BootstrapNotificationCompletionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0

    var count: Int { lock.withLock { storedCount } }

    func record() {
        lock.withLock { storedCount += 1 }
    }
}

private enum BootstrapTestError: Error {
    case storeUnavailable
}

private actor BootstrapAttemptGate {
    private var nextAttempt = 0
    private var results: [Int: Result<Void, BootstrapTestError>] = [:]
    private var continuations: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var attemptWaiters: [CheckedContinuation<Void, Never>] = []

    func begin() -> Int {
        nextAttempt += 1
        let waiters = attemptWaiters
        attemptWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return nextAttempt
    }

    func wait(_ attempt: Int) async throws {
        if let result = results.removeValue(forKey: attempt) {
            return try result.get()
        }
        try await withCheckedThrowingContinuation { continuation in
            continuations[attempt] = continuation
        }
    }

    func waitForAttempts(_ count: Int) async {
        while nextAttempt < count {
            await withCheckedContinuation { continuation in
                attemptWaiters.append(continuation)
            }
        }
    }

    func resolve(_ attempt: Int) {
        if let continuation = continuations.removeValue(forKey: attempt) {
            continuation.resume()
        } else {
            results[attempt] = .success(())
        }
    }

    func reject(_ attempt: Int) {
        if let continuation = continuations.removeValue(forKey: attempt) {
            continuation.resume(throwing: BootstrapTestError.storeUnavailable)
        } else {
            results[attempt] = .failure(.storeUnavailable)
        }
    }
}

private actor BootstrapPreferenceStore: DeviceNotificationPreferenceStore {
    func isEnabled() -> Bool { false }
    func setEnabled(_ enabled: Bool) {}
}

private actor BootstrapAuthorizationController:
    NotificationAuthorizationProviding,
    NotificationAuthorizationRequesting
{
    func currentAuthorization() -> NotificationAuthorizationSnapshot {
        NotificationAuthorizationSnapshot(state: .notDetermined, diagnostic: nil)
    }

    func requestAuthorization() throws -> Bool { false }
}

private actor BootstrapPendingCleaner: PendingAppNotificationCleaning {
    func removeAllPendingAppNotificationsReportingFailure() throws {}
}
