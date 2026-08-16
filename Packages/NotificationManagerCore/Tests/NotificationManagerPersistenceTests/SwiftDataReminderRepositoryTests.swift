import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import SwiftData
import Testing

@testable import NotificationManagerPersistence

@Suite(.serialized) struct SwiftDataReminderRepositoryTests {
    @Test func versionedSchemaHasCloudKitCompatibleOptionalInverseRelationshipsAndExactEncryption()
        throws
    {
        let schema = Schema(versionedSchema: NotificationManagerSchemaV1.self)
        let reminder = try #require(schema.entities.first { $0.name == "ReminderRecordV1" })
        let tag = try #require(schema.entities.first { $0.name == "TagRecordV1" })

        #expect(reminder.uniquenessConstraints.isEmpty)
        #expect(tag.uniquenessConstraints.isEmpty)
        #expect(reminder.attributes.allSatisfy { !$0.isUnique })
        #expect(tag.attributes.allSatisfy { !$0.isUnique })

        let encryptedReminderFields = Set(
            reminder.attributes.filter(isCloudEncrypted).map(\.name)
        )
        let encryptedTagFields = Set(tag.attributes.filter(isCloudEncrypted).map(\.name))
        #expect(encryptedReminderFields == ["title", "notes", "urlString", "scheduleData"])
        #expect(encryptedTagFields == ["name", "normalizedName"])
        #expect(reminder.attributes.allSatisfy { $0.options.isEmpty || isCloudEncrypted($0) })
        #expect(tag.attributes.allSatisfy { $0.options.isEmpty || isCloudEncrypted($0) })

        let tags = try #require(reminder.relationshipsByName["tags"])
        let reminders = try #require(tag.relationshipsByName["reminders"])
        #expect(tags.isOptional)
        #expect(reminders.isOptional)
        #expect(tags.inverseName == "reminders")
        #expect(reminders.inverseName == "tags")
        #expect(tags.deleteRule == .nullify)
        #expect(reminders.deleteRule == .nullify)
    }

