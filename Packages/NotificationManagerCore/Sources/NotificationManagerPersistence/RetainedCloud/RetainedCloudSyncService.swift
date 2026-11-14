import CloudKit
import Foundation
import Network

/// Manual engine scheduling is deliberate: automatic account resumption must never
/// publish retained data before the app has checked identity and obtained consent.
public actor RetainedCloudSyncService: CKSyncEngineDelegate {
    public static let zoneName = "PunctualRetainedV1"
    public static let recordType = "PunctualRevisionV1"
    private let repository: RetainedReminderRepository
    private let container: CKContainer
    private let accountScope: String
    private let zoneID = CKRecordZone.ID(zoneName: zoneName)
    private var engine: CKSyncEngine?
    private var boundAccount: String?
    private var generation: UInt64 = 0
    private var synchronizing = false
    private var refreshRequested = false
    private var importSession: UUID?
    private var observation: Task<Void, Never>?
    private let networkMonitor = NWPathMonitor()
    private var lastScheduled: Set<UUID> = []

    public init(
        repository: RetainedReminderRepository, container: CKContainer, accountScope: String
    ) {
        self.repository = repository
        self.container = container
        self.accountScope = accountScope
    }

    public func start() async {
        if observation == nil {
            networkMonitor.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else { return }
                Task { await self?.refresh() }
            }
            networkMonitor.start(queue: DispatchQueue(label: "org.tknw.punctual.cloud-network"))
            let changes = await repository.changes()
            observation = Task { [weak self] in
                for await _ in changes {
                    guard let self, !Task.isCancelled else { return }
                    await self.localDataChanged()
                }
            }
        }
        await refresh()
    }

    public func setEnabled(_ enabled: Bool) async throws {
        try await repository.setSyncEnabled(enabled)
        await stopEngine()
        if enabled { await refresh() }
    }

    public func confirmAccount(_ accepted: Bool) async throws {
        try await repository.confirmAccount(accepted)
        if accepted { await refresh() } else { await stopEngine() }
    }

    /// Call on launch, resume, account notification, remote notification, or explicit retry.
    public func refresh() async {
        guard !synchronizing else {
            refreshRequested = true
            return
        }
        synchronizing = true
        defer {
            synchronizing = false
            if refreshRequested {
                refreshRequested = false
                Task { [weak self] in await self?.refresh() }
            } else {
                Task { [weak self] in await self?.localDataChanged() }
            }
        }
        var attempt = generation
        do {
            guard await repository.status().isEnabled else {
                await stopEngine()
                return
            }
            let availability = try await container.accountStatus()
            guard attempt == generation else { return }
            guard availability == .available else {
                await stopEngine()
                _ = try await repository.checkAccount(
                    nil,
                    systemUnavailable: availability == .noAccount || availability == .restricted
                )
                return
            }
            let user = try await container.userRecordID()
            let account = "\(accountScope)/\(user.recordName)"
            guard attempt == generation else { return }
            guard try await repository.checkAccount(account) else {
                await stopEngine()
                return
            }
            if engine == nil || boundAccount != account {
                await stopEngine()
                let state = await repository.engineState(account: account)
                let serialization = try state.map {
                    try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
                }
                var configuration = CKSyncEngine.Configuration(
                    database: container.privateCloudDatabase, stateSerialization: serialization,
                    delegate: self
                )
                configuration.automaticallySync = false
                boundAccount = account
                engine = CKSyncEngine(configuration)
            }
            guard let engine, boundAccount == account else { return }
            let activeGeneration = generation
            attempt = activeGeneration
            importSession = try await repository.beginCloudImport(account: account)
            try await importLegacyCloud(account: account, generation: activeGeneration)
            guard activeGeneration == generation else { return }
            _ = try await container.privateCloudDatabase.save(CKRecordZone(zoneID: zoneID))
            try await engine.fetchChanges(.init(scope: .zoneIDs([zoneID])))
            guard activeGeneration == generation, try await verifiedAccount() == account else {
                return
            }
            await finishImport()
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            let pending = await repository.pendingRevisions(account: account)
            lastScheduled = Set(pending.map(\.id))
            engine.state.add(
                pendingRecordZoneChanges: pending.map {
                    .saveRecord(CKRecord.ID(recordName: $0.id.uuidString, zoneID: zoneID))
                })
            try await engine.sendChanges(.init(scope: .zoneIDs([zoneID])))
        } catch {
            // No receipt is fabricated on an error. All revisions remain durable for retry.
            if attempt == generation { await repository.markSyncFailed() }
            await finishImport()
        }
    }

    private func finishImport() async {
        guard let session = importSession else { return }
        importSession = nil
        await repository.finishCloudImport(session)
    }

    public func suspendForAccountChange() async {
        _ = try? await repository.checkAccount(nil)
        await stopEngine()
        await refresh()
    }

    private func stopEngine() async {
        generation &+= 1
        await finishImport()
        let previous = engine
        engine = nil
        boundAccount = nil
        lastScheduled = []
        // Cancellation can complete after delegate events. Invalidate identity first and
        // avoid waiting for the engine from inside its own async delegate callback.
        Task { await previous?.cancelOperations() }
    }

    private func localDataChanged() async {
        guard !synchronizing, let account = boundAccount else { return }
        let pending = Set(await repository.pendingRevisions(account: account).map(\.id))
        guard !pending.isEmpty, pending != lastScheduled else { return }
        lastScheduled = pending
        await refresh()
    }

    private func verifiedAccount() async throws -> String? {
        guard try await container.accountStatus() == .available else { return nil }
        let user = try await container.userRecordID()
        return "\(accountScope)/\(user.recordName)"
    }

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard syncEngine === engine, let account = boundAccount else { return }
        do {
            switch event {
            case .accountChange(let change):
                switch change.changeType {
                case .signIn(let currentUser):
                    if "\(accountScope)/\(currentUser.recordName)" != account {
                        await suspendForAccountChange()
                    }
                case .signOut, .switchAccounts: await suspendForAccountChange()
                @unknown default: await suspendForAccountChange()
                }
            case .stateUpdate(let update):
                try await repository.saveEngineState(
                    JSONEncoder().encode(update.stateSerialization), account: account)
            case .fetchedRecordZoneChanges(let changes):
                guard try await verifiedAccount() == account, syncEngine === engine else { return }
                for modification in changes.modifications
                where modification.record.recordID.zoneID == zoneID {
                    let revision = try Self.revision(modification.record)
                    try await repository.importRevision(revision, account: account)
                }
            // Remote deletion never removes the only retained local copy. App deletions
            // use immutable tombstone revisions and thus retain conflicting local edits.
            case .sentRecordZoneChanges(let changes):
                guard try await verifiedAccount() == account, syncEngine === engine else { return }
                for record in changes.savedRecords {
                    try await repository.acknowledge(Self.revision(record), account: account)
                }
                for failed in changes.failedRecordSaves {
                    switch failed.error.code {
                    case .serverRecordChanged:
                        guard let server = failed.error.serverRecord,
                            try Self.revision(server) == Self.revision(failed.record)
                        else { throw RetainedStoreError.immutableRevisionCollision }
                        try await repository.acknowledge(Self.revision(server), account: account)
                    case .zoneNotFound:
                        syncEngine.state.add(pendingDatabaseChanges: [
                            .saveZone(CKRecordZone(zoneID: zoneID))
                        ])
                        syncEngine.state.add(pendingRecordZoneChanges: [
                            .saveRecord(failed.record.recordID)
                        ])
                    default: await repository.markSyncFailed()
                    }
                }
            case .fetchedDatabaseChanges(let changes):
                if changes.deletions.contains(where: { $0.zoneID == zoneID }) {
                    // A removed zone invalidates receipts. Keep all local content and require
                    // a fresh publication decision rather than acknowledging vanished data.
                    try await repository.invalidateReceipts(account: account)
                    await stopEngine()
                }
            case .sentDatabaseChanges(let changes):
                if !changes.failedZoneSaves.isEmpty { await repository.markSyncFailed() }
            default: break
            }
        } catch {
            // Prevent a later engine token checkpoint from skipping an unpersisted import.
            await repository.markSyncFailed()
            await stopEngine()
        }
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard syncEngine === engine, let account = boundAccount,
            (try? await verifiedAccount()) == account
        else { return nil }
        let pending = await repository.pendingRevisions(account: account)
        let requested = Set(
            syncEngine.state.pendingRecordZoneChanges.compactMap { change -> String? in
                guard context.options.scope.contains(change), case .saveRecord(let id) = change,
                    id.zoneID == zoneID
                else { return nil }
                return id.recordName
            })
        let selected = pending.filter { requested.contains($0.id.uuidString) }.prefix(100)
        let records = selected.compactMap { revision -> CKRecord? in
            guard let data = try? revision.encoded() else { return nil }
            let record = CKRecord(
                recordType: Self.recordType,
                recordID: CKRecord.ID(recordName: revision.id.uuidString, zoneID: zoneID)
            )
            record.encryptedValues["payload"] = data
            return record
        }
        return records.isEmpty ? nil : .init(recordsToSave: records, atomicByZone: false)
    }

    public func nextFetchChangesOptions(
        _ context: CKSyncEngine.FetchChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.FetchChangesOptions {
        .init(scope: .zoneIDs([zoneID]))
    }

    private static func revision(_ record: CKRecord) throws -> RetainedCloudRevision {
        guard record.recordType == recordType,
            let data = record.encryptedValues["payload"] as? Data
        else { throw RetainedStoreError.invalidRevision }
        let revision = try JSONDecoder().decode(RetainedCloudRevision.self, from: data)
        guard revision.id.uuidString == record.recordID.recordName else {
            throw RetainedStoreError.invalidRevision
        }
        return revision
    }

    private func importLegacyCloud(account: String, generation expected: UInt64) async throws {
        let database = container.privateCloudDatabase
        let zones = try await database.allRecordZones().filter {
            $0.zoneID.zoneName == "com.apple.coredata.cloudkit.zone"
        }
        for zone in zones {
            let data = await repository.legacyToken(account: account)
            var token = try data.flatMap {
                try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
            }
            var more = true
            var resetExpiredToken = false
            while more {
                let page: LegacyCloudPage
                do {
                    page = try await fetchLegacyPage(
                        database: database, zoneID: zone.zoneID, token: token)
                } catch let error as CKError where error.code == .changeTokenExpired {
                    guard !resetExpiredToken else { throw error }
                    resetExpiredToken = true
                    token = nil
                    continue
                }
                guard expected == generation, try await verifiedAccount() == account else {
                    throw RetainedStoreError.staleAccount
                }
                let tokenData = try NSKeyedArchiver.archivedData(
                    withRootObject: page.token, requiringSecureCoding: true
                )
                try await repository.importLegacyPage(
                    records: page.records, deletedNames: page.deletedNames,
                    token: tokenData, account: account
                )
                token = page.token
                more = page.more
            }
        }
    }
    private func fetchLegacyPage(
        database: CKDatabase, zoneID: CKRecordZone.ID, token: CKServerChangeToken?
    ) async throws -> LegacyCloudPage {
        let result = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
        return LegacyCloudPage(
            records: try result.modificationResultsByID.values.map {
                try LegacyCloudRecord(record: $0.get().record)
            },
            deletedNames: result.deletions.map(\.recordID.recordName), token: result.changeToken,
            more: result.moreComing
        )
    }

}

private struct LegacyCloudPage: Sendable {
    let records: [LegacyCloudRecord]
    let deletedNames: [String]
    let token: CKServerChangeToken
    let more: Bool
}
