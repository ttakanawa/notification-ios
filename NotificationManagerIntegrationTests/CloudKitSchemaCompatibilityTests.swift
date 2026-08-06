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

    private func isCloudEncrypted(_ attribute: Schema.Attribute) -> Bool {
        String(reflecting: attribute.options) == "[allowsCloudEncryption]"
    }
}
