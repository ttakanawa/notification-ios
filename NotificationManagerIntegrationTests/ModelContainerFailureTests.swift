import Foundation
import NotificationManagerApplication
import NotificationManagerPersistence
import SwiftData
import Testing

@testable import NotificationManager

@Suite("Model container failure recovery")
struct ModelContainerFailureTests {
    @MainActor
    @Test func failedContainerOpenDoesNotDeleteOverwriteOrRecreateTheStore() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "ModelContainerFailureTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "NotificationManager.store")
        let original = Data("existing-store-bytes".utf8)
        try original.write(to: storeURL)
        let configuration = ModelContainerFactory.productionConfiguration(url: storeURL)
        let root = PersistenceCompositionRoot(
            configuration: configuration,
            makeContainer: { _ in throw ContainerFailureTestError.openFailed },
            makeEnvironment: { _ in AppEnvironment() }
        )

        #expect(throws: ContainerFailureTestError.openFailed) {
            _ = try root.open()
        }

        #expect(FileManager.default.fileExists(atPath: storeURL.path))
        #expect(try Data(contentsOf: storeURL) == original)
    }

    @MainActor
    @Test func bootstrapFailureRetainsPendingRequestsUntilAnExplicitRecoveryAction() async {
        let cleaner = FailurePendingCleaner()
        let bootstrapper = AppBootstrapper(
            notificationDelegate: NotificationApplicationDelegate(
                eligibilityIndexStore: ForegroundEligibilityIndexStore(),
                installHandler: { _, _ in }
            ),
            openEnvironment: { throw ContainerFailureTestError.openFailed },
            makeDataUnavailableActions: { retry in
                DataUnavailableActions(
                    preferenceStore: FailurePreferenceStore(enabled: true),
                    authorizationProvider: FailureAuthorizationController(),
                    authorizationRequester: FailureAuthorizationController(),
                    pendingCleaner: cleaner,
                    retry: retry
                )
            }
        )

        await bootstrapper.start()

        guard case .dataUnavailable(let actions) = bootstrapper.state else {
            Issue.record("Container failure should expose store-independent actions")
            return
        }
        #expect(await cleaner.callCount == 0)
        await actions.removeAllPending()
        #expect(await cleaner.callCount == 1)
    }

    #if DEBUG
        @MainActor
        @Test func explicitDebugSchemaBootstrapReleasesCoreDataBeforeSwiftDataOpen() {
            let trace = DebugSchemaTrace()
            let configuration = ModelContainerFactory.productionConfiguration(
                url: URL(fileURLWithPath: "/private/tmp/debug-schema-order.store")
            )
            let bootstrapper = DebugCloudKitSchemaBootstrapper(
                arguments: [DebugCloudKitSchemaBootstrapper.launchArgument],
                makeSession: { received in
                    trace.record(.sessionCreated)
                    #expect(received.url == configuration.url)
                    #expect(received.name == configuration.name)
                    #expect(
                        received.cloudKitContainerIdentifier
                            == configuration.cloudKitContainerIdentifier
                    )
                    return DebugSchemaSessionSpy(trace: trace)
                }
            )
            let root = PersistenceCompositionRoot(
                configuration: configuration,
                debugSchemaBootstrapper: bootstrapper,
                makeContainer: { _ in
                    trace.record(.swiftDataOpenStarted)
                    throw ContainerFailureTestError.stopAfterTrace
                },
                makeEnvironment: { _ in AppEnvironment() }
            )

            #expect(throws: ContainerFailureTestError.stopAfterTrace) {
                _ = try root.open()
            }
            #expect(
                trace.events == [
                    .sessionCreated,
                    .storeLoadedSynchronously,
                    .schemaInitialized,
                    .storeRemoved,
                    .sessionReleased,
                    .swiftDataOpenStarted
                ])
        }

        @MainActor
        @Test func debugSchemaBootstrapRequiresTheExplicitLaunchArgument() throws {
            let trace = DebugSchemaTrace()
            let bootstrapper = DebugCloudKitSchemaBootstrapper(
                arguments: ["-ordinary-debug-launch"],
                makeSession: { _ in
                    trace.record(.sessionCreated)
                    return DebugSchemaSessionSpy(trace: trace)
                }
            )

            try bootstrapper.initializeIfRequested(
                configuration: ModelContainerFactory.productionConfiguration(
                    url: URL(fileURLWithPath: "/private/tmp/debug-schema-not-requested.store")
                )
            )

            #expect(trace.events.isEmpty)
        }

        @MainActor
        @Test func schemaFailureStillUnloadsStoreAndPreservesThePrimaryError() {
            let trace = DebugSchemaTrace()
            let bootstrapper = DebugCloudKitSchemaBootstrapper(
                arguments: [DebugCloudKitSchemaBootstrapper.launchArgument],
                makeSession: { _ in
                    DebugSchemaSessionSpy(
                        trace: trace,
                        initializeError: .schemaInitializationFailed,
                        removeError: .storeRemovalFailed
                    )
                }
            )

            #expect(throws: ContainerFailureTestError.schemaInitializationFailed) {
                try bootstrapper.initializeIfRequested(
                    configuration: ModelContainerFactory.productionConfiguration(
                        url: URL(fileURLWithPath: "/private/tmp/debug-schema-failure.store")
                    )
                )
            }
            #expect(
                trace.events == [
                    .storeLoadedSynchronously,
                    .schemaInitialized,
                    .storeRemoved,
                    .sessionReleased
                ])
        }
    #endif
}

