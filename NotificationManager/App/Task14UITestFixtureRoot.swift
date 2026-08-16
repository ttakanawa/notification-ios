#if DEBUG
    import Foundation
    import NotificationManagerApplication
    import NotificationManagerDomain
    import NotificationManagerPersistence
    import SwiftUI

    @MainActor
    struct Task14UITestFixtureRoot: View {
        @State private var router: AppRouter
        @State private var listModel: ReminderListModel

        init(arguments: [String] = ProcessInfo.processInfo.arguments) {
            let composition = Task14UITestFixtureComposition.make(arguments: arguments)
            _router = State(initialValue: composition.router)
            _listModel = State(initialValue: composition.listModel)
        }

        var body: some View {
            AdaptiveRootView(router: router, listModel: listModel)
        }
    }

    @MainActor
    private struct Task14UITestFixtureComposition {
        let router: AppRouter
        let listModel: ReminderListModel

        static func make(arguments: [String]) -> Self {
            let scenario = scenarioName(in: arguments)
            let fixture = fixture(for: scenario)
            let enabledCapacityAction = Task14EnabledCapacityAction()
            let actionCoordinator = ReminderActionCoordinator(
                handlers: ReminderActionHandlers(
                    setEnabled: { command in
                        if scenario == "enabled-capacity" {
                            return await enabledCapacityAction.execute(command)
                        }
                        return .saved(command.reminderID)
                    },
                    delete: { _ in }
                )
            )
            let listModel = ReminderListModel(
                snapshot: ReminderListSnapshot(
                    generation: 1,
                    items: fixture.items,
                    availableTags: fixture.items.flatMap(\.tags)
                ),
                actions: actionCoordinator
            )
            let createForm: @MainActor @Sendable () -> ReminderFormModel? =
                switch scenario {
                case "empty-list":
                    { makeNewForm() }
                case "new-expired-schedule":
                    { makeExpiredNewForm() }
                default:
                    { nil }
                }
            let tagModel =
                scenario == "navigation-with-tags"
                ? makeTagManagementModel()
                : nil
            let router = AppRouter(
                actions: actionCoordinator,
                tagManagementModel: tagModel,
                createForm: createForm
            )

            for form in fixture.forms {
                router.registerFormIfAbsent(form)
            }

            return Self(router: router, listModel: listModel)
        }

        private static func scenarioName(in arguments: [String]) -> String {
            guard let flagIndex = arguments.firstIndex(of: "-ui-scenario"),
                arguments.indices.contains(flagIndex + 1)
            else {
                return "navigation"
            }
            return arguments[flagIndex + 1]
        }

        private static func fixture(for scenario: String) -> Task14ScenarioFixture {
            switch scenario {
            case "empty-list", "new-expired-schedule":
                return Task14ScenarioFixture(items: [], forms: [])
            case "localized-custom-rule":
                return editableFixture(
                    id: uuid("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
                    title: "Localized custom",
                    repeatPresentation: .custom(
                        localizedSummary: "毎週月曜日に繰り返します。",
                        canonicalEnglishDisclosure: "Every Monday"
                    )
                )
            case "unsupported-schedule":
                return unsupportedFixture()
            case "one-time-row":
                return oneTimeFixture()
            case "capacity-and-expired-confirmations":
                return editableFixture(
                    id: uuid("dddddddd-dddd-dddd-dddd-dddddddddddd"),
                    title: "Capacity edit",
                    repeatPresentation: .standard(localizedSummary: "Every week"),
                    actions: capacityConfirmationActions()
                )
            case "enabled-capacity":
                return enabledCapacityFixture()
            case "slow-persistence":
                return editableFixture(
                    id: uuid("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
                    title: "Visa renewal",
                    repeatPresentation: .standard(localizedSummary: "Every week"),
                    actions: slowPersistenceActions
                )
            default:
                return editableFixture(
                    id: uuid("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
                    title: "Visa renewal",
                    repeatPresentation: .standard(localizedSummary: "Every week")
                )
            }
        }

        private static func editableFixture(
            id: UUID,
            title: String,
            repeatPresentation: SavedRepeatPresentation,
            actions: ReminderFormActions = inertFormActions
        ) -> Task14ScenarioFixture {
            let notes = "Renewal documents"
            let snapshot = makeSnapshot(
                id: id,
                title: title,
                notes: notes,
                schedule: .valid(schedule, sourceVersion: 1, originalData: Data([1]))
            )
            let item = makeListItem(
                id: id,
                title: title,
                notes: notes,
                lifecycleStatus: .active,
                sourceWallClock: schedule.source,
                localizedRepeatSummary: repeatPresentation.localizedSummary,
                isRepeating: true,
                tags: [fixtureTag]
            )
            let form = ReminderFormModel(
                snapshot: snapshot,
                savedRepeatPresentation: repeatPresentation,
                now: evaluationNow,
                actions: actions
            )
            return Task14ScenarioFixture(
                items: [item],
                forms: [form]
            )
        }

        private static func unsupportedFixture() -> Task14ScenarioFixture {
            let id = uuid("cccccccc-cccc-cccc-cccc-cccccccccccc")
            let title = "Future schedule"
            let snapshot = makeSnapshot(
                id: id,
                title: title,
                schedule: .unsupportedFuture(version: 99, originalData: Data([99, 1, 2]))
            )
            let item = makeListItem(
                id: id,
                title: title,
                lifecycleStatus: .updateRequired,
                sourceWallClock: nil,
                localizedRepeatSummary: nil
            )
            let form = ReminderFormModel(
                snapshot: snapshot,
                savedRepeatPresentation: nil,
                now: evaluationNow,
                actions: inertFormActions
            )
            return Task14ScenarioFixture(
                items: [item],
                forms: [form]
            )
        }

        private static func enabledCapacityFixture() -> Task14ScenarioFixture {
            let id = uuid("ffffffff-ffff-ffff-ffff-ffffffffffff")
            let item = makeListItem(
                id: id,
                title: "Capacity enable",
                lifecycleStatus: .disabled,
                sourceWallClock: schedule.source,
                localizedRepeatSummary: "Every day",
                isRepeating: true,
                enabled: false
            )
            return Task14ScenarioFixture(
                items: [item],
                forms: []
            )
        }

        private static func oneTimeFixture() -> Task14ScenarioFixture {
            let id = uuid("99999999-9999-9999-9999-999999999999")
            let oneTimeSchedule = ScheduleDefinition(
                source: schedule.source,
                rule: .none,
                end: .never,
                early: nil
            )
            let snapshot = makeSnapshot(
                id: id,
                title: "One-time reminder",
                schedule: .valid(oneTimeSchedule, sourceVersion: 1, originalData: Data([1]))
            )
            let item = makeListItem(
                id: id,
                title: "One-time reminder",
                lifecycleStatus: .active,
                sourceWallClock: oneTimeSchedule.source,
                localizedRepeatSummary: "One time",
                isRepeating: false
            )
            return Task14ScenarioFixture(
                items: [item],
                forms: [
                    ReminderFormModel(
                        snapshot: snapshot,
                        savedRepeatPresentation: .standard(localizedSummary: "One time"),
                        now: evaluationNow,
                        actions: inertFormActions
                    )
                ]
            )
        }

        private static func makeNewForm() -> ReminderFormModel {
            ReminderFormModel(
                newReminderID: uuid("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"),
                now: evaluationNow,
                actions: inertFormActions,
                defaultTimeZone: fixtureTimeZone
            )
        }

        private static func makeExpiredNewForm() -> ReminderFormModel {
            let model = ReminderFormModel(
                newReminderID: uuid("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"),
                now: evaluationNow,
                actions: expiredCreateActions(),
                defaultTimeZone: fixtureTimeZone
            )
            model.title = "Expired one-shot reminder"
            model.sourceDate = SourceDate(year: 2040, month: 7, day: 3)
            model.sourceTime = SourceTime(hour: 9, minute: 30)
            return model
        }

        private static func makeSnapshot(
            id: UUID,
            title: String,
            notes: String? = nil,
            schedule: ScheduleReadState
        ) -> ReminderSnapshot {
            ReminderSnapshot(
                id: id,
                title: title,
                notes: notes,
                urlString: nil,
                enabled: true,
                schedule: schedule,
                tagIDs: [],
                createdAt: evaluationNow,
                updatedAt: evaluationNow
            )
        }

        private static func makeListItem(
            id: UUID,
            title: String,
            notes: String? = nil,
            lifecycleStatus: LifecycleStatus,
            sourceWallClock: SourceWallClock?,
            localizedRepeatSummary: String?,
            isRepeating: Bool = false,
            tags: [ReminderTagPresentation] = [],
            enabled: Bool = true
        ) -> ReminderListItemPresentation {
            ReminderListItemPresentation(
                id: id,
                title: title,
                notes: notes,
                reminderStatus: ReminderStatus(primary: lifecycleStatus, secondary: []),
                deviceSchedulingStatus: lifecycleStatus == .active ? .scheduled : .notApplicable,
                nextPresentation: lifecycleStatus == .active
                    ? .directOSFire(authoritative: sourceInstant, foundationPreview: sourceInstant)
                    : nil,
                nextReason: lifecycleStatus == .active ? .main : nil,
                sourceWallClock: sourceWallClock,
                localizedRepeatSummary: localizedRepeatSummary,
                isRepeating: isRepeating,
                tags: tags,
                enabled: enabled,
                updatedAt: evaluationNow
            )
        }

        private static func capacityConfirmationActions() -> ReminderFormActions {
            let capacityInstant = sourceInstant
            let expiredEvaluationNow = evaluationNow
            return ReminderFormActions(
                save: { draft, capacityConsent, expiredScheduleConsent in
                    if capacityConsent == .notProvided {
                        return .requiresCapacityConfirmation(
                            CapacityWarning(
                                reminderID: draft.id,
                                earliestGroupID: AlertGroupID(
                                    reminderID: draft.id,
                                    baseOccurrenceInstant: capacityInstant
                                ),
                                planningCapacity: 60
                            ))
                    }
                    if expiredScheduleConsent == .notProvided {
                        return .requiresExpiredScheduleConfirmation(
                            ExpiredScheduleWarning(
                                reminderID: draft.id,
                                evaluationNow: expiredEvaluationNow
                            ))
                    }
                    return .saved(draft.id)
                },
                delete: { _ in }
            )
        }

        private static let inertFormActions = ReminderFormActions(
            save: { draft, _, _ in .saved(draft.id) },
            delete: { _ in }
        )

        private static func expiredCreateActions() -> ReminderFormActions {
            let expiredEvaluationNow = evaluationNow
            return ReminderFormActions(
                save: { draft, _, expiredScheduleConsent in
                    if expiredScheduleConsent == .notProvided {
                        return .requiresExpiredScheduleConfirmation(
                            ExpiredScheduleWarning(
                                reminderID: draft.id,
                                evaluationNow: expiredEvaluationNow
                            ))
                    }
                    return .saved(draft.id)
                },
                delete: { _ in }
            )
        }

        private static let slowPersistenceActions = ReminderFormActions(
            save: { draft, _, _ in
                try? await Task.sleep(for: .seconds(2))
                return .saved(draft.id)
            },
            delete: { _ in
                try? await Task.sleep(for: .seconds(2))
            }
        )

        @MainActor
        private static func makeTagManagementModel() -> TagManagementModel {
            let repository: SwiftDataReminderRepository
            do {
                repository = try SwiftDataReminderRepository.inMemory()
            } catch {
                preconditionFailure("Task 14 UI fixture requires an in-memory repository: \(error)")
            }
            let now = Date(timeIntervalSince1970: 2_225_052_800)
            return TagManagementModel(
                repository: repository,
                useCase: TagManagementUseCase(
                    repository: repository,
                    normalizer: TagNameNormalizerV1(),
                    now: { now }
                )
            )
        }

        private static let schedule = ScheduleDefinition(
            source: SourceWallClock(
                year: 2040,
                month: 8,
                day: 31,
                hour: 9,
                minute: 30,
                timeZoneIdentifier: "America/New_York"
            ),
            rule: .weekly(
                interval: 1,
                weekdaySetKind: .explicit,
                weekdays: [.monday]
            ),
            end: .never,
            early: nil
        )

        private static let fixtureTag = ReminderTagPresentation(
            id: uuid("77777777-7777-7777-7777-777777777777"),
            name: "Travel",
            normalizedName: "travel"
        )

        private static let evaluationNow = Date(timeIntervalSince1970: 2_225_052_800)
        private static let sourceInstant = Date(timeIntervalSince1970: 2_228_349_000)
        private static let fixtureTimeZone = TimeZone(identifier: "Africa/Abidjan")!

        private static func uuid(_ value: String) -> UUID {
            guard let id = UUID(uuidString: value) else {
                preconditionFailure("Invalid Task 14 UI fixture UUID")
            }
            return id
        }
    }

    private actor Task14EnabledCapacityAction {
        func execute(_ command: SetReminderEnabledCommand) -> SaveReminderOutcome {
            guard command.enabled, command.capacityConsent == .notProvided else {
                return .saved(command.reminderID)
            }
            return .requiresCapacityConfirmation(
                CapacityWarning(
                    reminderID: command.reminderID,
                    earliestGroupID: AlertGroupID(
                        reminderID: command.reminderID,
                        baseOccurrenceInstant: Date(timeIntervalSince1970: 2_229_868_200)
                    ),
                    planningCapacity: 60
                ))
        }
    }

    @MainActor
    private struct Task14ScenarioFixture {
        let items: [ReminderListItemPresentation]
        let forms: [ReminderFormModel]
    }
#endif