    @Test func migrationPlanStartsAtV1WithNoStages() {
        #expect(NotificationManagerSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(NotificationManagerMigrationPlan.schemas.count == 1)
        #expect(
            NotificationManagerMigrationPlan.schemas.first?.versionIdentifier
                == Schema.Version(1, 0, 0))
        #expect(NotificationManagerMigrationPlan.stages.isEmpty)
    }

    @Test func inMemoryContainerDisablesCloudKit() throws {
        let container = try ModelContainerFactory.inMemory()
        let configuration = try #require(container.configurations.first)

        #expect(configuration.isStoredInMemoryOnly)
        #expect(String(reflecting: configuration.cloudKitDatabase).contains("_none: true"))
        #expect(container.migrationPlan == NotificationManagerMigrationPlan.self)
    }

    @Test func saveAndFetchReturnCompleteImmutableSnapshotsWithStableIDs() async throws {
        let repository = try SwiftDataReminderRepository.inMemory()
        let tag = try await repository.saveTag(.fixture(id: TestValues.tagID, name: "  ＴｅＳＴ  "))
        let original = EncodedReminderMutation.fixture(tagIDs: [tag.id])

        let inserted = try await repository.save(original)
        let fetched = try await repository.fetchCompleteSnapshot()

        #expect(inserted.id == TestValues.reminderID)
        #expect(inserted.tagIDs == [TestValues.tagID])
        #expect(fetched.reminders == [inserted])
        #expect(fetched.tags == [tag])

        let updated = try await repository.save(
            .fixture(
                title: "Updated",
                command: .updateMetadataPreservingCurrentSchedule,
                tagIDs: [tag.id],
                updatedAt: TestValues.later
            )
        )
        #expect(updated.id == inserted.id)
        #expect(try await repository.reminder(id: inserted.id) == updated)
        #expect(try await repository.fetchCompleteSnapshot().reminders.count == 1)
    }

    @Test func completeSnapshotRejectsTornInsertWhenExternalContextPrunesHistory() async throws {
        let container = try ModelContainerFactory.inMemory()
        try prunePersistentHistory(in: container)
        #expect(try persistentHistoryCount(in: container) == 0)
        let injections = LockedCounter()
        let repository = SwiftDataReminderRepository(
            container: container,
            snapshotAttemptLimit: 3,
            completeSnapshotInterFetchHook: { _ in
                guard injections.increment() == 1 else { return }
                try insertRelatedReminderAndTag(in: container)
                try prunePersistentHistory(in: container)
            }
        )

        let snapshot = try await repository.fetchCompleteSnapshot()

        #expect(injections.value == 3)
        #expect(try persistentHistoryCount(in: container) == 0)
        #expect(snapshot.reminders.map(\.id) == [TestValues.reminderID])
        #expect(snapshot.tags.map(\.id) == [TestValues.tagID])
        #expect(snapshot.reminders.first?.tagIDs == [TestValues.tagID])
    }

    @Test func completeSnapshotRetriesAnExternalRelationshipUpdate() async throws {
        let container = try ModelContainerFactory.inMemory()
        try insertRelatedReminderAndTag(in: container)
        try insertTag(
            id: TestValues.otherTagID, name: "Work", normalizedName: "work", in: container)
        try prunePersistentHistory(in: container)
        let injections = LockedCounter()
        let repository = SwiftDataReminderRepository(
            container: container,
            snapshotAttemptLimit: 3,
            completeSnapshotInterFetchHook: { _ in
                guard injections.increment() == 1 else { return }
                let context = ModelContext(container)
                context.autosaveEnabled = false
                let reminder = try #require(
                    context.fetch(FetchDescriptor<ReminderRecordV1>()).first {
                        $0.id == TestValues.reminderID
                    }
                )
                let replacement = try #require(
                    context.fetch(FetchDescriptor<TagRecordV1>()).first {
                        $0.id == TestValues.otherTagID
                    }
                )
                reminder.tags = [replacement]
                reminder.updatedAt = TestValues.later
                try context.save()
                try prunePersistentHistory(in: container)
            }
        )

        let snapshot = try await repository.fetchCompleteSnapshot()

        #expect(injections.value == 3)
        #expect(try persistentHistoryCount(in: container) == 0)
        #expect(Set(snapshot.tags.map(\.id)) == [TestValues.tagID, TestValues.otherTagID])
        #expect(snapshot.reminders.first?.tagIDs == [TestValues.otherTagID])
        #expect(snapshot.reminders.first?.updatedAt == TestValues.later)
    }

    @Test func completeSnapshotRetriesExternalTagDeleteAndRelationshipNullification() async throws {
        let container = try ModelContainerFactory.inMemory()
        try insertRelatedReminderAndTag(in: container)
        try prunePersistentHistory(in: container)
        let injections = LockedCounter()
        let repository = SwiftDataReminderRepository(
            container: container,
            snapshotAttemptLimit: 3,
            completeSnapshotInterFetchHook: { _ in
                guard injections.increment() == 1 else { return }
                let context = ModelContext(container)
                context.autosaveEnabled = false
                let tag = try #require(context.fetch(FetchDescriptor<TagRecordV1>()).first)
                context.delete(tag)
                try context.save()
                try prunePersistentHistory(in: container)
            }
        )

        let snapshot = try await repository.fetchCompleteSnapshot()

        #expect(injections.value == 3)
        #expect(try persistentHistoryCount(in: container) == 0)
        #expect(snapshot.tags.isEmpty)
        #expect(snapshot.reminders.map(\.id) == [TestValues.reminderID])
        #expect(snapshot.reminders.first?.tagIDs.isEmpty == true)
    }

    @Test(arguments: ReminderPersistedField.allCases)
    func completeSnapshotDetectsEachReminderFieldChangingAcrossPrunedCollections(
        field: ReminderPersistedField
    ) async throws {
        let container = try ModelContainerFactory.inMemory()
        try insertRelatedReminderAndTag(in: container)
        try prunePersistentHistory(in: container)
        let injections = LockedCounter()
        let repository = SwiftDataReminderRepository(
            container: container,
            snapshotAttemptLimit: 3,
            completeSnapshotInterFetchHook: { attempt in
                _ = injections.increment()
                let context = ModelContext(container)
                context.autosaveEnabled = false
                let reminder = try #require(
                    context.fetch(FetchDescriptor<ReminderRecordV1>()).first)
                field.mutate(reminder, attempt: attempt)
                try context.save()
                try prunePersistentHistory(in: container)
            }
        )

        await #expect(
            throws: PersistenceError.snapshotConsistencyUnavailable(attempts: 3)
        ) {
            try await repository.fetchCompleteSnapshot()
        }
        #expect(injections.value == 3)
        #expect(try persistentHistoryCount(in: container) == 0)
    }

    @Test(arguments: TagPersistedField.allCases)
    func completeSnapshotDetectsEachTagFieldChangingAcrossPrunedCollections(
        field: TagPersistedField
    ) async throws {
        let container = try ModelContainerFactory.inMemory()
        try insertRelatedReminderAndTag(in: container)
        try prunePersistentHistory(in: container)
        let injections = LockedCounter()
        let repository = SwiftDataReminderRepository(
            container: container,
            snapshotAttemptLimit: 3,
            completeSnapshotInterFetchHook: { attempt in
                _ = injections.increment()
                let context = ModelContext(container)
                context.autosaveEnabled = false
                let tag = try #require(context.fetch(FetchDescriptor<TagRecordV1>()).first)
                field.mutate(tag, attempt: attempt)
                try context.save()
                try prunePersistentHistory(in: container)
            }
        )

        await #expect(
            throws: PersistenceError.snapshotConsistencyUnavailable(attempts: 3)
        ) {
            try await repository.fetchCompleteSnapshot()
        }
        #expect(injections.value == 3)
        #expect(try persistentHistoryCount(in: container) == 0)
    }

    @Test func staleMetadataMutationPreservesTheCurrentDurableScheduleBytes() async throws {
        let container = try ModelContainerFactory.inMemory()
        let repository = SwiftDataReminderRepository(container: container)
        let unsupported = Data(
            #"{"format":"notification-manager.schedule","future":true,"version":4294967295}"#.utf8
        )
        try insertReminder(scheduleData: unsupported, in: container)
        let staleMetadataMutation = EncodedReminderMutation.fixture(
            title: "Metadata edit",
            command: .updateMetadataPreservingCurrentSchedule,
            updatedAt: TestValues.later
        )
        let current = try SchedulePayloadCodec().encodeCurrent(TestValues.schedule)
        try updateScheduleData(current, in: container)

        let saved = try await repository.save(staleMetadataMutation)
        let persisted = try #require(try await repository.reminder(id: TestValues.reminderID))

        #expect(saved.title == "Metadata edit")
        #expect(rawScheduleData(saved.schedule) == current)
        #expect(rawScheduleData(persisted.schedule) == current)
    }

    @Test func metadataOnlyMappingsPreserveUnsupportedAndCorruptRawBytesExactly() async throws {
        let container = try ModelContainerFactory.inMemory()
        let repository = SwiftDataReminderRepository(container: container)
        let unsupported = Data(
            #"{"format":"notification-manager.schedule","future":true,"version":4294967295}"#.utf8
        )
        try insertReminder(scheduleData: unsupported, in: container)
        let unsupportedEdit = try await repository.save(
            .fixture(
                title: "Metadata edit",
                command: .updateMetadataPreservingCurrentSchedule,
                updatedAt: TestValues.later
            ))
        #expect(rawScheduleData(unsupportedEdit.schedule) == unsupported)

        let corrupt = Data([0xFF, 0x00, 0x7B])
        try updateScheduleData(corrupt, in: container)
        let corruptEdit = try await repository.save(
            .fixture(
                title: "Second metadata edit",
                command: .updateMetadataPreservingCurrentSchedule,
                updatedAt: TestValues.latest
            ))
        let persisted = try #require(try await repository.reminder(id: TestValues.reminderID))
        #expect(rawScheduleData(corruptEdit.schedule) == corrupt)
        #expect(rawScheduleData(persisted.schedule) == corrupt)
    }

    @Test func metadataUpdateValidatesTheFinalAggregateUsingCurrentScheduleBytes() async throws {
        let container = try ModelContainerFactory.inMemory()
        let repository = SwiftDataReminderRepository(container: container)
        try insertReminder(
            scheduleData: Data(repeating: 0xFF, count: ReminderLimits.scheduleBytes + 1),
            in: container
        )

        await #expect(throws: PersistenceError.invalidReminder(.scheduleTooLarge)) {
            try await repository.save(
                .fixture(
                    command: .updateMetadataPreservingCurrentSchedule,
                    updatedAt: TestValues.later
                ))
        }

        #expect(try await repository.reminder(id: TestValues.reminderID)?.title == "Reminder")
    }

    @Test func replacingAValidScheduleReturnsSemanticallyEquivalentDecodedSnapshot() async throws {
        let repository = try SwiftDataReminderRepository.inMemory()
        _ = try await repository.save(
            .fixture(
                command: .create(scheduleData: TestValues.validScheduleData)
            ))
        let definition = TestValues.schedule
        let encoded = try SchedulePayloadCodec().encodeCurrent(definition)

        let updated = try await repository.save(
            .fixture(
                command: .replaceSchedule(scheduleData: encoded),
                updatedAt: TestValues.later
            )
        )

        guard case .valid(let decoded, let version, let originalData) = updated.schedule else {
            Issue.record("Expected a valid replacement schedule")
            return
        }
        #expect(decoded == definition)
        #expect(version == SchedulePayloadCodec.currentVersion)
        #expect(originalData == encoded)
    }

    @Test(arguments: ScheduleReplacementBlockedCase.allCases)
    func replacingAnOpaqueCurrentScheduleIsRejectedAtomically(
        blocked: ScheduleReplacementBlockedCase
    ) async throws {
        let container = try ModelContainerFactory.inMemory()
        try insertReminder(scheduleData: blocked.data, in: container)
        let repository = SwiftDataReminderRepository(container: container)
        let replacement = try SchedulePayloadCodec().encodeCurrent(TestValues.schedule)

        await #expect(throws: blocked.expectedError) {
            try await repository.save(
                .fixture(
                    title: "Must not publish",
                    command: .replaceSchedule(scheduleData: replacement),
                    updatedAt: TestValues.later
                ))
        }

        let persisted = try #require(await repository.reminder(id: TestValues.reminderID))
        #expect(persisted.title == "Reminder")
        #expect(rawScheduleData(persisted.schedule) == blocked.data)
    }

    @Test func replacingADomainInvalidCurrentScheduleRepairsIt() async throws {
        let container = try ModelContainerFactory.inMemory()
        try insertReminder(scheduleData: TestValues.domainInvalidScheduleData, in: container)
        let repository = SwiftDataReminderRepository(container: container)
        let replacement = try SchedulePayloadCodec().encodeCurrent(TestValues.schedule)

        let saved = try await repository.save(
            .fixture(
                command: .replaceSchedule(scheduleData: replacement),
                updatedAt: TestValues.later
            ))

        guard case .valid = saved.schedule else {
            Issue.record("Expected the domain-invalid schedule to be repaired")
            return
        }
        #expect(rawScheduleData(saved.schedule) == replacement)
    }

    @Test func reminderUpdateAfterDeleteDoesNotResurrectTheDeletedRow() async throws {
        let repository = try SwiftDataReminderRepository.inMemory()
        _ = try await repository.save(
            .fixture(
                command: .create(scheduleData: TestValues.validScheduleData)
            ))
        let staleUpdate = EncodedReminderMutation.fixture(
            title: "Stale",
            command: .updateMetadataPreservingCurrentSchedule,
            updatedAt: TestValues.later
        )
        try await repository.delete(id: TestValues.reminderID)

        await #expect(throws: PersistenceError.reminderNotFound(TestValues.reminderID)) {
            try await repository.save(staleUpdate)
        }

        #expect(try await repository.reminder(id: TestValues.reminderID) == nil)
    }

    @Test func reminderCreateRejectsAnOccupiedIDWithoutOverwritingIt() async throws {
        let repository = try SwiftDataReminderRepository.inMemory()
        let original = try await repository.save(
            .fixture(
                command: .create(scheduleData: TestValues.validScheduleData)
            ))

        await #expect(throws: PersistenceError.duplicateReminderID(TestValues.reminderID)) {
            try await repository.save(
                .fixture(
                    title: "Collision",
                    command: .create(scheduleData: TestValues.validScheduleData),
                    updatedAt: TestValues.later
                ))
        }

        #expect(try await repository.reminder(id: TestValues.reminderID) == original)
    }

    @Test func tagUpdateAfterDeleteDoesNotResurrectTheDeletedRow() async throws {
        let repository = try SwiftDataReminderRepository.inMemory()
        _ = try await repository.saveTag(.fixture(id: TestValues.tagID, name: "Travel"))
        let staleUpdate = EncodedTagMutation.fixture(
            id: TestValues.tagID,
            name: "Trips",
            command: .update
        )
        try await repository.deleteTag(id: TestValues.tagID)

        await #expect(throws: TagRepositoryError.notFound(TestValues.tagID)) {
            try await repository.saveTag(staleUpdate)
        }

        #expect(try await repository.fetchCompleteSnapshot().tags.isEmpty)
    }

    @Test func tagCreateRejectsAnOccupiedIDWithoutOverwritingIt() async throws {
        let repository = try SwiftDataReminderRepository.inMemory()
        let original = try await repository.saveTag(.fixture(id: TestValues.tagID, name: "Travel"))

        await #expect(throws: TagRepositoryError.duplicateID(TestValues.tagID)) {
            try await repository.saveTag(.fixture(id: TestValues.tagID, name: "Collision"))
        }

        #expect(try await repository.fetchCompleteSnapshot().tags == [original])
    }

    @Test func invalidTagFailureIsSemanticAndRollsBackWithoutPublishingARecord() async throws {
        let repository = try SwiftDataReminderRepository.inMemory()
        let invalid = EncodedTagMutation(
            id: TestValues.tagID,
            name: "Work",
            normalizedName: "wrong",
            normalizationVersion: TagLimits.normalizationVersion,
            createdAt: TestValues.created,
            updatedAt: TestValues.created,
            command: .create
        )

        await #expect(throws: TagRepositoryError.invalid(.normalizedNameMismatch)) {
            try await repository.saveTag(invalid)
        }

        #expect(try await repository.fetchCompleteSnapshot().tags.isEmpty)
    }

    @Test func unavailableTagSaveRollsBackWithoutPublishingARecord() async throws {
        let repository = try SwiftDataReminderRepository.inMemory(saveFailure: .diskFull)

        await #expect(throws: TagRepositoryError.unavailable) {
            try await repository.saveTag(.fixture(id: TestValues.tagID, name: "Work"))
        }

        #expect(try await repository.fetchCompleteSnapshot().tags.isEmpty)
    }

    @Test func missingTagDeleteIsSemanticAndLeavesTheSnapshotUnchanged() async throws {
        let repository = try SwiftDataReminderRepository.inMemory()

        await #expect(throws: TagRepositoryError.notFound(TestValues.tagID)) {
            try await repository.deleteTag(id: TestValues.tagID)
        }

        #expect(try await repository.fetchCompleteSnapshot().tags.isEmpty)
    }

    @Test func failedSaveRollsBackWithoutPublishingPartialSnapshot() async throws {
        let repository = try SwiftDataReminderRepository.inMemory(saveFailure: .diskFull)

        await #expect(throws: PersistenceError.diskFull) {
            try await repository.save(.fixture())
        }

        #expect(try await repository.fetchCompleteSnapshot().reminders.isEmpty)
        #expect(try await repository.fetchCompleteSnapshot().tags.isEmpty)
    }

    @Test func missingTagFailureRollsBackTheWholeReminderMutation() async throws {
        let repository = try SwiftDataReminderRepository.inMemory()

        await #expect(throws: PersistenceError.tagNotFound(TestValues.tagID)) {
            try await repository.save(.fixture(tagIDs: [TestValues.tagID]))
        }

        #expect(try await repository.fetchCompleteSnapshot().reminders.isEmpty)
    }

    @Test func localNormalizedTagDuplicateIsRejectedAtomicallyWithoutMergingUUIDs() async throws {
        let repository = try SwiftDataReminderRepository.inMemory()
        let first = try await repository.saveTag(.fixture(id: TestValues.tagID, name: "ＴｅＳＴ"))

        await #expect(throws: TagRepositoryError.duplicateNormalizedName("test")) {
            try await repository.saveTag(.fixture(id: TestValues.otherTagID, name: "test"))
        }

        let snapshot = try await repository.fetchCompleteSnapshot()
        #expect(snapshot.tags == [first])
        #expect(snapshot.tags.first?.id == TestValues.tagID)
    }

    @Test func concurrentRepositoriesAllowOneNormalizedTagNamePerContainer() async throws {
        let container = try ModelContainerFactory.inMemory()
        let firstRepository = SwiftDataReminderRepository(container: container)
        let secondRepository = SwiftDataReminderRepository(container: container)
        let saveBarrier = TimedSaveBarrier(participants: 2)
        let observer = installSaveBarrier(saveBarrier, containers: [container])
        defer { NotificationCenter.default.removeObserver(observer) }

        async let first = tagSaveOutcome(
            .fixture(id: TestValues.tagID, name: "ＴｅＳＴ"),
            in: firstRepository
        )
        async let second = tagSaveOutcome(
            .fixture(id: TestValues.otherTagID, name: "test"),
            in: secondRepository
        )
        let outcomes = await [first, second]

        #expect(outcomes.filter(\.isSaved).count == 1)
        #expect(outcomes.filter { $0 == .duplicate("test") }.count == 1)
        let snapshot = try await firstRepository.fetchCompleteSnapshot()
        #expect(snapshot.tags.count == 1)
        #expect(snapshot.tags.first?.normalizedName == "test")
    }

    @Test func repositoriesForTheSamePersistentStoreURLShareDuplicateCoordination() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "NotificationManagerPersistenceTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Shared.store")
        let configuration = ModelConfiguration(
            "Shared",
            schema: ModelContainerFactory.schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let firstContainer = try ModelContainerFactory.makeContainer(configuration: configuration)
        let secondContainer = try ModelContainerFactory.makeContainer(configuration: configuration)
        let firstRepository = SwiftDataReminderRepository(container: firstContainer)
        let secondRepository = SwiftDataReminderRepository(container: secondContainer)
        let saveBarrier = TimedSaveBarrier(participants: 2)
        let observer = installSaveBarrier(
            saveBarrier,
            containers: [firstContainer, secondContainer]
        )
        defer { NotificationCenter.default.removeObserver(observer) }

        async let first = tagSaveOutcome(
            .fixture(id: TestValues.tagID, name: "ＴｅＳＴ"),
            in: firstRepository
        )
        async let second = tagSaveOutcome(
            .fixture(id: TestValues.otherTagID, name: "test"),
            in: secondRepository
        )
        let outcomes = await [first, second]

        #expect(outcomes.filter(\.isSaved).count == 1)
        #expect(outcomes.filter { $0 == .duplicate("test") }.count == 1)
        #expect(try await firstRepository.fetchCompleteSnapshot().tags.count == 1)
        #expect(try await secondRepository.fetchCompleteSnapshot().tags.count == 1)
    }

    @Test func concurrentRepositoriesKeepDistinctNormalizedTagNamesIndependent() async throws {
        let container = try ModelContainerFactory.inMemory()
        let firstRepository = SwiftDataReminderRepository(container: container)
        let secondRepository = SwiftDataReminderRepository(container: container)

        async let first = tagSaveOutcome(
            .fixture(id: TestValues.tagID, name: "Travel"),
            in: firstRepository
        )
        async let second = tagSaveOutcome(
            .fixture(id: TestValues.otherTagID, name: "Work"),
            in: secondRepository
        )
        let outcomes = await [first, second]

        #expect(outcomes.filter(\.isSaved).count == 2)
        let snapshot = try await firstRepository.fetchCompleteSnapshot()
        #expect(Set(snapshot.tags.map(\.id)) == [TestValues.tagID, TestValues.otherTagID])
        #expect(Set(snapshot.tags.map(\.normalizedName)) == ["travel", "work"])
    }

    @Test func cloudImportedNormalizedDuplicatesWithDifferentUUIDsRemainSeparate() async throws {
        let container = try ModelContainerFactory.inMemory()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.insert(TagRecordV1.fixture(id: TestValues.tagID, name: "Test"))
        context.insert(TagRecordV1.fixture(id: TestValues.otherTagID, name: "ＴｅＳＴ"))
        try context.save()

        let repository = SwiftDataReminderRepository(container: container)
        let snapshot = try await repository.fetchCompleteSnapshot()

        #expect(Set(snapshot.tags.map(\.id)) == [TestValues.tagID, TestValues.otherTagID])
        #expect(snapshot.tags.map(\.normalizedName) == ["test", "test"])
    }

    @Test func unknownOrCorruptScheduleDoesNotPreventDelete() async throws {
        let container = try ModelContainerFactory.inMemory()
        try insertReminder(scheduleData: Data([0xFF, 0xFE]), in: container)
        let repository = SwiftDataReminderRepository(container: container)

        try await repository.delete(id: TestValues.reminderID)

        #expect(try await repository.reminder(id: TestValues.reminderID) == nil)
        #expect(try await repository.fetchCompleteSnapshot().reminders.isEmpty)
    }

    @Test func deletingTagNullifiesReminderRelationshipInTheSameSavedMutation() async throws {
        let repository = try SwiftDataReminderRepository.inMemory()
        _ = try await repository.saveTag(.fixture(id: TestValues.tagID, name: "Travel"))
        _ = try await repository.save(.fixture(tagIDs: [TestValues.tagID]))

        try await repository.deleteTag(id: TestValues.tagID)

        let snapshot = try await repository.fetchCompleteSnapshot()
        #expect(snapshot.tags.isEmpty)
        #expect(snapshot.reminders.first?.tagIDs.isEmpty == true)
    }

    @Test func devicePreferenceDefaultsOffPersistsAndUsesOnlyInjectedSuite() async throws {
        let suiteA = "NotificationManagerPersistenceTests.A.\(UUID().uuidString)"
        let suiteB = "NotificationManagerPersistenceTests.B.\(UUID().uuidString)"
        let defaultsA = try #require(UserDefaults(suiteName: suiteA))
        let defaultsB = try #require(UserDefaults(suiteName: suiteB))
        defer {
            defaultsA.removePersistentDomain(forName: suiteA)
            defaultsB.removePersistentDomain(forName: suiteB)
        }
        defaultsA.removePersistentDomain(forName: suiteA)
        defaultsB.removePersistentDomain(forName: suiteB)
        let first = UserDefaultsNotificationPreferenceStore(suiteName: suiteA)
        let sameSuite = UserDefaultsNotificationPreferenceStore(suiteName: suiteA)
        let otherSuite = UserDefaultsNotificationPreferenceStore(suiteName: suiteB)

        #expect(await first.isEnabled() == false)
        await first.setEnabled(true)
        #expect(await sameSuite.isEnabled() == true)
        #expect(await otherSuite.isEnabled() == false)
        await sameSuite.setEnabled(false)
        #expect(await first.isEnabled() == false)
    }

    private func isCloudEncrypted(_ attribute: Schema.Attribute) -> Bool {
        String(reflecting: attribute.options) == "[allowsCloudEncryption]"
    }
}

