import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import SwiftData
import Testing
@testable import NotificationManagerPersistence

@Suite(.serialized) struct SwiftDataReminderRepositoryTests {
    @Test func versionedSchemaHasCloudKitCompatibleOptionalInverseRelationshipsAndExactEncryption() throws {
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
        #expect(NotificationManagerMigrationPlan.schemas.first?.versionIdentifier == Schema.Version(1, 0, 0))
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
            .fixture(title: "Updated", tagIDs: [tag.id], updatedAt: TestValues.later)
        )
        #expect(updated.id == inserted.id)
        #expect(try await repository.reminder(id: inserted.id) == updated)
        #expect(try await repository.fetchCompleteSnapshot().reminders.count == 1)
    }

    @Test func metadataOnlyMappingsPreserveUnsupportedAndCorruptRawBytesExactly() async throws {
        let repository = try SwiftDataReminderRepository.inMemory()
        let unsupported = Data(
            #"{"format":"notification-manager.schedule","future":true,"version":4294967295}"#.utf8
        )
        _ = try await repository.save(.fixture(scheduleData: unsupported))

        let unsupportedEdit = try await repository.save(
            .fixture(title: "Metadata edit", scheduleData: unsupported, updatedAt: TestValues.later)
        )
        #expect(rawScheduleData(unsupportedEdit.schedule) == unsupported)

        let corrupt = Data([0xFF, 0x00, 0x7B])
        let corruptEdit = try await repository.save(
            .fixture(title: "Second metadata edit", scheduleData: corrupt, updatedAt: TestValues.latest)
        )
        #expect(rawScheduleData(corruptEdit.schedule) == corrupt)
        #expect(rawScheduleData(try await repository.reminder(id: TestValues.reminderID)!.schedule) == corrupt)
    }

    @Test func replacingScheduleBytesReturnsSemanticallyEquivalentDecodedSnapshot() async throws {
        let repository = try SwiftDataReminderRepository.inMemory()
        _ = try await repository.save(.fixture(scheduleData: Data([0xFF])))
        let definition = TestValues.schedule
        let encoded = try SchedulePayloadCodec().encodeCurrent(definition)

        let updated = try await repository.save(
            .fixture(scheduleData: encoded, updatedAt: TestValues.later)
        )

        guard case let .valid(decoded, version, originalData) = updated.schedule else {
            Issue.record("Expected a valid replacement schedule")
            return
        }
        #expect(decoded == definition)
        #expect(version == SchedulePayloadCodec.currentVersion)
        #expect(originalData == encoded)
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

        await #expect(throws: PersistenceError.duplicateNormalizedTagName("test")) {
            try await repository.saveTag(.fixture(id: TestValues.otherTagID, name: "test"))
        }

        let snapshot = try await repository.fetchCompleteSnapshot()
        #expect(snapshot.tags == [first])
        #expect(snapshot.tags.first?.id == TestValues.tagID)
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
        let repository = try SwiftDataReminderRepository.inMemory()
        _ = try await repository.save(.fixture(scheduleData: Data([0xFF, 0xFE])))

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
        let first = UserDefaultsDeviceNotificationPreferenceStore(suiteName: suiteA)
        let sameSuite = UserDefaultsDeviceNotificationPreferenceStore(suiteName: suiteA)
        let otherSuite = UserDefaultsDeviceNotificationPreferenceStore(suiteName: suiteB)

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
}

private extension EncodedReminderMutation {
    static func fixture(
        title: String = "Reminder",
        scheduleData: Data = Data(
            #"{"format":"notification-manager.schedule","payload":{},"version":2}"#.utf8
        ),
        tagIDs: Set<UUID> = [],
        updatedAt: Date = TestValues.created
    ) -> EncodedReminderMutation {
        EncodedReminderMutation(
            id: TestValues.reminderID,
            title: title,
            notes: "Notes",
            urlString: "https://example.com/reminder",
            enabled: true,
            scheduleData: scheduleData,
            tagIDs: tagIDs,
            createdAt: TestValues.created,
            updatedAt: updatedAt
        )
    }
}

private extension EncodedTagMutation {
    static func fixture(id: UUID, name: String) -> EncodedTagMutation {
        let normalizedName = try! TagNameNormalizerV1().normalize(name)
        return EncodedTagMutation(
            id: id,
            name: name,
            normalizedName: normalizedName,
            normalizationVersion: TagLimits.normalizationVersion,
            createdAt: TestValues.created,
            updatedAt: TestValues.created
        )
    }
}

private extension TagRecordV1 {
    static func fixture(id: UUID, name: String) -> TagRecordV1 {
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

private func rawScheduleData(_ state: ScheduleReadState) -> Data {
    switch state {
    case let .valid(_, _, originalData),
         let .unsupportedFuture(_, originalData),
         let .corrupt(originalData),
         let .domainInvalid(_, originalData, _):
        originalData
    }
}
