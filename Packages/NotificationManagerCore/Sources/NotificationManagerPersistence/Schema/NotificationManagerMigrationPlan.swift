import SwiftData

public enum NotificationManagerMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [NotificationManagerSchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}