private enum TestValues {
    static let reminderID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    static let tagID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    static let otherTagID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    static let created = Date(timeIntervalSince1970: 1_700_000_000)
    static let later = Date(timeIntervalSince1970: 1_700_000_100)
    static let latest = Date(timeIntervalSince1970: 1_700_000_200)
    static let schedule = ScheduleDefinition(
        source: SourceWallClock(
            year: 2026,
            month: 8,
            day: 6,
            hour: 9,
            minute: 30,
            timeZoneIdentifier: "Asia/Manila"
        ),
        rule: .daily(interval: 1),
        end: .never,
        early: EarlyReminder(value: 5, unit: .minutes)
    )
    static let validScheduleData: Data = {
        guard let data = try? SchedulePayloadCodec().encodeCurrent(schedule) else {
            preconditionFailure("Valid schedule fixture must encode")
        }
        return data
    }()
    static let domainInvalidScheduleData = Data(
        #"{"format":"notification-manager.schedule","payload":{"end":{"type":"never"},"rule":{"interval":0,"type":"daily"},"source":{"day":3,"hour":9,"minute":30,"month":8,"timeZone":"America/New_York","year":2026}},"version":1}"#
            .utf8
    )
}

enum ScheduleReplacementBlockedCase: CaseIterable, Sendable {
    case unsupportedFuture
    case corrupt