private enum ContainerFailureTestError: Error, Equatable {
    case openFailed
    case stopAfterTrace
    case schemaInitializationFailed
    case storeRemovalFailed
}

private actor FailurePreferenceStore: DeviceNotificationPreferenceStore {
    private var enabled: Bool

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func isEnabled() -> Bool { enabled }
    func setEnabled(_ enabled: Bool) { self.enabled = enabled }
}

private actor FailureAuthorizationController:
    NotificationAuthorizationProviding,
    NotificationAuthorizationRequesting
{
    func currentAuthorization() -> NotificationAuthorizationSnapshot {
        NotificationAuthorizationSnapshot(state: .allowed, diagnostic: nil)
    }

    func requestAuthorization() throws -> Bool { true }
}

private actor FailurePendingCleaner: PendingAppNotificationCleaning {
    private(set) var callCount = 0

    func removeAllPendingAppNotificationsReportingFailure() throws {
        callCount += 1
    }
}

#if DEBUG
    @MainActor
    private final class DebugSchemaTrace {
        private(set) var events: [DebugSchemaTraceEvent] = []

        func record(_ event: DebugSchemaTraceEvent) {
            events.append(event)
        }
    }

    private enum DebugSchemaTraceEvent: Equatable {
        case sessionCreated
        case storeLoadedSynchronously
        case schemaInitialized
        case storeRemoved
        case sessionReleased
        case swiftDataOpenStarted
    }

    @MainActor
    private final class DebugSchemaSessionSpy: DebugCloudKitSchemaSession {
        private let trace: DebugSchemaTrace
        private let initializeError: ContainerFailureTestError?
        private let removeError: ContainerFailureTestError?

        init(
            trace: DebugSchemaTrace,
            initializeError: ContainerFailureTestError? = nil,
            removeError: ContainerFailureTestError? = nil
        ) {
            self.trace = trace
            self.initializeError = initializeError
            self.removeError = removeError
        }

        func loadPersistentStoreSynchronously() throws {
            trace.record(.storeLoadedSynchronously)
        }

        func initializeCloudKitSchema() throws {
            trace.record(.schemaInitialized)
            if let initializeError { throw initializeError }
        }

        func removePersistentStore() throws {
            trace.record(.storeRemoved)
            if let removeError { throw removeError }
        }

        deinit {
            MainActor.assumeIsolated {
                trace.record(.sessionReleased)
            }
        }
    }
#endif
