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
        private let iCloudSyncModel: ICloudSyncStatusModel
        private let tagModel: TagManagementModel
        private let appIconModel: AppIconSelectionModel
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
            iCloudSyncModel = ICloudSyncStatusModel(
                accountAvailability: .available,
                syncActivity: .succeeded,
                notificationCenter: NotificationCenter(),
                accountStatus: { .available }
            )
            let iconMode =
                ProcessInfo.processInfo.argumentValue(
                    following: "-ui-app-icon-mode"
                ) ?? "normal"
            appIconModel = AppIconSelectionModel(
                service: Task15AppIconService(mode: iconMode)
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
                        SettingsView(
                            model: settingsModel,
                            iCloudModel: iCloudSyncModel,
                            tagModel: tagModel,
                            appIconModel: appIconModel
                        )
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

    @MainActor
    private final class Task15AppIconService: AppIconServicing {
        let supportsAlternateIcons: Bool
        private(set) var alternateIconName: String?
        private let failsChanges: Bool

        init(mode: String) {
            supportsAlternateIcons = mode != "unsupported"
            alternateIconName = nil
            failsChanges = mode == "failure"
        }

        func setAlternateIconName(_ name: String?) async throws {
            if failsChanges {
                throw Task15AppIconError.changeFailed
            }
            alternateIconName = name
        }
    }

    private enum Task15AppIconError: Error {
        case changeFailed
    }

    extension ProcessInfo {
        fileprivate func argumentValue(following flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag),
                arguments.indices.contains(index + 1)
            else {
                return nil
            }
            return arguments[index + 1]
        }
    }
#endif
