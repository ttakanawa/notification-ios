import Foundation
import SwiftData

public enum ModelContainerFactory {
    public static let schema = Schema(versionedSchema: NotificationManagerSchemaV1.self)

    public static func productionConfiguration(
        name: String = "NotificationManager",
        url: URL? = nil
    ) -> ModelConfiguration {
        if let url {
            return ModelConfiguration(
                name,
                schema: schema,
                url: url,
                allowsSave: true,
                cloudKitDatabase: .automatic
            )
        }
        return ModelConfiguration(
            name,
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .automatic
        )
    }

    public static func inMemoryConfiguration(
        name: String = "NotificationManagerInMemory"
    ) -> ModelConfiguration {
        ModelConfiguration(
            name,
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            cloudKitDatabase: .none
        )
    }

    public static func makeContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            migrationPlan: NotificationManagerMigrationPlan.self,
            configurations: [configuration]
        )
    }

    public static func production() throws -> ModelContainer {
        try makeContainer(configuration: productionConfiguration())
    }

    public static func inMemory() throws -> ModelContainer {
        try makeContainer(configuration: inMemoryConfiguration())
    }
}
