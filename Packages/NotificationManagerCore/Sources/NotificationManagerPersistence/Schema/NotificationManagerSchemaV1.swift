import SwiftData

public enum NotificationManagerSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [ReminderRecordV1.self, TagRecordV1.self]
    }
}
