import NotificationManagerPersistence
import SwiftData

@MainActor
struct PersistenceCompositionRoot {
    typealias ContainerFactory = @MainActor (ModelConfiguration) throws -> ModelContainer
    typealias EnvironmentFactory = @MainActor (ModelContainer) -> AppEnvironment

    let configuration: ModelConfiguration
    private let makeContainer: ContainerFactory
    private let makeEnvironment: EnvironmentFactory

    #if DEBUG
    private let debugSchemaBootstrapper: DebugCloudKitSchemaBootstrapper

    init(
        configuration: ModelConfiguration = ModelContainerFactory.productionConfiguration(),
        debugSchemaBootstrapper: DebugCloudKitSchemaBootstrapper =
            DebugCloudKitSchemaBootstrapper(),
        makeContainer: @escaping ContainerFactory = ModelContainerFactory.makeContainer,
        makeEnvironment: @escaping EnvironmentFactory
    ) {
        self.configuration = configuration
        self.debugSchemaBootstrapper = debugSchemaBootstrapper
        self.makeContainer = makeContainer
        self.makeEnvironment = makeEnvironment
    }
    #else
    init(
        configuration: ModelConfiguration = ModelContainerFactory.productionConfiguration(),
        makeContainer: @escaping ContainerFactory = ModelContainerFactory.makeContainer,
        makeEnvironment: @escaping EnvironmentFactory
    ) {
        self.configuration = configuration
        self.makeContainer = makeContainer
        self.makeEnvironment = makeEnvironment
    }
    #endif

    func open() throws -> AppEnvironment {
        #if DEBUG
        try debugSchemaBootstrapper.initializeIfRequested(configuration: configuration)
        #endif
        let container = try makeContainer(configuration)
        return makeEnvironment(container)
    }
}
