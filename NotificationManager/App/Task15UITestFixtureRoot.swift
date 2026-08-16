#if DEBUG
    import Foundation
    import NotificationManagerApplication
    import NotificationManagerPersistence
    import SwiftUI

    @MainActor
    struct Task15UITestFixtureRoot: View {
        let scenario: String

        @State private var tagsSeeded = false
        private let settingsModel: NotificationSettingsModel
        private let tagModel: TagManagementModel
        private let tagUseCase: TagManagementUseCase
        private let dataUnavailableActions: DataUnavailableActions

        init(scenario: String) {
            self.scenario = scenario
            let authorization = Task15AuthorizationController(rawValue: 1)
            let cleaner = Task15PendingCleaner()
            settingsModel = NotificationSettingsModel(
                preferenceStore: Task15PreferenceStore(enabled: false),
                authorizationProvider: authorization,
                authorizationRequester: authorization,
                pendingCleaner: cleaner,
                reconciler: nil
            )

            let repository: SwiftDataReminderRepository
            do {
                repository = try SwiftDataReminderRepository.inMemory()
            } catch {
                preconditionFailure("Task 15 UI fixture requires an in-memory repository: \(error)")
            }
            let useCase = TagManagementUseCase(
                repository: repository,
                normalizer: TagNameNormalizerV1(),
                now: { Date(timeIntervalSince1970: 1_786_003_200) }
            )
            tagUseCase = useCase
            tagModel = TagManagementModel(repository: repository, useCase: useCase)

            let unavailableAuthorization = Task15AuthorizationController(rawValue: 2)
            dataUnavailableActions = DataUnavailableActions(
                preferenceStore: Task15PreferenceStore(enabled: true),
                authorizationProvider: unavailableAuthorization,
                authorizationRequester: unavailableAuthorization,
                pendingCleaner: Task15PendingCleaner(),
                retry: {}
            )
        }

        var body: some View {
            switch scenario {
            case "settings":
                NavigationStack {
                    if tagsSeeded {
                        SettingsView(model: settingsModel, tagModel: tagModel)
                    } else {
                        ProgressView()
                            .task { await seedTags() }
                    }
                }
            case "data-unavailable":
                DataUnavailableView(actions: dataUnavailableActions)
            case "notification-unavailable":
                NotificationNoLongerAvailableView()
            default:
                NotificationNoLongerAvailableView()
            }
        }

        private func seedTags() async {
            _ = try? await tagUseCase.create(
                name: "Travel",
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
            )
            tagsSeeded = true
        }
    }

    private actor Task15PreferenceStore: DeviceNotificationPreferenceStore {
        private var enabled: Bool

        init(enabled: Bool) {
            self.enabled = enabled
        }

        func isEnabled() -> Bool { enabled }

        func setEnabled(_ enabled: Bool) {
            self.enabled = enabled
        }
    }

    private actor Task15AuthorizationController:
        NotificationAuthorizationProviding,
        NotificationAuthorizationRequesting
    {
        private let rawValue: Int

        init(rawValue: Int) {
            self.rawValue = rawValue
        }

        func currentAuthorization() -> NotificationAuthorizationSnapshot {
            NotificationAuthorizationService.map(rawValue: rawValue)
        }

        func requestAuthorization() throws -> Bool { false }
    }

    private actor Task15PendingCleaner: PendingAppNotificationCleaning {
        func removeAllPendingAppNotificationsReportingFailure() async throws {}
    }
#endif
