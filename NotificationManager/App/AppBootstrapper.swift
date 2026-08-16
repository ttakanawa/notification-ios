import Observation

#if canImport(UIKit)
    import NotificationManagerPersistence
#endif

enum AppBootstrapState {
    case loading
    case ready(AppEnvironment)
    case dataUnavailable(DataUnavailableActions)
}

@MainActor
@Observable
final class AppBootstrapper {
    typealias EnvironmentOpener = @MainActor @Sendable () async throws -> AppEnvironment
    typealias FailureActionsFactory =
        @MainActor @Sendable (
            @escaping @MainActor @Sendable () async -> Void
        ) -> DataUnavailableActions

    private(set) var state: AppBootstrapState = .loading

    @ObservationIgnored private let notificationDelegate: NotificationApplicationDelegate
    @ObservationIgnored private let openEnvironment: EnvironmentOpener
    @ObservationIgnored private let makeDataUnavailableActions: FailureActionsFactory
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var attemptGeneration: UInt64 = 0
    @ObservationIgnored private var attemptTask: Task<AttemptResult, Never>?

    init(
        notificationDelegate: NotificationApplicationDelegate,
        openEnvironment: @escaping EnvironmentOpener,
        makeDataUnavailableActions: @escaping FailureActionsFactory
    ) {
        self.notificationDelegate = notificationDelegate
        self.openEnvironment = openEnvironment
        self.makeDataUnavailableActions = makeDataUnavailableActions
    }

    #if canImport(UIKit)
        static func production(
            notificationDelegate: NotificationApplicationDelegate
        ) -> AppBootstrapper {
            let preferenceStore = UserDefaultsNotificationPreferenceStore()
            let authorizationService = NotificationAuthorizationService()
            let notificationCenter = SystemNotificationCenterClient()
            let cleanupService = NotificationCleanupService(
                notificationCenter: notificationCenter
            )
            let compositionRoot = PersistenceCompositionRoot(
                makeEnvironment: { container in
                    AppEnvironment.production(
                        container: container,
                        notificationDelegate: notificationDelegate,
                        preferenceStore: preferenceStore,
                        authorizationService: authorizationService,
                        notificationCenter: notificationCenter,
                        cleanupService: cleanupService
                    )
                }
            )
            return AppBootstrapper(
                notificationDelegate: notificationDelegate,
                openEnvironment: {
                    try compositionRoot.open()
                },
                makeDataUnavailableActions: { retry in
                    DataUnavailableActions(
                        preferenceStore: preferenceStore,
                        authorizationProvider: authorizationService,
                        authorizationRequester: authorizationService,
                        pendingCleaner: cleanupService,
                        retry: retry
                    )
                }
            )
        }
    #endif

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        notificationDelegate.install()
        await beginAttempt()
    }

    func retry() async {
        switch state {
        case .loading, .dataUnavailable:
            await beginAttempt()
        case .ready:
            return
        }
    }

    private func beginAttempt() async {
        attemptGeneration &+= 1
        let generation = attemptGeneration
        attemptTask?.cancel()
        let openEnvironment = self.openEnvironment
        let task = Task { @MainActor in
            do {
                return AttemptResult.success(try await openEnvironment())
            } catch {
                return AttemptResult.failure
            }
        }
        attemptTask = task
        let result = await task.value
        guard generation == attemptGeneration else { return }
        attemptTask = nil

        switch result {
        case .success(let environment):
            environment.activateNotificationHandling()
            state = .ready(environment)
        case .failure:
            state = .dataUnavailable(
                makeDataUnavailableActions { [weak self] in
                    await self?.retry()
                })
        }
    }
}

private enum AttemptResult {
    case success(AppEnvironment)
    case failure
}
