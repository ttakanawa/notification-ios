import CloudKit
import CoreData
import Foundation
import NotificationManagerPersistence
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
    private(set) var isSyncEnabled = true
    private(set) var retainedPhase: RetainedSyncPhase?
    private(set) var recoveryCopies: [RetainedCloudRevision] = []
    private(set) var actionFailed = false
    @ObservationIgnored private let repository: RetainedReminderRepository?
    @ObservationIgnored private let cloudService: RetainedCloudSyncService?
    @ObservationIgnored private var retainedObservation: Task<Void, Never>?

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
        repository: RetainedReminderRepository? = nil,
        cloudService: RetainedCloudSyncService? = nil,
        accountAvailability: ICloudAccountAvailability = .checking,
        syncActivity: ICloudSyncActivity = .notObserved,
        notificationCenter: NotificationCenter = .default,
        accountStatus: @escaping AccountStatus = {
            let status = try await CKContainer.default().accountStatus()
            return ICloudAccountAvailability(cloudKitStatus: status)
        }
    ) {
        self.repository = repository
        self.cloudService = cloudService
        self.accountAvailability = accountAvailability
        self.syncActivity = syncActivity
        self.notificationCenter = notificationCenter
        self.accountStatus = accountStatus
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        if repository == nil {
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
        }
        if let repository {
            retainedObservation = Task { [weak self] in
                for await _ in await repository.changes() {
                    guard !Task.isCancelled else { return }
                    await self?.refreshRetainedStatus()
                }
            }
        }
        Task { await cloudService?.start() }
        observationTokens.append(
            notificationCenter.addObserver(
                forName: .CKAccountChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.cloudService?.suspendForAccountChange()
                    await self?.refreshAccountAvailability()
                }
            })

        Task { @MainActor [weak self] in
            await self?.refreshAccountAvailability()
        }
    }

    func setSyncEnabled(_ enabled: Bool) async {
        do {
            actionFailed = false
            if let cloudService {
                try await cloudService.setEnabled(enabled)
            } else if let repository {
                try await repository.setSyncEnabled(enabled)
            } else {
                isSyncEnabled = enabled
            }
        } catch { actionFailed = true }
        await refreshRetainedStatus()
    }

    func confirmAccount(_ accepted: Bool) async {
        do {
            actionFailed = false
            if let cloudService {
                try await cloudService.confirmAccount(accepted)
            } else {
                try await repository?.confirmAccount(accepted)
            }
        } catch { actionFailed = true }
        await refreshRetainedStatus()
    }

    func restore(_ revision: RetainedCloudRevision) async {
        do {
            actionFailed = false
            try await repository?.restoreRevision(revision.id)
        } catch { actionFailed = true }
        await refreshRetainedStatus()
    }

    private func refreshRetainedStatus() async {
        guard let repository else { return }
        let status = await repository.status()
        isSyncEnabled = status.isEnabled
        retainedPhase = status.phase
        recoveryCopies = await repository.recoveryRevisions()
        switch status.phase {
        case .off, .unavailable, .confirmationRequired: syncActivity = .notObserved
        case .checking: syncActivity = .inProgress
        case .failed: syncActivity = .failed
        case .syncing: syncActivity = status.pendingRevisionCount == 0 ? .succeeded : .inProgress
        }
    }

    func refreshAccountAvailability() async {
        await cloudService?.refresh()
        await refreshRetainedStatus()
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
        guard repository == nil else { return }
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