    var data: Data {
        switch self {
        case .unsupportedFuture:
            Data(#"{"format":"notification-manager.schedule","version":4294967295}"#.utf8)
        case .corrupt:
            Data([0xFF, 0x00, 0x7B])
        }
    }

    var expectedError: PersistenceError {
        switch self {
        case .unsupportedFuture:
            .scheduleReplacementNotAllowed(
                TestValues.reminderID,
                currentState: .unsupportedFuture
            )
        case .corrupt:
            .scheduleReplacementNotAllowed(TestValues.reminderID, currentState: .corrupt)
        }
    }
}

enum ReminderPersistedField: CaseIterable, Sendable {
    case id
    case title
    case notes
    case urlString
    case enabled
    case scheduleData
    case createdAt
    case updatedAt

    func mutate(_ reminder: ReminderRecordV1, attempt: Int) {
        switch self {
        case .id:
            reminder.id = mutationUUID(attempt: attempt, prefix: "44444444")
        case .title:
            reminder.title = "Remote title \(attempt)"
        case .notes:
            reminder.notes = "Remote notes \(attempt)"
        case .urlString:
            reminder.urlString = "https://example.com/remote/\(attempt)"
        case .enabled:
            reminder.enabled = attempt.isMultiple(of: 2)
        case .scheduleData:
            reminder.scheduleData = Data([0xFF, UInt8(attempt)])
        case .createdAt:
            reminder.createdAt = mutationDate(attempt: attempt, multiplier: 10)
        case .updatedAt:
            reminder.updatedAt = mutationDate(attempt: attempt, multiplier: 1)
        }
    }
}

enum TagPersistedField: CaseIterable, Sendable {
    case id
    case name
    case normalizedName
    case normalizationVersion
    case createdAt
    case updatedAt

