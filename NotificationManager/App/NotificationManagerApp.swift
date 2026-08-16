import Foundation
import NotificationManagerPersistence
import SwiftData
import SwiftUI

@main
struct NotificationManagerApp: App {
    @UIApplicationDelegateAdaptor(NotificationApplicationDelegate.self)
    private var notificationDelegate

    var body: some Scene {
        WindowGroup {
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
                    let scenario = Self.uiScenario
                    if ["settings", "data-unavailable", "notification-unavailable"]
                        .contains(scenario)
                    {
                        Task15UITestFixtureRoot(scenario: scenario)
                    } else {
                        Task14UITestFixtureRoot()
                    }
                } else {
                    AppBootstrapRoot(notificationDelegate: notificationDelegate)
                }
            #else
                AppBootstrapRoot(notificationDelegate: notificationDelegate)
            #endif
        }
    }

    private static var uiScenario: String {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ui-scenario"),
            arguments.indices.contains(index + 1)
        else {
            return "navigation"
        }
        return arguments[index + 1]
    }
}

private struct AppBootstrapRoot: View {
    @State private var bootstrapper: AppBootstrapper

    init(notificationDelegate: NotificationApplicationDelegate) {
        _bootstrapper = State(
            initialValue: AppBootstrapper.production(
                notificationDelegate: notificationDelegate
            ))
    }

    var body: some View {
        Group {
            switch bootstrapper.state {
            case .loading:
                ProgressView(
                    LocalizedStringResource(
                        "common.app-name",
                        table: "Common"
                    )
                )
                .accessibilityIdentifier("app-bootstrap.loading")
            case .ready(let environment):
                ReadyAppRoot(environment: environment)
            case .dataUnavailable(let actions):
                DataUnavailableView(actions: actions)
            }
        }
        .task { await bootstrapper.start() }
    }
}

private struct ReadyAppRoot: View {
    let environment: AppEnvironment

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .task { await environment.start() }
            .onChange(of: scenePhase) { _, phase in
                Task {
                    switch phase {
                    case .active:
                        await environment.enterForeground()
                    case .background:
                        await environment.enterBackground()
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let container = environment.container {
            AdaptiveRootView(
                router: environment.router,
                listModel: environment.listModel
            )
            .background {
                SwiftDataModelImportObserver {
                    await environment.modelSnapshotChanged()
                }
            }
            .modelContainer(container)
        } else {
            AdaptiveRootView(
                router: environment.router,
                listModel: environment.listModel
            )
        }
    }
}

private struct SwiftDataModelImportObserver: View {
    @Query private var reminders: [ReminderRecordV1]
    @Query private var tags: [TagRecordV1]
    @State private var changeObserver: ModelImportChangeObserver<ModelSnapshotFingerprint>

    init(
        changeHandler: @escaping @MainActor @Sendable () async -> Void
    ) {
        _changeObserver = State(
            initialValue: ModelImportChangeObserver(
                changeHandler: changeHandler
            ))
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task(id: fingerprint) {
                await changeObserver.observe(fingerprint)
            }
    }

    private var fingerprint: ModelSnapshotFingerprint {
        ModelSnapshotFingerprint(reminders: reminders, tags: tags)
    }
}

private struct ModelSnapshotFingerprint: Sendable, Hashable {
    private struct Reminder: Sendable, Hashable {
        let id: UUID
        let title: String
        let notes: String?
        let urlString: String?
        let enabled: Bool
        let scheduleData: Data
        let createdAt: Date
        let updatedAt: Date
        let tagIDs: [UUID]
    }

    private struct Tag: Sendable, Hashable {
        let id: UUID
        let name: String
        let normalizedName: String
        let normalizationVersion: String
        let createdAt: Date
        let updatedAt: Date
    }

    private let reminders: [Reminder]
    private let tags: [Tag]

    @MainActor
    init(reminders: [ReminderRecordV1], tags: [TagRecordV1]) {
        self.reminders = reminders.map { record in
            Reminder(
                id: record.id,
                title: record.title,
                notes: record.notes,
                urlString: record.urlString,
                enabled: record.enabled,
                scheduleData: record.scheduleData,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                tagIDs: (record.tags ?? []).map(\.id).sorted(by: Self.uuidOrder)
            )
        }.sorted { Self.uuidOrder($0.id, $1.id) }
        self.tags = tags.map { record in
            Tag(
                id: record.id,
                name: record.name,
                normalizedName: record.normalizedName,
                normalizationVersion: record.normalizationVersion,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt
            )
        }.sorted { Self.uuidOrder($0.id, $1.id) }
    }

    private static func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString.lowercased() < rhs.uuidString.lowercased()
    }
}
