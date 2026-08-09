import NotificationManagerDomain
import NotificationManagerPersistence
import SwiftData
import XCTest

final class CloudKitSchemaCompatibilityTests: XCTestCase {
    func testProductionConfigurationOpensVersionedCloudKitCompatibleSchema() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "CloudKitSchemaCompatibilityTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "NotificationManager.store")
        let configuration = ModelContainerFactory.productionConfiguration(url: storeURL)

        XCTAssertFalse(configuration.isStoredInMemoryOnly)
        XCTAssertTrue(String(reflecting: configuration.cloudKitDatabase).contains("_automatic: true"))
        XCTAssertNoThrow(try configuration.validate())

        let container = try ModelContainerFactory.makeContainer(configuration: configuration)
        XCTAssertEqual(container.schema.version, Schema.Version(1, 0, 0))
        XCTAssertTrue(container.migrationPlan == NotificationManagerMigrationPlan.self)
        XCTAssertEqual(Set(container.schema.entities.map(\.name)), ["ReminderRecordV1", "TagRecordV1"])
    }

    func testCloudKitSchemaMetadataHasNoUniqueConstraintsAndOnlyApprovedEncryption() throws {
        let schema = Schema(versionedSchema: NotificationManagerSchemaV1.self)
        let reminder = try XCTUnwrap(schema.entities.first { $0.name == "ReminderRecordV1" })
        let tag = try XCTUnwrap(schema.entities.first { $0.name == "TagRecordV1" })

        XCTAssertTrue(reminder.uniquenessConstraints.isEmpty)
        XCTAssertTrue(tag.uniquenessConstraints.isEmpty)
        XCTAssertTrue(reminder.relationshipsByName["tags"]?.isOptional == true)
        XCTAssertTrue(tag.relationshipsByName["reminders"]?.isOptional == true)
        XCTAssertEqual(reminder.relationshipsByName["tags"]?.inverseName, "reminders")
        XCTAssertEqual(tag.relationshipsByName["reminders"]?.inverseName, "tags")

        XCTAssertEqual(
            Set(reminder.attributes.filter(isCloudEncrypted).map(\.name)),
            ["title", "notes", "urlString", "scheduleData"]
        )
        XCTAssertEqual(
            Set(tag.attributes.filter(isCloudEncrypted).map(\.name)),
            ["name", "normalizedName"]
        )
        XCTAssertTrue(reminder.attributes.allSatisfy { $0.options.isEmpty || isCloudEncrypted($0) })
        XCTAssertTrue(tag.attributes.allSatisfy { $0.options.isEmpty || isCloudEncrypted($0) })
    }

    func testProductionConfigurationAcceptsMaximumBoundaryRecordShapeLocally() throws {
        let fixture = try maximumBoundaryAggregateFixture()
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "CloudKitMaximumBoundary-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelContainerFactory.productionConfiguration(
            url: directory.appending(path: "NotificationManager.store")
        )
        let container = try ModelContainerFactory.makeContainer(configuration: configuration)
        let writeContext = ModelContext(container)
        writeContext.autosaveEnabled = false
        fixture.tags.forEach(writeContext.insert)
        writeContext.insert(fixture.reminder)

        try writeContext.save()

        let readContext = ModelContext(container)
        let fetched = try XCTUnwrap(
            readContext.fetch(FetchDescriptor<ReminderRecordV1>()).first
        )
        XCTAssertEqual(fetched.title.utf8.count, ReminderLimits.titleBytes)
        XCTAssertEqual(fetched.notes?.utf8.count, ReminderLimits.notesBytes)
        XCTAssertEqual(fetched.urlString?.utf8.count, ReminderLimits.urlBytes)
        XCTAssertEqual(fetched.scheduleData.count, ReminderLimits.scheduleBytes)
        XCTAssertEqual(fetched.tags?.count, ReminderLimits.tagCount)
        XCTAssertTrue((fetched.tags ?? []).allSatisfy {
            $0.name.utf8.count == TagLimits.nameBytes
                && $0.normalizedName.utf8.count == TagLimits.normalizedNameBytes
        })
    }

    private func isCloudEncrypted(_ attribute: Schema.Attribute) -> Bool {
        String(reflecting: attribute.options) == "[allowsCloudEncryption]"
    }
}

private struct MaximumBoundaryAggregateFixture {
    let reminder: ReminderRecordV1
    let tags: [TagRecordV1]
}

private func maximumBoundaryAggregateFixture() throws -> MaximumBoundaryAggregateFixture {
    let timestamp = Date(timeIntervalSince1970: 2_229_984_000)
    let tags = (0..<ReminderLimits.tagCount).map { index in
        let prefix = String(format: "tag-%03d-", index)
        let name = prefix + String(repeating: "x", count: TagLimits.nameBytes - prefix.utf8.count)
        return TagRecordV1(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
            name: name,
            normalizedName: name,
            normalizationVersion: TagLimits.normalizationVersion,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }
    let title = String(repeating: "T", count: ReminderLimits.titleBytes)
    let notes = String(repeating: "N", count: ReminderLimits.notesBytes)
    let urlPrefix = "https://example.com/"
    let urlString = urlPrefix + String(
        repeating: "u",
        count: ReminderLimits.urlBytes - urlPrefix.utf8.count
    )
    let scheduleData = Data(repeating: 0x7B, count: ReminderLimits.scheduleBytes)
    let draft = ReminderDraft(
        id: UUID(uuidString: "123e4567-e89b-12d3-a456-426614174000")!,
        title: title,
        notes: notes,
        urlString: urlString,
        enabled: true,
        scheduleChange: .preserveOriginal,
        originalScheduleData: scheduleData,
        tagIDs: Set(tags.map(\.id)),
        createdAt: timestamp,
        updatedAt: timestamp
    )
    let aggregate = try ReminderAggregateValidator().validate(draft)
    let reminder = ReminderRecordV1(
        id: aggregate.id,
        title: aggregate.title,
        notes: aggregate.notes,
        urlString: aggregate.urlString,
        enabled: aggregate.enabled,
        scheduleData: aggregate.scheduleData,
        createdAt: aggregate.createdAt,
        updatedAt: aggregate.updatedAt,
        tags: tags
    )
    return MaximumBoundaryAggregateFixture(reminder: reminder, tags: tags)
}
