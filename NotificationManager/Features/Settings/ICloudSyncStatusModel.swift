import CloudKit
import CoreData
import Foundation
import Observation

enum ICloudAccountAvailability: Sendable, Equatable {
    case checking
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine

    init(cloudKitStatus: CKAccountStatus) {
        switch cloudKitStatus {
        case .available:
            self = .available
        case .noAccount:
            self = .noAccount
        case .restricted:
            self = .restricted
        case .temporarilyUnavailable:
            self = .temporarilyUnavailable
        case .couldNotDetermine:
            self = .couldNotDetermine
        @unknown default:
            self = .couldNotDetermine
        }
    }
}

enum ICloudSyncActivity: Sendable, Equatable {
    case notObserved
    case inProgress
    case succeeded
    case failed
}

struct ICloudSyncEvent: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case setup
        case `import`
        case export
        case other
    }

    let identifier: UUID
    let kind: Kind
    let endDate: Date?
    let succeeded: Bool

    init(
        identifier: UUID,
        kind: Kind,
        endDate: Date?,
        succeeded: Bool
    ) {
        self.identifier = identifier
        self.kind = kind
        self.endDate = endDate
        self.succeeded = succeeded
    }

    init(_ event: NSPersistentCloudKitContainer.Event) {
        identifier = event.identifier
        switch event.type {
        case .setup:
            kind = .setup
        case .import:
            kind = .import
        case .export:
            kind = .export
        @unknown default:
            kind = .other
        }
        endDate = event.endDate
        succeeded = event.succeeded
    }
}

@MainActor
@Observable
final class ICloudSyncStatusModel {
    typealias AccountStatus = @MainActor @Sendable () async throws -> ICloudAccountAvailability

    private(set) var accountAvailability: ICloudAccountAvailability
    private(set) var syncActivity: ICloudSyncActivity

    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private let accountStatus: AccountStatus
    @ObservationIgnored private var activeEventIdentifiers: Set<UUID> = []
    @ObservationIgnored private var latestOutcome: ICloudSyncActivity?
    @ObservationIgnored private var latestOutcomeDate: Date?
    @ObservationIgnored private var observationTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var accountRefreshGeneration: UInt64 = 0
    @ObservationIgnored private var hasStarted = false

    init(
        accountAvailability: ICloudAccountAvailability = .checking,
        syncActivity: ICloudSyncActivity = .notObserved,
        notificationCenter: NotificationCenter = .default,
        accountStatus: @escaping AccountStatus = {
            let status = try await CKContainer.default().accountStatus()
            return ICloudAccountAvailability(cloudKitStatus: status)
        }
    ) {
        self.accountAvailability = accountAvailability
        self.syncActivity = syncActivity
        self.notificationCenter = notificationCenter
        self.accountStatus = accountStatus
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        observationTokens.append(
            notificationCenter.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard
                    let event = notification.userInfo?[
                        NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                    ] as? NSPersistentCloudKitContainer.Event
                else {
                    return
                }
                let snapshot = ICloudSyncEvent(event)
                Task { @MainActor [weak self] in
                    self?.receive(snapshot)
                }
            })
        observationTokens.append(
            notificationCenter.addObserver(
                forName: .CKAccountChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refreshAccountAvailability()
                }
            })

        Task { @MainActor [weak self] in
            await self?.refreshAccountAvailability()
        }
    }

    func refreshAccountAvailability() async {
        accountRefreshGeneration &+= 1
        let generation = accountRefreshGeneration
        let availability: ICloudAccountAvailability
        do {
            availability = try await accountStatus()
        } catch {
            availability = .couldNotDetermine
        }
        guard generation == accountRefreshGeneration else { return }
        accountAvailability = availability
    }

    func receive(_ event: ICloudSyncEvent) {
        guard let endDate = event.endDate else {
            activeEventIdentifiers.insert(event.identifier)
            syncActivity = .inProgress
            return
        }

        activeEventIdentifiers.remove(event.identifier)
        if latestOutcomeDate.map({ endDate >= $0 }) ?? true {
            latestOutcomeDate = endDate
            latestOutcome = event.succeeded ? .succeeded : .failed
        }
        syncActivity = activeEventIdentifiers.isEmpty ? latestOutcome ?? .notObserved : .inProgress
    }
}
