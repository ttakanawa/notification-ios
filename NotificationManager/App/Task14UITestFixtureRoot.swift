#if DEBUG
import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
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
        let listModel = ReminderListModel(items: fixture.items)
        let actionCoordinator = ReminderActionCoordinator(
            handlers: ReminderActionHandlers(
                setEnabled: { _, _ in },
                delete: { _ in }
            )
        )
        let createForm: @MainActor @Sendable () -> ReminderFormModel? =
            if scenario == "empty-list" {
                { makeNewForm() }
            } else {
                { nil }
            }
        let router = AppRouter(
            actions: actionCoordinator,
            createForm: createForm
        )

        for detail in fixture.details {
            router.register(detail: detail)
        }
        for form in fixture.forms {
            router.register(form: form)
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
        case "empty-list":
            return Task14ScenarioFixture(items: [], details: [], forms: [])
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
        case "capacity-and-expired-confirmations":
            return editableFixture(
                id: uuid("dddddddd-dddd-dddd-dddd-dddddddddddd"),
                title: "Capacity edit",
                repeatPresentation: .standard(localizedSummary: "Every week"),
                actions: capacityConfirmationActions()
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
        let snapshot = makeSnapshot(
            id: id,
            title: title,
            schedule: .valid(schedule, sourceVersion: 1, originalData: Data([1]))
        )
        let item = makeListItem(
            id: id,
            title: title,
            lifecycleStatus: .active,
            sourceWallClock: schedule.source,
            localizedRepeatSummary: repeatPresentation.localizedSummary
        )
        let form = ReminderFormModel(
            snapshot: snapshot,
            savedRepeatPresentation: repeatPresentation,
            now: evaluationNow,
            actions: actions
        )
        return Task14ScenarioFixture(
            items: [item],
            details: [makeDetail(item: item)],
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
            details: [makeDetail(item: item)],
            forms: [form]
        )
    }

    private static func makeNewForm() -> ReminderFormModel {
        ReminderFormModel(
            newReminderID: uuid("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"),
            now: evaluationNow,
            actions: inertFormActions
        )
    }

    private static func makeSnapshot(
        id: UUID,
        title: String,
        schedule: ScheduleReadState
    ) -> ReminderSnapshot {
        ReminderSnapshot(
            id: id,
            title: title,
            notes: nil,
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
        lifecycleStatus: LifecycleStatus,
        sourceWallClock: SourceWallClock?,
        localizedRepeatSummary: String?
    ) -> ReminderListItemPresentation {
        ReminderListItemPresentation(
            id: id,
            title: title,
            lifecycleStatus: lifecycleStatus,
            deviceSchedulingStatus: lifecycleStatus == .active ? .scheduled : .notApplicable,
            nextPresentation: lifecycleStatus == .active
                ? .directOSFire(authoritative: sourceInstant, foundationPreview: sourceInstant)
                : nil,
            nextReason: lifecycleStatus == .active ? .main : nil,
            sourceWallClock: sourceWallClock,
            localizedRepeatSummary: localizedRepeatSummary,
            enabled: true,
            updatedAt: evaluationNow
        )
    }

    private static func makeDetail(
        item: ReminderListItemPresentation
    ) -> ReminderDetailModel {
        ReminderDetailModel(
            item: item,
            sourceTime: item.sourceWallClock == nil ? nil : sourceInstant,
            currentDeviceTime: item.sourceWallClock == nil ? nil : sourceInstant,
            localizedRepeatSummary: item.localizedRepeatSummary,
            nextNotifications: [],
            alertGroups: [],
            scheduledThrough: nil,
            requestDiagnostics: []
        )
    }

    private static func capacityConfirmationActions() -> ReminderFormActions {
        let capacityInstant = sourceInstant
        let expiredEvaluationNow = evaluationNow
        return ReminderFormActions(
            save: { draft, capacityConsent, expiredScheduleConsent in
                if capacityConsent == .notProvided {
                    return .requiresCapacityConfirmation(CapacityWarning(
                        reminderID: draft.id,
                        earliestGroupID: AlertGroupID(
                            reminderID: draft.id,
                            baseOccurrenceInstant: capacityInstant
                        ),
                        planningCapacity: 60
                    ))
                }
                if expiredScheduleConsent == .notProvided {
                    return .requiresExpiredScheduleConfirmation(ExpiredScheduleWarning(
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

    private static let evaluationNow = Date(timeIntervalSince1970: 2_225_052_800)
    private static let sourceInstant = Date(timeIntervalSince1970: 2_228_349_000)

    private static func uuid(_ value: String) -> UUID {
        guard let id = UUID(uuidString: value) else {
            preconditionFailure("Invalid Task 14 UI fixture UUID")
        }
        return id
    }
}

@MainActor
private struct Task14ScenarioFixture {
    let items: [ReminderListItemPresentation]
    let details: [ReminderDetailModel]
    let forms: [ReminderFormModel]
}
#endif
