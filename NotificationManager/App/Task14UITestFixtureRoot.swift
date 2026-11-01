#if DEBUG
    import Foundation
    import NotificationManagerApplication
    import NotificationManagerDomain
    import NotificationManagerPersistence
    import SwiftData
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
            let tagModel: TagManagementModel? =
                switch scenario {
                case "navigation-with-tags":
                    makeTagManagementModel(delaysAssociationRemoval: false)
                case "slow-tag-removal":
                    makeTagManagementModel(delaysAssociationRemoval: true)
                default:
                    nil
                }
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
            case "tag-filter":
                return tagFilterFixture()
            case "time-zone-filter":
                return timeZoneFilterFixture()
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

        private static func timeZoneFilterFixture() -> Task14ScenarioFixture {
            let newYork = makeListItem(
                id: uuid("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
                title: "New York reminder",
                lifecycleStatus: .active,
                sourceWallClock: schedule.source,
                localizedRepeatSummary: nil
            )
            let manila = makeListItem(
                id: uuid("12121212-1212-1212-1212-121212121212"),
                title: "Manila reminder",
                lifecycleStatus: .active,
                sourceWallClock: SourceWallClock(
                    year: 2040,
                    month: 9,
                    day: 1,
                    hour: 9,
                    minute: 30,
                    timeZoneIdentifier: "Asia/Manila"
                ),
                localizedRepeatSummary: nil
            )
            return Task14ScenarioFixture(
                items: [newYork, manila],
                forms: []
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

        private static func tagFilterFixture() -> Task14ScenarioFixture {
            let tags = [
                ReminderTagPresentation(
                    id: uuid("11111111-1111-1111-1111-111111111111"),
                    name: "Family",
                    normalizedName: "family"
                ),
                ReminderTagPresentation(
                    id: uuid("22222222-2222-2222-2222-222222222222"),
                    name: "Food & Drink",
                    normalizedName: "food & drink"
                ),
                ReminderTagPresentation(
                    id: uuid("33333333-3333-3333-3333-333333333333"),
                    name: "Personal",
                    normalizedName: "personal"
                ),
                ReminderTagPresentation(
                    id: uuid("44444444-4444-4444-4444-444444444444"),
                    name: "Tech",
                    normalizedName: "tech"
                ),
                fixtureTag,
                ReminderTagPresentation(
                    id: uuid("55555555-5555-5555-5555-555555555555"),
                    name: "Health & Wellness",
                    normalizedName: "health & wellness"
                ),
                ReminderTagPresentation(
                    id: uuid("66666666-6666-6666-6666-666666666666"),
                    name: "Learning & Education",
                    normalizedName: "learning & education"
                ),
                ReminderTagPresentation(
                    id: uuid("88888888-8888-8888-8888-888888888888"),
                    name: "Local Community Events",
                    normalizedName: "local community events"
                ),
                ReminderTagPresentation(
                    id: uuid("99999999-9999-9999-9999-999999999998"),
                    name: "Professional Development",
                    normalizedName: "professional development"
                ),
                ReminderTagPresentation(
                    id: uuid("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1"),
                    name: "Shopping & Errands",
                    normalizedName: "shopping & errands"
                ),
                ReminderTagPresentation(
                    id: uuid("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1"),
                    name: "Sports & Fitness",
                    normalizedName: "sports & fitness"
                ),
                ReminderTagPresentation(
                    id: uuid("cccccccc-cccc-cccc-cccc-ccccccccccc1"),
                    name: "Volunteering & Community",
                    normalizedName: "volunteering & community"
                ),
                ReminderTagPresentation(
                    id: uuid("dddddddd-dddd-dddd-dddd-ddddddddddd1"),
                    name: "Work & Career",
                    normalizedName: "work & career"
                )
            ]
            let items = zip(tags.indices, tags).map { index, tag in
                makeListItem(
                    id: uuid(
                        String(
                            format: "00000000-0000-0000-0000-%012d",
                            index + 1
                        )
                    ),
                    title: "\(tag.name) reminder",
                    lifecycleStatus: .active,
                    sourceWallClock: schedule.source,
                    localizedRepeatSummary: nil,
                    tags: [tag]
                )
            }
            return Task14ScenarioFixture(items: items, forms: [])
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
        private static func makeTagManagementModel(
            delaysAssociationRemoval: Bool
        ) -> TagManagementModel {
            let now = Date(timeIntervalSince1970: 2_225_052_800)
            let baseRepository: SwiftDataReminderRepository
            do {
                let container = try ModelContainerFactory.inMemory()
                let context = ModelContext(container)
                let tag = TagRecordV1(
                    id: uuid("88888888-8888-8888-8888-888888888888"),
                    name: "Work",
                    normalizedName: "work",
                    normalizationVersion: TagLimits.normalizationVersion,
                    createdAt: now,
                    updatedAt: now
                )
                context.insert(tag)
                context.insert(
                    ReminderRecordV1(
                        id: uuid("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
                        title: "Visa renewal",
                        notes: "Renewal documents",
                        urlString: nil,
                        enabled: true,
                        scheduleData: Data([1]),
                        createdAt: now,
                        updatedAt: now
                    )
                )
                try context.save()
                baseRepository = SwiftDataReminderRepository(container: container)
            } catch {
                preconditionFailure("Task 14 UI fixture requires an in-memory repository: \(error)")
            }
            let repository: any ReminderRepository =
                delaysAssociationRemoval
                ? Task14DelayedTagRepository(base: baseRepository)
                : baseRepository
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

    private actor Task14DelayedTagRepository: ReminderRepository {
        let base: SwiftDataReminderRepository

        init(base: SwiftDataReminderRepository) {
            self.base = base
        }

        func fetchCompleteSnapshot() async throws -> CompleteReminderSnapshot {
            try await base.fetchCompleteSnapshot()
        }

        func reminder(id: UUID) async throws -> ReminderSnapshot? {
            try await base.reminder(id: id)
        }

        func save(_ mutation: EncodedReminderMutation) async throws -> ReminderSnapshot {
            try await base.save(mutation)
        }

        func delete(id: UUID) async throws {
            try await base.delete(id: id)
        }

        func saveTag(_ mutation: EncodedTagMutation) async throws -> TagSnapshot {
            try await base.saveTag(mutation)
        }

        func deleteTag(id: UUID) async throws {
            try await base.deleteTag(id: id)
        }

        func removeTagAssociation(
            tagID: UUID,
            from reminderID: UUID?
        ) async throws -> TagAssociationRemovalOutcome {
            try await Task.sleep(for: .seconds(2))
            return try await base.removeTagAssociation(tagID: tagID, from: reminderID)
        }
    }

    @MainActor
    private struct Task14ScenarioFixture {
        let items: [ReminderListItemPresentation]
        let forms: [ReminderFormModel]
    }
#endif
