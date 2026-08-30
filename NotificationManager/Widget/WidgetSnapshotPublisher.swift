import Foundation
import NotificationManagerWidgetSupport
import OSLog

actor WidgetSnapshotPublisher {
    typealias Reload = @Sendable () -> Void

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "org.tknw.punctual",
        category: "WidgetSnapshotPublication"
    )

    private let store: WidgetSnapshotFileStore
    private let reload: Reload
    private var highestAcceptedGeneration: UInt64?

    init(
        store: WidgetSnapshotFileStore,
        reload: @escaping Reload
    ) {
        self.store = store
        self.reload = reload
    }

    func publish(_ snapshot: WidgetSnapshot, generation: UInt64) async {
        if let highestAcceptedGeneration,
            generation <= highestAcceptedGeneration
        {
            return
        }
        highestAcceptedGeneration = generation

        do {
            if try store.write(snapshot) == .changed {
                reload()
            }
        } catch {
            Self.logger.error(
                "Widget snapshot write failed: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
