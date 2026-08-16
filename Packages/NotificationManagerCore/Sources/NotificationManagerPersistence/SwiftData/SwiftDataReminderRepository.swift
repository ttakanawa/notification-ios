import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import SwiftData

public enum ScheduleReplacementBlockedState: Sendable, Equatable {
    case unsupportedFuture
    case corrupt
}

public enum PersistenceError: Error, Sendable, Equatable {
    case diskFull
    case reminderNotFound(UUID)
    case tagNotFound(UUID)
    case duplicateReminderID(UUID)
    case duplicateTagID(UUID)
    case duplicateTagName(String)
    case invalidReminder(ReminderValidationIssue)
    case invalidTag(TagValidationIssue)
    case scheduleReplacementNotAllowed(UUID, currentState: ScheduleReplacementBlockedState)
    case snapshotConsistencyUnavailable(attempts: Int)
    case storeFailure
}

public enum PersistenceSaveFailure: Sendable {
    case diskFull
}

public actor SwiftDataReminderRepository: ReminderRepository {
    private let container: ModelContainer
    private let mapper: RecordMapper
    private let scheduleCodec: any SchedulePayloadCoding
    private let tagNormalizer: TagNameNormalizerV1
    private let saveFailure: PersistenceSaveFailure?
    private let snapshotAttemptLimit: Int
    private let completeSnapshotInterFetchHook: @Sendable (Int) throws -> Void
    private let storeCoordinator: StoreCoordinator

    public init(
        container: ModelContainer,
        scheduleCodec: any SchedulePayloadCoding = SchedulePayloadCodec(),
        tagNormalizer: TagNameNormalizerV1 = TagNameNormalizerV1(),
        saveFailure: PersistenceSaveFailure? = nil
    ) {
        self.container = container
        self.scheduleCodec = scheduleCodec
        mapper = RecordMapper(scheduleCodec: scheduleCodec)
        self.tagNormalizer = tagNormalizer
        self.saveFailure = saveFailure
        snapshotAttemptLimit = 3
        completeSnapshotInterFetchHook = { _ in }
        storeCoordinator = StoreCoordinatorRegistry.shared.coordinator(for: container)
    }

    init(
        container: ModelContainer,
        scheduleCodec: any SchedulePayloadCoding = SchedulePayloadCodec(),
        tagNormalizer: TagNameNormalizerV1 = TagNameNormalizerV1(),
        saveFailure: PersistenceSaveFailure? = nil,
        snapshotAttemptLimit: Int,
        completeSnapshotInterFetchHook: @escaping @Sendable (Int) throws -> Void
    ) {
        precondition(snapshotAttemptLimit >= 2)
        self.container = container
        self.scheduleCodec = scheduleCodec
        mapper = RecordMapper(scheduleCodec: scheduleCodec)
        self.tagNormalizer = tagNormalizer
        self.saveFailure = saveFailure
        self.snapshotAttemptLimit = snapshotAttemptLimit
        self.completeSnapshotInterFetchHook = completeSnapshotInterFetchHook
        storeCoordinator = StoreCoordinatorRegistry.shared.coordinator(for: container)
    }

    public static func inMemory(
        saveFailure: PersistenceSaveFailure? = nil
    ) throws -> SwiftDataReminderRepository {
        SwiftDataReminderRepository(
            container: try ModelContainerFactory.inMemory(),
            saveFailure: saveFailure
        )
    }

    public func fetchCompleteSnapshot() async throws -> CompleteReminderSnapshot {
        try storeCoordinator.withCriticalSection {
            try fetchCompleteSnapshotCoordinated()
        }
    }

    private func fetchCompleteSnapshotCoordinated() throws -> CompleteReminderSnapshot {
        do {
            var previousCandidate: CompleteReminderSnapshot?
            for attempt in 1...snapshotAttemptLimit {
                guard let candidate = try collectStableCompleteSnapshotCandidate(attempt: attempt)
                else {
                    previousCandidate = nil
                    continue
                }
                if let previousCandidate, previousCandidate == candidate {
                    return candidate
                }
                previousCandidate = candidate
            }
            throw PersistenceError.snapshotConsistencyUnavailable(attempts: snapshotAttemptLimit)
        } catch let error as PersistenceError {
            throw error
        } catch {
            throw PersistenceError.storeFailure
        }
    }

    private func collectStableCompleteSnapshotCandidate(
        attempt: Int
    ) throws -> CompleteReminderSnapshot? {
        // SwiftData has no public API that pins several fetches to one query generation. This is
        // therefore an optimistic, bounded stability check rather than transaction isolation:
        // bracket both entity collections with fresh reads, then require the whole immutable
        // candidate to repeat on the next attempt before publishing it. Changes visible between
        // observations force a retry; persistent churn exhausts the configured attempt limit.
        // An adversarial ABA cycle that restores every value before each observation can evade
        // detection, and a commit after the final observation is not promised to be included.
        let remindersBefore = try readReminderSnapshots()
        try completeSnapshotInterFetchHook(attempt)
        let tagsBefore = try readTagSnapshots()
        let remindersAfter = try readReminderSnapshots()
        let tagsAfter = try readTagSnapshots()
        guard remindersBefore == remindersAfter, tagsBefore == tagsAfter else { return nil }
        return CompleteReminderSnapshot(reminders: remindersAfter, tags: tagsAfter)
    }

    private func readReminderSnapshots() throws -> [ReminderSnapshot] {
        let context = makeContext()
        let records = try context.fetch(FetchDescriptor<ReminderRecordV1>())
        try ensureUniqueReminderIDs(records)
        return records.map(mapper.reminder).sorted(by: Self.reminderSort)
    }

    private func readTagSnapshots() throws -> [TagSnapshot] {
        let context = makeContext()
        let records = try context.fetch(FetchDescriptor<TagRecordV1>())
        try ensureUniqueTagIDs(records)
        return records.map(mapper.tag).sorted(by: Self.tagSort)
    }

    public func reminder(id: UUID) async throws -> ReminderSnapshot? {
        try storeCoordinator.withCriticalSection {
            try reminderCoordinated(id: id)
        }
    }

    private func reminderCoordinated(id: UUID) throws -> ReminderSnapshot? {
        let context = makeContext()
        do {
            return try fetchReminder(id: id, in: context).map(mapper.reminder)
        } catch let error as PersistenceError {
            throw error
        } catch {
            throw PersistenceError.storeFailure
        }
    }

    public func save(_ mutation: EncodedReminderMutation) async throws -> ReminderSnapshot {
        try storeCoordinator.withCriticalSection {
            try saveCoordinated(mutation)
        }
    }

    private func saveCoordinated(_ mutation: EncodedReminderMutation) throws -> ReminderSnapshot {
        let context = makeContext()
        do {
            let existing = try fetchReminder(id: mutation.id, in: context)
            let record: ReminderRecordV1
            let finalScheduleData: Data
            switch mutation.command {
            case .create(let scheduleData):
                guard existing == nil else {
                    throw PersistenceError.duplicateReminderID(mutation.id)
                }
                record = ReminderRecordV1(
                    id: mutation.id,
                    title: mutation.title,
                    notes: mutation.notes,
                    urlString: mutation.urlString,
                    enabled: mutation.enabled,
                    scheduleData: scheduleData,
                    createdAt: mutation.createdAt,
                    updatedAt: mutation.updatedAt
                )
                finalScheduleData = scheduleData
            case .updateMetadataPreservingCurrentSchedule:
                guard let existing else {
                    throw PersistenceError.reminderNotFound(mutation.id)
                }
                record = existing
                finalScheduleData = existing.scheduleData
            case .replaceSchedule(let scheduleData):
                guard let existing else {
                    throw PersistenceError.reminderNotFound(mutation.id)
                }
                try requireReplaceableCurrentSchedule(
                    existing.scheduleData,
                    reminderID: mutation.id
                )
                record = existing
                finalScheduleData = scheduleData
            }

            let validated = try validateFinalAggregate(
                mutation,
                scheduleData: finalScheduleData
            )
            switch mutation.command {
            case .create, .replaceSchedule:
                try requireValidProposedSchedule(validated.scheduleData)
            case .updateMetadataPreservingCurrentSchedule:
                break
            }

            let tags = try resolveTags(ids: validated.tagIDs, in: context)
            if record.modelContext == nil {
                context.insert(record)
            }
            record.title = validated.title
            record.notes = validated.notes
            record.urlString = validated.urlString
            record.enabled = validated.enabled
            record.scheduleData = validated.scheduleData
            record.createdAt = validated.createdAt
            record.updatedAt = validated.updatedAt
            record.tags = tags

            try injectSaveFailureIfNeeded()
            try context.save()
            return mapper.reminder(record)
        } catch let error as PersistenceError {
            context.rollback()
            throw error
        } catch {
            context.rollback()
            throw PersistenceError.storeFailure
        }
    }

    public func delete(id: UUID) async throws {
        try storeCoordinator.withCriticalSection {
            try deleteCoordinated(id: id)
        }
    }

    private func deleteCoordinated(id: UUID) throws {
        let context = makeContext()
        do {
            guard let record = try fetchReminder(id: id, in: context) else {
                throw PersistenceError.reminderNotFound(id)
            }
            context.delete(record)
            try injectSaveFailureIfNeeded()
            try context.save()
        } catch let error as PersistenceError {
            context.rollback()
            throw error
        } catch {
            context.rollback()
            throw PersistenceError.storeFailure
        }
    }

    public func saveTag(_ mutation: EncodedTagMutation) async throws -> TagSnapshot {
        do {
            return try storeCoordinator.withCriticalSection {
                try saveTagCoordinated(mutation)
            }
        } catch let error as PersistenceError {
            throw Self.tagRepositoryError(error)
        }
    }

    private func saveTagCoordinated(_ mutation: EncodedTagMutation) throws -> TagSnapshot {
        let context = makeContext()
        do {
            try validateTag(mutation)
            let allTags = try context.fetch(FetchDescriptor<TagRecordV1>())
            try ensureUniqueTagIDs(allTags)
            let matches = allTags.filter { $0.id == mutation.id }
            guard matches.count <= 1 else { throw PersistenceError.duplicateTagID(mutation.id) }
            let record: TagRecordV1
            switch mutation.command {
            case .create:
                guard matches.isEmpty else { throw PersistenceError.duplicateTagID(mutation.id) }
                record = TagRecordV1(
                    id: mutation.id,
                    name: mutation.name,
                    normalizedName: mutation.normalizedName,
                    normalizationVersion: mutation.normalizationVersion,
                    createdAt: mutation.createdAt,
                    updatedAt: mutation.updatedAt
                )
            case .update:
                guard let existing = matches.first else {
                    throw PersistenceError.tagNotFound(mutation.id)
                }
                record = existing
            }
            let displayName = TagNameNormalizerV1.trimmedDisplayName(mutation.name)
            if allTags.contains(where: {
                $0.id != mutation.id
                    && TagNameNormalizerV1.trimmedDisplayName($0.name) == displayName
            }) {
                throw PersistenceError.duplicateTagName(displayName)
            }
            if record.modelContext == nil {
                context.insert(record)
            }
            record.name = mutation.name
            record.normalizedName = mutation.normalizedName
            record.normalizationVersion = mutation.normalizationVersion
            record.createdAt = mutation.createdAt
            record.updatedAt = mutation.updatedAt

            try injectSaveFailureIfNeeded()
            try context.save()
            return mapper.tag(record)
        } catch let error as PersistenceError {
            context.rollback()
            throw error
        } catch {
            context.rollback()
            throw PersistenceError.storeFailure
        }
    }

    public func deleteTag(id: UUID) async throws {
        do {
            try storeCoordinator.withCriticalSection {
                try deleteTagCoordinated(id: id)
            }
        } catch let error as PersistenceError {
            throw Self.tagRepositoryError(error)
        }
    }

    private static func tagRepositoryError(_ error: PersistenceError) -> TagRepositoryError {
        switch error {
        case .tagNotFound(let id):
            .notFound(id)
        case .duplicateTagID(let id):
            .duplicateID(id)
        case .duplicateTagName(let name):
            .duplicateName(name)
        case .invalidTag(let issue):
            .invalid(issue)
        default:
            .unavailable
        }
    }

    private func deleteTagCoordinated(id: UUID) throws {
        let context = makeContext()
        do {
            guard let record = try fetchTag(id: id, in: context) else {
                throw PersistenceError.tagNotFound(id)
            }
            context.delete(record)
            try injectSaveFailureIfNeeded()
            try context.save()
        } catch let error as PersistenceError {
            context.rollback()
            throw error
        } catch {
            context.rollback()
            throw PersistenceError.storeFailure
        }
    }

    private func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func fetchReminder(id: UUID, in context: ModelContext) throws -> ReminderRecordV1? {
        let requestedID = id
        var descriptor = FetchDescriptor<ReminderRecordV1>(
            predicate: #Predicate { $0.id == requestedID }
        )
        descriptor.fetchLimit = 2
        let matches = try context.fetch(descriptor)
        guard matches.count <= 1 else { throw PersistenceError.duplicateReminderID(id) }
        return matches.first
    }

    private func fetchTag(id: UUID, in context: ModelContext) throws -> TagRecordV1? {
        let requestedID = id
        var descriptor = FetchDescriptor<TagRecordV1>(
            predicate: #Predicate { $0.id == requestedID }
        )
        descriptor.fetchLimit = 2
        let matches = try context.fetch(descriptor)
        guard matches.count <= 1 else { throw PersistenceError.duplicateTagID(id) }
        return matches.first
    }

    private func resolveTags(ids: Set<UUID>, in context: ModelContext) throws -> [TagRecordV1] {
        guard !ids.isEmpty else { return [] }
        let records = try context.fetch(FetchDescriptor<TagRecordV1>())
        try ensureUniqueTagIDs(records)
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        return try ids.sorted(by: Self.uuidSort).map { id in
            guard let record = byID[id] else { throw PersistenceError.tagNotFound(id) }
            return record
        }
    }

    private func validateTag(_ mutation: EncodedTagMutation) throws {
        let normalized: String
        do {
            normalized = try tagNormalizer.normalize(mutation.name)
        } catch let issue as TagValidationIssue {
            throw PersistenceError.invalidTag(issue)
        }
        guard normalized == mutation.normalizedName else {
            throw PersistenceError.invalidTag(.normalizedNameMismatch)
        }
        guard mutation.normalizationVersion == TagLimits.normalizationVersion else {
            throw PersistenceError.invalidTag(.unsupportedNormalizationVersion)
        }
        guard Self.isFiniteIntegralSecond(mutation.createdAt) else {
            throw PersistenceError.invalidTag(.invalidCreatedAt)
        }
        guard Self.isFiniteIntegralSecond(mutation.updatedAt) else {
            throw PersistenceError.invalidTag(.invalidUpdatedAt)
        }
    }

    private func validateFinalAggregate(
        _ mutation: EncodedReminderMutation,
        scheduleData: Data
    ) throws -> ValidatedReminderAggregate {
        let draft = ReminderDraft(
            id: mutation.id,
            title: mutation.title,
            notes: mutation.notes,
            urlString: mutation.urlString,
            enabled: mutation.enabled,
            scheduleChange: .preserveOriginal,
            originalScheduleData: scheduleData,
            tagIDs: mutation.tagIDs,
            createdAt: mutation.createdAt,
            updatedAt: mutation.updatedAt
        )
        do {
            return try ReminderAggregateValidator().validate(draft)
        } catch let issue as ReminderValidationIssue {
            throw PersistenceError.invalidReminder(issue)
        }
    }

    private func requireReplaceableCurrentSchedule(
        _ scheduleData: Data,
        reminderID: UUID
    ) throws {
        switch scheduleCodec.decode(scheduleData) {
        case .valid, .domainInvalid:
            return
        case .unsupportedFuture:
            throw PersistenceError.scheduleReplacementNotAllowed(
                reminderID,
                currentState: .unsupportedFuture
            )
        case .corrupt:
            throw PersistenceError.scheduleReplacementNotAllowed(
                reminderID,
                currentState: .corrupt
            )
        }
    }

    private func requireValidProposedSchedule(_ scheduleData: Data) throws {
        guard case .valid = scheduleCodec.decode(scheduleData) else {
            throw PersistenceError.invalidReminder(.invalidSchedule)
        }
    }

    private func injectSaveFailureIfNeeded() throws {
        if case .diskFull = saveFailure {
            throw PersistenceError.diskFull
        }
    }

    private func ensureUniqueReminderIDs(_ records: [ReminderRecordV1]) throws {
        var ids: Set<UUID> = []
        for record in records where !ids.insert(record.id).inserted {
            throw PersistenceError.duplicateReminderID(record.id)
        }
    }

    private func ensureUniqueTagIDs(_ records: [TagRecordV1]) throws {
        var ids: Set<UUID> = []
        for record in records where !ids.insert(record.id).inserted {
            throw PersistenceError.duplicateTagID(record.id)
        }
    }

    private static func reminderSort(_ lhs: ReminderSnapshot, _ rhs: ReminderSnapshot) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return uuidSort(lhs.id, rhs.id)
    }

    private static func tagSort(_ lhs: TagSnapshot, _ rhs: TagSnapshot) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return uuidSort(lhs.id, rhs.id)
    }

    private static func uuidSort(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }

    private static func isFiniteIntegralSecond(_ date: Date) -> Bool {
        let seconds = date.timeIntervalSince1970
        return seconds.isFinite && seconds.rounded(.towardZero) == seconds
    }
}