    func mutate(_ tag: TagRecordV1, attempt: Int) {
        switch self {
        case .id:
            tag.id = mutationUUID(attempt: attempt, prefix: "55555555")
        case .name:
            tag.name = "Remote tag \(attempt)"
        case .normalizedName:
            tag.normalizedName = "remote-tag-\(attempt)"
        case .normalizationVersion:
            tag.normalizationVersion = "remote-version-\(attempt)"
        case .createdAt:
            tag.createdAt = mutationDate(attempt: attempt, multiplier: 10)
        case .updatedAt:
            tag.updatedAt = mutationDate(attempt: attempt, multiplier: 1)
        }
    }
}

private func mutationUUID(attempt: Int, prefix: String) -> UUID {
    let value = "\(prefix)-4444-4444-8444-00000000000\(attempt)"
    guard let id = UUID(uuidString: value) else {
        preconditionFailure("Invalid mutation UUID fixture: \(value)")
    }
    return id
}

private func mutationDate(attempt: Int, multiplier: Int) -> Date {
    Date(
        timeIntervalSince1970: TestValues.latest.timeIntervalSince1970
            + Double(attempt * multiplier)
    )
}

extension EncodedReminderMutation {
    fileprivate static func fixture(
        title: String = "Reminder",
        command: ReminderMutationCommand = .create(scheduleData: TestValues.validScheduleData),
        tagIDs: Set<UUID> = [],
        updatedAt: Date = TestValues.created
    ) -> EncodedReminderMutation {
        EncodedReminderMutation(
            id: TestValues.reminderID,
            title: title,
            notes: "Notes",
            urlString: "https://example.com/reminder",
            enabled: true,
            tagIDs: tagIDs,
            createdAt: TestValues.created,
            updatedAt: updatedAt,
            command: command
        )
    }
}

extension EncodedTagMutation {
    fileprivate static func fixture(
        id: UUID,
        name: String,
        command: TagMutationCommand = .create
    ) -> EncodedTagMutation {
        guard let normalizedName = try? TagNameNormalizerV1().normalize(name) else {
            preconditionFailure("Valid tag fixture name must normalize: \(name)")
        }
        return EncodedTagMutation(
            id: id,
            name: name,
            normalizedName: normalizedName,
            normalizationVersion: TagLimits.normalizationVersion,
            createdAt: TestValues.created,
            updatedAt: TestValues.created,
            command: command
        )
    }
}

extension TagRecordV1 {
    fileprivate static func fixture(id: UUID, name: String) -> TagRecordV1 {
        TagRecordV1(
            id: id,
            name: name,
            normalizedName: "test",
            normalizationVersion: TagLimits.normalizationVersion,
            createdAt: TestValues.created,
            updatedAt: TestValues.created,
            reminders: nil
        )
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}

private enum TagSaveOutcome: Sendable, Equatable {
    case saved(UUID)
    case duplicate(String)
    case otherTagRepositoryError(TagRepositoryError)
    case unexpectedError

