#if DEBUG
import CloudKit
import CoreData
import Foundation
import NotificationManagerPersistence
import SwiftData
import _SwiftData_CoreData

@MainActor
protocol DebugCloudKitSchemaSession: AnyObject {
    func loadPersistentStoreSynchronously() throws
    func initializeCloudKitSchema() throws
    func removePersistentStore() throws
}

@MainActor
struct DebugCloudKitSchemaBootstrapper {
    static let launchArgument = "-initialize-cloudkit-schema"

    typealias SessionFactory = @MainActor (ModelConfiguration) throws ->
        any DebugCloudKitSchemaSession

    private let arguments: [String]
    private let makeSession: SessionFactory

    init(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        makeSession: @escaping SessionFactory = {
            try SystemDebugCloudKitSchemaSession(configuration: $0)
        }
    ) {
        self.arguments = arguments
        self.makeSession = makeSession
    }

    func initializeIfRequested(configuration: ModelConfiguration) throws {
        guard arguments.contains(Self.launchArgument) else { return }
        try autoreleasepool {
            try runSession(configuration: configuration)
        }
    }

    private func runSession(configuration: ModelConfiguration) throws {
        let session = try makeSession(configuration)
        try session.loadPersistentStoreSynchronously()
        var cleanupFailure: (any Error)?
        do {
            defer {
                do {
                    try session.removePersistentStore()
                } catch {
                    cleanupFailure = error
                }
            }
            try session.initializeCloudKitSchema()
        } catch {
            // Schema initialization is the primary operation. Preserve that error if the
            // best-effort unload also fails so diagnostics do not hide the root cause.
            throw error
        }
        if let cleanupFailure {
            throw cleanupFailure
        }
    }
}

private enum DebugCloudKitSchemaError: Error {
    case managedObjectModelUnavailable
    case cloudKitContainerIdentifierUnavailable
    case storeLoadDidNotComplete
}

@MainActor
private final class SystemDebugCloudKitSchemaSession: DebugCloudKitSchemaSession {
    private let container: NSPersistentCloudKitContainer

    init(configuration: ModelConfiguration) throws {
        guard let managedObjectModel = NSManagedObjectModel.makeManagedObjectModel(
            for: NotificationManagerSchemaV1.models
        ) else {
            throw DebugCloudKitSchemaError.managedObjectModelUnavailable
        }
        let identifier = configuration.cloudKitContainerIdentifier
            ?? CKContainer.default().containerIdentifier
        guard let identifier else {
            throw DebugCloudKitSchemaError.cloudKitContainerIdentifierUnavailable
        }

        container = NSPersistentCloudKitContainer(
            name: configuration.name,
            managedObjectModel: managedObjectModel
        )
        let description = NSPersistentStoreDescription(url: configuration.url)
        description.shouldAddStoreAsynchronously = false
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: identifier
        )
        container.persistentStoreDescriptions = [description]
    }

    func loadPersistentStoreSynchronously() throws {
        let result = PersistentStoreLoadResult()
        container.loadPersistentStores { _, error in
            result.complete(error: error)
        }
        guard result.didComplete else {
            throw DebugCloudKitSchemaError.storeLoadDidNotComplete
        }
        if let error = result.error {
            throw error
        }
    }

    func initializeCloudKitSchema() throws {
        try container.initializeCloudKitSchema(options: [])
    }

    func removePersistentStore() throws {
        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            try coordinator.remove(store)
        }
    }
}

private final class PersistentStoreLoadResult: @unchecked Sendable {
    private let lock = NSLock()
    private var completionState: (didComplete: Bool, error: (any Error)?) = (false, nil)

    var didComplete: Bool {
        lock.withLock { completionState.didComplete }
    }

    var error: (any Error)? {
        lock.withLock { completionState.error }
    }

    func complete(error: (any Error)?) {
        lock.withLock {
            completionState = (true, error)
        }
    }
}
#endif
