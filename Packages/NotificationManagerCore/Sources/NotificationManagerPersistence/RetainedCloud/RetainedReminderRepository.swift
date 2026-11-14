import Foundation
import NotificationManagerApplication
import NotificationManagerDomain

/// The account-independent archive is authoritative. CloudKit only carries immutable copies.
public actor RetainedReminderRepository: ReminderRepository, ReminderCloudCommitChecking,
    DisplayCustomizationRepository
{
    private let url: URL
    var archive: RetainedArchive
    var currentAccount: String?
    private var proposedAccount: String?
    var phase: RetainedSyncPhase = .checking
    private var systemLocalOnly = false
    var sessionAcknowledgments: [String: [String: String]] = [:]
    private var cloudImportSessions: Set<UUID> = []
    private var observers: [UUID: AsyncStream<Void>.Continuation] = [:]

    /// Production callers share one actor for a store, including multiple app scenes.
    public static func open(url: URL, legacy: RetainedLegacySnapshot? = nil) throws
        -> RetainedReminderRepository
    {
        try RetainedRepositoryRegistry.shared.open(url: url, legacy: legacy)
    }

    public init(url: URL, legacy: RetainedLegacySnapshot? = nil) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            archive = try JSONDecoder().decode(RetainedArchive.self, from: Data(contentsOf: url))
            guard archive.schemaVersion == 1 else {
                throw RetainedStoreError.unsupportedArchive(archive.schemaVersion)
            }
        } else {
            archive = RetainedArchive()
        }
        if !archive.legacyImported, let legacy {
            for revision in legacy.revisions {
                archive.revisions[revision.id.uuidString] = revision
            }
            archive.legacyImported = true
        }
        if archive.syncPreference == .off { phase = .off }
        try Self.write(archive, to: url)
    }

    public func fetchCompleteSnapshot() throws -> CompleteReminderSnapshot {
        CompleteReminderSnapshot(
            reminders: activeRevisions(prefix: "reminder/").compactMap { revision in
                revision.payload.flatMap {
                    try? JSONDecoder().decode(RetainedReminderValue.self, from: $0)
                }?.snapshot()
            }.sorted {
                $0.createdAt == $1.createdAt
                    ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
            },
            tags: activeRevisions(prefix: "tag/").compactMap { revision in
                revision.payload.flatMap {
                    try? JSONDecoder().decode(RetainedTagValue.self, from: $0)
                }?.snapshot()
            }.sorted {
                $0.createdAt == $1.createdAt
                    ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
            }
        )
    }

    public func reminder(id: UUID) throws -> ReminderSnapshot? {
        try value(id: id)?.snapshot()
    }

    public func save(_ mutation: EncodedReminderMutation) throws -> ReminderSnapshot {
        let existing = try value(id: mutation.id)
        let data: Data
        switch mutation.command {
        case .create(let proposed):
            guard existing == nil else { throw PersistenceError.duplicateReminderID(mutation.id) }
            data = proposed
        case .updateMetadataPreservingCurrentSchedule:
            guard let existing else { throw PersistenceError.reminderNotFound(mutation.id) }
            data = existing.scheduleData
        case .replaceSchedule(let proposed):
            guard let existing else { throw PersistenceError.reminderNotFound(mutation.id) }
            switch SchedulePayloadCodec().decode(existing.scheduleData) {
            case .unsupportedFuture:
                throw PersistenceError.scheduleReplacementNotAllowed(
                    mutation.id, currentState: .unsupportedFuture)
            case .corrupt:
                throw PersistenceError.scheduleReplacementNotAllowed(
                    mutation.id, currentState: .corrupt)
            case .valid, .domainInvalid: break
            }
            data = proposed
        }
        let draft = ReminderDraft(
            id: mutation.id, title: mutation.title, notes: mutation.notes,
            urlString: mutation.urlString,
            enabled: mutation.enabled, originalScheduleData: data, tagIDs: mutation.tagIDs,
            createdAt: mutation.createdAt, updatedAt: mutation.updatedAt
        )
        let validated: ValidatedReminderAggregate
        do {
            validated = try ReminderAggregateValidator().validate(draft)
        } catch let issue as ReminderValidationIssue {
            throw PersistenceError.invalidReminder(issue)
        }
        switch mutation.command {
        case .create, .replaceSchedule:
            guard case .valid = SchedulePayloadCodec().decode(data) else {
                throw PersistenceError.invalidReminder(.invalidSchedule)
            }
        case .updateMetadataPreservingCurrentSchedule: break
        }
        for tagID in validated.tagIDs {
            guard current("tag/\(tagID.uuidString)")?.payload != nil else {
                throw PersistenceError.tagNotFound(tagID)
            }
        }
        let snapshot = ReminderSnapshot(
            id: validated.id, title: validated.title, notes: validated.notes,
            urlString: validated.urlString,
            enabled: validated.enabled, schedule: SchedulePayloadCodec().decode(data),
            tagIDs: validated.tagIDs,
            createdAt: validated.createdAt, updatedAt: validated.updatedAt,
            displayCustomizationData: existing?.displayCustomizationData
        )
        try append(
            entityKey: reminderKey(mutation.id),
            payload: RetainedCoding.encode(RetainedReminderValue(snapshot)))
        return snapshot
    }

    public func delete(id: UUID) throws {
        guard try value(id: id) != nil else { throw PersistenceError.reminderNotFound(id) }
        try append(entityKey: reminderKey(id), payload: nil)
    }

    public func saveTag(_ mutation: EncodedTagMutation) throws -> TagSnapshot {
        let key = "tag/\(mutation.id.uuidString)"
        let exists = current(key)?.payload != nil
        switch mutation.command {
        case .create: if exists { throw TagRepositoryError.duplicateID(mutation.id) }
        case .update: if !exists { throw TagRepositoryError.notFound(mutation.id) }
        }
        let normalized: String
        do {
            normalized = try TagNameNormalizerV1().normalize(mutation.name)
        } catch let issue as TagValidationIssue {
            throw TagRepositoryError.invalid(issue)
        }
        guard normalized == mutation.normalizedName else {
            throw TagRepositoryError.invalid(.normalizedNameMismatch)
        }
        guard mutation.normalizationVersion == TagLimits.normalizationVersion else {
            throw TagRepositoryError.invalid(.unsupportedNormalizationVersion)
        }
        guard Self.integral(mutation.createdAt) else {
            throw TagRepositoryError.invalid(.invalidCreatedAt)
        }
        guard Self.integral(mutation.updatedAt) else {
            throw TagRepositoryError.invalid(.invalidUpdatedAt)
        }
        let tags = try fetchCompleteSnapshot().tags
        let displayName = TagNameNormalizerV1.trimmedDisplayName(mutation.name)
        guard
            !tags.contains(where: {
                $0.id != mutation.id
                    && TagNameNormalizerV1.trimmedDisplayName($0.name) == displayName
            })
        else { throw TagRepositoryError.duplicateName(displayName) }
        let snapshot = TagSnapshot(
            id: mutation.id, name: mutation.name, normalizedName: normalized,
            normalizationVersion: mutation.normalizationVersion, createdAt: mutation.createdAt,
            updatedAt: mutation.updatedAt
        )
        try append(entityKey: key, payload: RetainedCoding.encode(RetainedTagValue(snapshot)))
        return snapshot
    }

    public func deleteTag(id: UUID) throws {
        guard current("tag/\(id.uuidString)")?.payload != nil else {
            throw TagRepositoryError.notFound(id)
        }
        var next = archive
        for snapshot in try fetchCompleteSnapshot().reminders where snapshot.tagIDs.contains(id) {
            var reminder = RetainedReminderValue(snapshot)
            reminder.tagIDs.removeAll { $0 == id }
            addRevision(
                to: &next, entityKey: reminderKey(snapshot.id),
                payload: try RetainedCoding.encode(reminder))
        }
        addRevision(to: &next, entityKey: "tag/\(id.uuidString)", payload: nil)
        try commit(next)
    }

    public func removeTagAssociation(tagID: UUID, from reminderID: UUID?) throws
        -> TagAssociationRemovalOutcome
    {
        guard current("tag/\(tagID.uuidString)")?.payload != nil else {
            throw TagRepositoryError.notFound(tagID)
        }
        var next = archive
        if let reminderID {
            guard var reminder = try value(id: reminderID) else {
                throw PersistenceError.reminderNotFound(reminderID)
            }
            reminder.tagIDs.removeAll { $0 == tagID }
            addRevision(
                to: &next, entityKey: reminderKey(reminderID),
                payload: try RetainedCoding.encode(reminder))
        }
        let hasReference = try fetchCompleteSnapshot().reminders.contains {
            $0.id != reminderID && $0.tagIDs.contains(tagID)
        }
        if !hasReference {
            addRevision(to: &next, entityKey: "tag/\(tagID.uuidString)", payload: nil)
        }
        try commit(next)
        return hasReference ? .tagRetained : .tagDeleted
    }

    public func globalDisplayCustomizationData() -> Data? {
        current("customization/global")?.payload
    }

    public func saveGlobalDisplayCustomizationData(_ data: Data?) throws {
        try append(entityKey: "customization/global", payload: data)
    }

    public func saveDisplayCustomizationData(_ data: Data?, reminderID: UUID) throws
        -> ReminderSnapshot
    {
        guard var reminder = try value(id: reminderID) else {
            throw PersistenceError.reminderNotFound(reminderID)
        }
        reminder.displayCustomizationData = data
        try append(entityKey: reminderKey(reminderID), payload: RetainedCoding.encode(reminder))
        return reminder.snapshot()
    }

    public func canPublish(_ snapshot: ReminderSnapshot) -> Bool {
        guard let current = current(reminderKey(snapshot.id)), let data = current.payload,
            let value = try? JSONDecoder().decode(RetainedReminderValue.self, from: data),
            value.snapshot() == snapshot
        else { return false }
        if archive.syncPreference == .off || systemLocalOnly { return true }
        guard phase == .syncing, cloudImportSessions.isEmpty, let account = currentAccount else {
            return false
        }
        var required = [current]
        for tagID in snapshot.tagIDs {
            guard let revision = self.current("tag/\(tagID.uuidString)"), revision.payload != nil
            else { return false }
            required.append(revision)
        }
        if let global = self.current("customization/global") { required.append(global) }
        return required.allSatisfy {
            sessionAcknowledgments[account]?[$0.id.uuidString] == $0.fingerprint
        }
    }

    public func changes() -> AsyncStream<Void> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        observers[id] = continuation
        continuation.yield(())
        continuation.onTermination = { [weak self] _ in Task { await self?.removeObserver(id) } }
        return stream
    }

    public func status() -> RetainedSyncStatus {
        RetainedSyncStatus(
            isEnabled: archive.syncPreference != .off, phase: phase,
            recoveryCopyCount: recoveryRevisions().count,
            pendingRevisionCount: currentAccount.map { pendingRevisions(account: $0).count } ?? 0
        )
    }

    public func setSyncEnabled(_ enabled: Bool) throws {
        var next = archive
        next.syncPreference = enabled ? .enabled : .off
        try commit(next)
        currentAccount = nil
        proposedAccount = nil
        systemLocalOnly = false
        phase = enabled ? .checking : .off
        notify()
    }

    /// A nil identity is uncertainty, never evidence of a switch. Only positively known
    /// system unavailability (signed out/restricted) permits the local-only gate.
    @discardableResult
    public func checkAccount(_ identity: String?, systemUnavailable: Bool = false) throws -> Bool {
        currentAccount = nil
        proposedAccount = nil
        systemLocalOnly = systemUnavailable
        guard archive.syncPreference != .off else {
            phase = .off
            notify()
            return false
        }
        guard let identity else {
            phase = .unavailable
            notify()
            return false
        }
        systemLocalOnly = false
        if archive.acceptedAccount == identity {
            currentAccount = identity
            phase = .syncing
            notify()
            return true
        }
        // Empty installations have nothing to move. Every retained value without proven
        // account origin requires consent, including a migration from the old mirror.
        if archive.revisions.isEmpty && archive.acceptedAccount == nil {
            var next = archive
            next.acceptedAccount = identity
            next.originAccount = identity
            try commit(next)
            currentAccount = identity
            phase = .syncing
            notify()
            return true
        }
        proposedAccount = identity
        phase = .confirmationRequired
        notify()
        return false
    }

    public func confirmAccount(_ accepted: Bool) throws {
        guard let identity = proposedAccount, phase == .confirmationRequired else {
            throw RetainedStoreError.confirmationRequired
        }
        var next = archive
        if accepted {
            next.acceptedAccount = identity
            next.originAccount = identity
        } else {
            next.syncPreference = .off
        }
        try commit(next)
        currentAccount = accepted ? identity : nil
        proposedAccount = nil
        phase = accepted ? .syncing : .off
        notify()
    }

    public func account() -> String? { currentAccount }

    public func pendingRevisions(account: String) -> [RetainedCloudRevision] {
        guard currentAccount == account, phase == .syncing else { return [] }
        return archive.revisions.values.filter {
            archive.acknowledgments[account]?[$0.id.uuidString] != $0.fingerprint
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    public func acknowledge(_ revision: RetainedCloudRevision, account: String) throws {
        guard currentAccount == account, phase == .syncing else {
            throw RetainedStoreError.staleAccount
        }
        guard archive.revisions[revision.id.uuidString] == revision else {
            throw RetainedStoreError.invalidRevision
        }
        if archive.acknowledgments[account]?[revision.id.uuidString] == revision.fingerprint {
            sessionAcknowledgments[account, default: [:]][revision.id.uuidString] =
                revision.fingerprint
            notify()
            return
        }
        var next = archive
        next.acknowledgments[account, default: [:]][revision.id.uuidString] = revision.fingerprint
        try commit(next)
        sessionAcknowledgments[account, default: [:]][revision.id.uuidString] = revision.fingerprint
    }

    public func importRevision(_ revision: RetainedCloudRevision, account: String) throws {
        guard currentAccount == account, phase == .syncing else {
            throw RetainedStoreError.staleAccount
        }
        try validateRevision(revision)
        if let existing = archive.revisions[revision.id.uuidString], existing != revision {
            throw RetainedStoreError.immutableRevisionCollision
        }
        if archive.revisions[revision.id.uuidString] == revision,
            archive.acknowledgments[account]?[revision.id.uuidString] == revision.fingerprint
        {
            sessionAcknowledgments[account, default: [:]][revision.id.uuidString] =
                revision.fingerprint
            notify()
            return
        }
        var next = archive
        next.revisions[revision.id.uuidString] = revision
        next.acknowledgments[account, default: [:]][revision.id.uuidString] = revision.fingerprint
        try commit(next)
        sessionAcknowledgments[account, default: [:]][revision.id.uuidString] = revision.fingerprint
    }

    public func recoveryRevisions() -> [RetainedCloudRevision] {
        archive.revisions.values.filter { revision in
            let selected = current(revision.entityKey)
            return selected?.id != revision.id && selected?.payload != revision.payload
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// Restore creates a new version and retains every previous value, including tombstones.
    public func restoreRevision(_ id: UUID) throws {
        guard let revision = archive.revisions[id.uuidString] else {
            throw RetainedStoreError.invalidRevision
        }
        try append(entityKey: revision.entityKey, payload: revision.payload)
    }

    /// Disk receipts are an optimization, not proof about the currently signed database.
    /// Revalidate visible heads after process restart before releasing publication.
    public func revisionsNeedingReceiptValidation(account: String) -> [RetainedCloudRevision] {
        guard currentAccount == account, phase == .syncing else { return [] }
        return Set(archive.revisions.values.map(\.entityKey)).compactMap { current($0) }.filter {
            sessionAcknowledgments[account]?[$0.id.uuidString] != $0.fingerprint
                && (archive.acknowledgments[account]?[$0.id.uuidString] == $0.fingerprint
                    || archive.legacyCommitted[account]?[$0.id.uuidString] == $0.fingerprint)
        }
    }

    /// A positively missing saved record means archived receipts must be rebuilt. All
    /// immutable values remain pending; no timestamp or inferred environment can release them.
    public func resetCloudReceipts(account: String) throws {
        guard currentAccount == account, phase == .syncing else {
            throw RetainedStoreError.staleAccount
        }
        var next = archive
        next.acknowledgments[account] = [:]
        next.legacyCommitted[account] = [:]
        try commit(next)
        sessionAcknowledgments[account] = [:]
        notify()
    }

    public func beginCloudImport(account: String) throws -> UUID {
        guard currentAccount == account, phase == .syncing else {
            throw RetainedStoreError.staleAccount
        }
        let session = UUID()
        cloudImportSessions.insert(session)
        notify()
        return session
    }

    public func finishCloudImport(_ session: UUID) {
        guard cloudImportSessions.remove(session) != nil else { return }
        notify()
    }

    public func engineState(account: String) -> Data? { archive.engineStates[account] }

    public func saveEngineState(_ data: Data, account: String) throws {
        guard currentAccount == account, phase == .syncing else {
            throw RetainedStoreError.staleAccount
        }
        var next = archive
        next.engineStates[account] = data
        try commit(next, notifyObservers: false)
    }

    public func invalidateReceipts(account: String) throws {
        var next = archive
        next.acknowledgments[account] = [:]
        next.engineStates.removeValue(forKey: account)
        next.acceptedAccount = nil
        try commit(next)
        sessionAcknowledgments[account] = [:]
        currentAccount = nil
        proposedAccount = account
        phase = .confirmationRequired
        notify()
    }

    public func markSyncFailed() {
        guard phase != .off, phase != .confirmationRequired, phase != .unavailable else { return }
        phase = .failed
        notify()
    }

    private func validateRevision(_ revision: RetainedCloudRevision) throws {
        guard revision.schemaVersion == 1, !revision.parents.contains(revision.id),
            revision.entityKey.hasPrefix("reminder/") || revision.entityKey.hasPrefix("tag/")
                || revision.entityKey == "customization/global"
        else { throw RetainedStoreError.invalidRevision }
        if let payload = revision.payload {
            if revision.entityKey.hasPrefix("reminder/") {
                let value = try JSONDecoder().decode(RetainedReminderValue.self, from: payload)
                guard revision.entityKey == reminderKey(value.id) else {
                    throw RetainedStoreError.invalidRevision
                }
            } else if revision.entityKey.hasPrefix("tag/") {
                let value = try JSONDecoder().decode(RetainedTagValue.self, from: payload)
                guard revision.entityKey == "tag/\(value.id.uuidString)" else {
                    throw RetainedStoreError.invalidRevision
                }
            }
        }
        for parent in revision.parents {
            if let existing = archive.revisions[parent.uuidString] {
                guard existing.entityKey == revision.entityKey else {
                    throw RetainedStoreError.invalidRevision
                }
                var pending = [existing]
                var visited: Set<UUID> = []
                while let ancestor = pending.popLast() {
                    guard ancestor.id != revision.id else {
                        throw RetainedStoreError.invalidRevision
                    }
                    if visited.insert(ancestor.id).inserted {
                        pending.append(
                            contentsOf: ancestor.parents.compactMap {
                                archive.revisions[$0.uuidString]
                            })
                    }
                }
            }
        }
        // Also validate children imported before their parents.
        guard
            !archive.revisions.values.contains(where: {
                $0.parents.contains(revision.id) && $0.entityKey != revision.entityKey
            })
        else { throw RetainedStoreError.invalidRevision }
    }

    private func reminderKey(_ id: UUID) -> String { "reminder/\(id.uuidString)" }

    private func value(id: UUID) throws -> RetainedReminderValue? {
        guard let data = current(reminderKey(id))?.payload else { return nil }
        return try JSONDecoder().decode(RetainedReminderValue.self, from: data)
    }

    private func activeRevisions(prefix: String) -> [RetainedCloudRevision] {
        Set(archive.revisions.values.map(\.entityKey)).filter { $0.hasPrefix(prefix) }.compactMap {
            current($0)
        }
    }

    private func heads(_ key: String) -> [RetainedCloudRevision] {
        let versions = archive.revisions.values.filter { $0.entityKey == key }
        let superseded = Set(versions.flatMap(\.parents))
        return versions.filter { !superseded.contains($0.id) }.sorted {
            $0.id.uuidString < $1.id.uuidString
        }
    }

    private func current(_ key: String) -> RetainedCloudRevision? { heads(key).last }

    private func append(entityKey: String, payload: Data?) throws {
        var next = archive
        addRevision(to: &next, entityKey: entityKey, payload: payload)
        try commit(next)
    }

    private func addRevision(to next: inout RetainedArchive, entityKey: String, payload: Data?) {
        let revision = RetainedCloudRevision(
            entityKey: entityKey, parents: heads(entityKey).map(\.id), payload: payload)
        next.revisions[revision.id.uuidString] = revision
    }

    func commit(_ next: RetainedArchive, notifyObservers: Bool = true) throws {
        try Self.write(next, to: url)
        archive = next
        if notifyObservers { notify() }
    }

    private static func write(_ archive: RetainedArchive, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try RetainedCoding.encode(archive).write(to: url, options: .atomic)
        let handle = try FileHandle(forWritingTo: url)
        do {
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
    }

    private static func integral(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite
            && date.timeIntervalSince1970.rounded(.towardZero) == date.timeIntervalSince1970
    }

    private func notify() { for observer in observers.values { observer.yield(()) } }
    private func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
}

private final class RetainedRepositoryRegistry: @unchecked Sendable {
    static let shared = RetainedRepositoryRegistry()
    private let lock = NSLock()
    private var repositories: [URL: RetainedReminderRepository] = [:]

    func open(url: URL, legacy: RetainedLegacySnapshot?) throws -> RetainedReminderRepository {
        try lock.withLock {
            let key = url.standardizedFileURL.resolvingSymlinksInPath()
            if let repository = repositories[key] { return repository }
            let repository = try RetainedReminderRepository(url: key, legacy: legacy)
            repositories[key] = repository
            return repository
        }
    }
}