private enum StoreIdentity: Hashable, Sendable {
    case inMemory(ObjectIdentifier)
    case persistent([String])

    init(container: ModelContainer) {
        let configurations = container.configurations
        if configurations.contains(where: \.isStoredInMemoryOnly) {
            self = .inMemory(ObjectIdentifier(container))
        } else {
            self = .persistent(
                configurations.map {
                    $0.url.standardizedFileURL.resolvingSymlinksInPath().path
                }.sorted()
            )
        }
    }
}

private final class StoreCoordinator: @unchecked Sendable {
    private let lock = NSLock()

    func withCriticalSection<Result: Sendable>(
        _ operation: () throws -> Result
    ) rethrows -> Result {
        // This operation is deliberately synchronous. Allowing suspension while locked would
        // reopen check-then-save races through actor reentrancy.
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

private final class StoreCoordinatorRegistry: @unchecked Sendable {
    static let shared = StoreCoordinatorRegistry()

    // All process-wide mutable registry state is accessed only while this lock is held.
    private let lock = NSLock()
    private var coordinators: [StoreIdentity: StoreCoordinator] = [:]

    func coordinator(for container: ModelContainer) -> StoreCoordinator {
        let identity = StoreIdentity(container: container)
        lock.lock()
        defer { lock.unlock() }
        if let coordinator = coordinators[identity] {
            return coordinator
        }
        let coordinator = StoreCoordinator()
        coordinators[identity] = coordinator
        return coordinator
    }
}
