import CoreData
import Foundation
import NotificationManagerApplication
#if canImport(UIKit)
import UIKit
#endif

enum AppLifecycleTrigger: Sendable, Equatable {
    case launch
    case foreground
    case background
    case backgroundRefresh
    case notificationPresentationCompleted
    case notificationResponseCompleted
    case modelSnapshotChanged
    case significantTimeChanged
    case timeZoneChanged
    case localeChanged
    case authorizationOrPreferenceChanged
}

struct AppLifecycleNotificationNames: Sendable {
    let significantTimeChanged: Notification.Name
    let timeZoneChanged: Notification.Name
    let localeChanged: Notification.Name
    let modelImported: Notification.Name

    static let system = AppLifecycleNotificationNames(
        significantTimeChanged: platformSignificantTimeChangeNotification,
        timeZoneChanged: .NSSystemTimeZoneDidChange,
        localeChanged: NSLocale.currentLocaleDidChangeNotification,
        modelImported: .NSPersistentStoreRemoteChange
    )

    private static var platformSignificantTimeChangeNotification: Notification.Name {
        #if canImport(UIKit)
        UIApplication.significantTimeChangeNotification
        #else
        Notification.Name("notification-manager.significant-time-change")
        #endif
    }
}

@MainActor
final class AppLifecycleCoordinator {
    typealias Reconcile = @Sendable (ReconcileReason) async -> Void
    typealias AsyncAction = @Sendable () async -> Void

    private let eligibilityIndexStore: ForegroundEligibilityIndexStore
    private let notificationCenter: NotificationCenter
    private let notificationNames: AppLifecycleNotificationNames
    private let requestReconcile: Reconcile
    private let enterBackgroundAction: AsyncAction
    private let refreshDeviceState: AsyncAction
    private let refreshModelSnapshot: AsyncAction
    private var observerTokens: [NSObjectProtocol] = []
    private var sceneGeneration: UInt64 = 0
    private var sceneIsForeground = false

    init(
        eligibilityIndexStore: ForegroundEligibilityIndexStore,
        notificationCenter: NotificationCenter = .default,
        notificationNames: AppLifecycleNotificationNames = .system,
        requestReconcile: @escaping Reconcile,
        enterBackground: @escaping AsyncAction,
        refreshDeviceState: @escaping AsyncAction = {},
        refreshModelSnapshot: @escaping AsyncAction = {}
    ) {
        self.eligibilityIndexStore = eligibilityIndexStore
        self.notificationCenter = notificationCenter
        self.notificationNames = notificationNames
        self.requestReconcile = requestReconcile
        enterBackgroundAction = enterBackground
        self.refreshDeviceState = refreshDeviceState
        self.refreshModelSnapshot = refreshModelSnapshot
    }

    func handle(_ trigger: AppLifecycleTrigger) async {
        switch trigger {
        case .launch, .foreground:
            sceneIsForeground = true
            let generation = beginSceneTransition()
            eligibilityIndexStore.markStale()
            await refreshDeviceState()
            guard generation == sceneGeneration else { return }
            await refreshModelSnapshot()
            guard generation == sceneGeneration else { return }
            await requestReconcile(.foreground)
        case .background:
            sceneIsForeground = false
            _ = beginSceneTransition()
            await enterBackgroundAction()
        case .backgroundRefresh:
            sceneIsForeground = false
            let generation = beginSceneTransition()
            await enterBackgroundAction()
            guard generation == sceneGeneration else { return }
            eligibilityIndexStore.markStale()
            await refreshModelSnapshot()
            guard generation == sceneGeneration else { return }
            await requestReconcile(.modelChanged)
        case .notificationPresentationCompleted, .notificationResponseCompleted:
            guard sceneIsForeground else { return }
            await requestReconcile(.foreground)
        case .modelSnapshotChanged, .significantTimeChanged, .timeZoneChanged,
             .localeChanged:
            eligibilityIndexStore.markStale()
            await refreshModelSnapshot()
            await requestReconcile(.modelChanged)
        case .authorizationOrPreferenceChanged:
            eligibilityIndexStore.markStale()
            await refreshDeviceState()
            await refreshModelSnapshot()
            await requestReconcile(.deviceSettingsChanged)
        }
    }

    /// Executes reconciliation when the operating system has already granted background time.
    /// This entry point does not schedule work or promise that iOS will launch the process.
    func backgroundRefresh() async {
        await handle(.backgroundRefresh)
    }

    func startObservingSystemChanges() {
        guard observerTokens.isEmpty else { return }
        observe(notificationNames.significantTimeChanged, trigger: .significantTimeChanged)
        observe(notificationNames.timeZoneChanged, trigger: .timeZoneChanged)
        observe(notificationNames.localeChanged, trigger: .localeChanged)
        observe(notificationNames.modelImported, trigger: .modelSnapshotChanged)
    }

    func stopObservingSystemChanges() {
        observerTokens.forEach(notificationCenter.removeObserver)
        observerTokens.removeAll()
    }

    private func observe(
        _ name: Notification.Name,
        trigger: AppLifecycleTrigger
    ) {
        let eligibilityIndexStore = self.eligibilityIndexStore
        observerTokens.append(notificationCenter.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            eligibilityIndexStore.markStale()
            Task { @MainActor [weak self] in
                await self?.handle(trigger)
            }
        })
    }

    private func beginSceneTransition() -> UInt64 {
        sceneGeneration &+= 1
        return sceneGeneration
    }
}

@MainActor
enum AppEnvironmentStartSequence {
    typealias AsyncAction = @MainActor @Sendable () async -> Void

    static func run(
        startSchedulingStateObservation: AsyncAction,
        handleLaunch: AsyncAction
    ) async {
        await handleLaunch()
        await startSchedulingStateObservation()
    }
}

@MainActor
final class ModelImportChangeObserver<Fingerprint: Equatable & Sendable> {
    typealias ChangeHandler = @MainActor @Sendable () async -> Void

    private let changeHandler: ChangeHandler
    private var previousFingerprint: Fingerprint?

    init(changeHandler: @escaping ChangeHandler) {
        self.changeHandler = changeHandler
    }

    func observe(_ fingerprint: Fingerprint) async {
        guard previousFingerprint != fingerprint else { return }
        previousFingerprint = fingerprint
        await changeHandler()
    }
}