    var isSaved: Bool {
        if case .saved = self { true } else { false }
    }
}

private func tagSaveOutcome(
    _ mutation: EncodedTagMutation,
    in repository: SwiftDataReminderRepository
) async -> TagSaveOutcome {
    do {
        return .saved(try await repository.saveTag(mutation).id)
    } catch let TagRepositoryError.duplicateNormalizedName(name) {
        return .duplicate(name)
    } catch let error as TagRepositoryError {
        return .otherTagRepositoryError(error)
    } catch {
        return .unexpectedError
    }
}

private final class TimedSaveBarrier: @unchecked Sendable {
    private let condition = NSCondition()
    private let participants: Int
    private var arrivals = 0

    init(participants: Int) {
        self.participants = participants
    }

    func arriveAndWait() {
        condition.lock()
        arrivals += 1
        if arrivals == participants {
            condition.broadcast()
        } else {
            _ = condition.wait(until: Date().addingTimeInterval(0.5))
        }
        condition.unlock()
    }
}

private func installSaveBarrier(
    _ barrier: TimedSaveBarrier,
    containers: [ModelContainer]
) -> NSObjectProtocol {
    NotificationCenter.default.addObserver(
        forName: ModelContext.willSave,
        object: nil,
        queue: nil
    ) { notification in
        guard let context = notification.object as? ModelContext,
            containers.contains(where: { $0 === context.container })
        else { return }
        barrier.arriveAndWait()
    }
}

private func insertRelatedReminderAndTag(in container: ModelContainer) throws {
    let context = ModelContext(container)
    context.autosaveEnabled = false
    let tag = TagRecordV1.fixture(id: TestValues.tagID, name: "Test")
    let reminder = ReminderRecordV1(
        id: TestValues.reminderID,
        title: "Reminder",
        notes: "Notes",
        urlString: "https://example.com/reminder",
        enabled: true,
        scheduleData: TestValues.validScheduleData,
        createdAt: TestValues.created,
        updatedAt: TestValues.created,
        tags: [tag]
    )
    context.insert(tag)
    context.insert(reminder)
    try context.save()
}

private func insertReminder(scheduleData: Data, in container: ModelContainer) throws {
    let context = ModelContext(container)
    context.autosaveEnabled = false
    context.insert(
        ReminderRecordV1(
            id: TestValues.reminderID,
            title: "Reminder",
            notes: "Notes",
            urlString: "https://example.com/reminder",
            enabled: true,
            scheduleData: scheduleData,
            createdAt: TestValues.created,
            updatedAt: TestValues.created
        ))
    try context.save()
}

private func updateScheduleData(_ scheduleData: Data, in container: ModelContainer) throws {
    let context = ModelContext(container)
    context.autosaveEnabled = false
    let reminder = try #require(
        context.fetch(FetchDescriptor<ReminderRecordV1>()).first {
            $0.id == TestValues.reminderID
        })
    reminder.scheduleData = scheduleData
    try context.save()
}

private func insertTag(
    id: UUID,
    name: String,
    normalizedName: String,
    in container: ModelContainer
) throws {
    let context = ModelContext(container)
    context.autosaveEnabled = false
    context.insert(
        TagRecordV1(
            id: id,
            name: name,
            normalizedName: normalizedName,
            normalizationVersion: TagLimits.normalizationVersion,
            createdAt: TestValues.created,
            updatedAt: TestValues.created
        )
    )
    try context.save()
}

private func prunePersistentHistory(in container: ModelContainer) throws {
    let context = ModelContext(container)
    try context.deleteHistory(HistoryDescriptor<DefaultHistoryTransaction>())
}

private func persistentHistoryCount(in container: ModelContainer) throws -> Int {
    let context = ModelContext(container)
    return try context.fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>()).count
}

private func rawScheduleData(_ state: ScheduleReadState) -> Data {
    switch state {
    case .valid(_, _, let originalData),
        .unsupportedFuture(_, let originalData),
        .corrupt(let originalData),
        .domainInvalid(_, let originalData, _):
        originalData
    }
}
