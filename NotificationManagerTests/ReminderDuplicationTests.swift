import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import Testing

@testable import NotificationManager

@MainActor
struct ReminderDuplicationTests {
    @Test func duplicateCopiesContentAndExactScheduleWithFreshIdentity() throws {
        let source = snapshot()
        let newID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let now = date("2040-08-01T02:30:45Z")
        let model = try #require(
            ReminderFormModel(
                duplicating: source,
                newReminderID: newID,
                savedRepeatPresentation: .custom(
                    localizedSummary: "Every 3 days.",
                    canonicalEnglishDisclosure: "Every 3 days."
                ),
                now: now.addingTimeInterval(0.75),
                actions: inertActions
            )
        )
        let draft = model.detachedDraft

        #expect(draft.id == newID)
        #expect(draft.id != source.id)
        #expect(draft.title == source.title)
        #expect(draft.notes == source.notes)
        #expect(draft.urlString == source.urlString)
        #expect(draft.enabled == source.enabled)
        #expect(draft.tagIDs == source.tagIDs)
        #expect(draft.createdAt == now)
        #expect(draft.updatedAt == now)
        #expect(draft.originalScheduleData == nil)
        #expect(draft.scheduleChange == .replace(definition()))
        #expect(draft.durationSeconds == 2_700)
        #expect(
            draft.liveActivityWindow == LiveActivityWindow(beforeSeconds: 61, afterSeconds: 119))
        #expect(!model.canDelete)
        #expect(model.scheduleAccess == .editable)
        #expect(!model.canSaveWithoutReplacingSchedule)
        #expect(model.canSave)
        #expect(model.repeatEndsOnDate)
        #expect(model.earlyReminderChoice == .fiveMinutes)
        #expect(model.currentRepeatWasCustom)
        #expect(model.currentLocalizedRepeatSummary == "Every 3 days.")
        #expect(model.canonicalEnglishDisclosure == "Every 3 days.")
        #expect(model.liveActivityEnabled)
        #expect(model.liveActivityBeforeMinutes == 2)
        #expect(model.liveActivityAfterMinutes == 2)
    }

    @Test(arguments: [AppRouterLayout.compact, .regular])
    func openingDuplicateDoesNotSaveOrChangeDirtySourceEditor(
        layout: AppRouterLayout
    ) async throws {
        let source = snapshot()
        let newID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let recorder = DuplicationSaveRecorder()
        let actions = ReminderFormActions(
            save: { draft, _, _ in await recorder.save(draft) },
            delete: { _ in }
        )
        let sourceEditor = ReminderFormModel(
            snapshot: source,
            savedRepeatPresentation: nil,
            now: date("2040-08-01T00:00:00Z"),
            actions: actions
        )
        sourceEditor.title = "Unsaved edit"
        var factoryCallCount = 0
        let router = AppRouter(
            actions: actionCoordinator(),
            canDuplicateReminder: { $0 == source.id },
            duplicateForm: { id in
                guard id == source.id else { return nil }
                factoryCallCount += 1
                return ReminderFormModel(
                    duplicating: source,
                    newReminderID: newID,
                    now: self.date("2040-08-01T00:00:00Z"),
                    actions: actions
                )
            }
        )
        router.register(form: sourceEditor)
        router.synchronizeLayout(layout)

        #expect(router.canDuplicate(source.id))
        #expect(factoryCallCount == 0)
        router.showDuplicate(source.id)

        let duplicate = try #require(router.formModel(for: newID))
        #expect(factoryCallCount == 1)
        #expect(await recorder.drafts.isEmpty)
        #expect(duplicate.title == source.title)
        #expect(router.formModel(for: source.id) === sourceEditor)
        #expect(sourceEditor.title == "Unsaved edit")
        #expect(sourceEditor.hasChanges)
        #expect(router.selectedReminderID == nil)
        switch layout {
        case .compact:
            #expect(router.compactPath == [.reminderCreate(newID)])
        case .regular:
            #expect(router.regularDestination == .reminderCreate(newID))
        }

        router.prunePersistedReminders(keeping: [source.id])
        #expect(router.formModel(for: newID) === duplicate)
        #expect(await duplicate.save())
        let saved = try #require(await recorder.drafts.first)
        #expect(saved.id == newID)
        #expect(saved.originalScheduleData == nil)
        #expect(saved.scheduleChange == .replace(definition()))
    }

    @Test func invalidSchedulesCannotBeDuplicated() {
        let schedules: [ScheduleReadState] = [
            .unsupportedFuture(version: 99, originalData: Data([99])),
            .corrupt(originalData: Data([0xff])),
            .domainInvalid(
                repairSeed: ScheduleRepairSeed(),
                originalData: Data([1]),
                issues: [.invalidSourceDay]
            )
        ]
        for schedule in schedules {
            let source = snapshot(schedule: schedule)
            #expect(
                ReminderFormModel(
                    duplicating: source,
                    now: date("2040-08-01T00:00:00Z"),
                    actions: inertActions
                ) == nil
            )
            var factoryCallCount = 0
            let router = AppRouter(
                actions: actionCoordinator(),
                canDuplicateReminder: { _ in false },
                duplicateForm: { _ in
                    factoryCallCount += 1
                    return nil
                }
            )
            router.register(
                form: ReminderFormModel(
                    snapshot: source,
                    savedRepeatPresentation: nil,
                    now: date("2040-08-01T00:00:00Z"),
                    actions: inertActions
                )
            )

            #expect(!router.canDuplicate(source.id))
            router.showDuplicate(source.id)
            #expect(factoryCallCount == 0)
            #expect(router.compactPath.isEmpty)
        }
    }

    @Test func duplicateRejectsReusingSourceIdentityAndUnknownRouterIdentity() {
        let source = snapshot()
        #expect(
            ReminderFormModel(
                duplicating: source,
                newReminderID: source.id,
                now: date("2040-08-01T00:00:00Z"),
                actions: inertActions
            ) == nil
        )
        var factoryCallCount = 0
        let router = AppRouter(
            actions: actionCoordinator(),
            canDuplicateReminder: { _ in true },
            duplicateForm: { _ in
                factoryCallCount += 1
                return nil
            }
        )

        #expect(!router.canDuplicate(source.id))
        router.showDuplicate(source.id)
        #expect(factoryCallCount == 0)
        #expect(router.compactPath.isEmpty)
    }

    @Test(arguments: [false, true])
    func publishingEnabledChangeRefreshesOnlyCleanEditors(isDirty: Bool) async throws {
        let environment = AppEnvironment()
        let deviceState = await DeviceSchedulingStateStore().snapshot()
        let source = snapshot()
        environment.publish(
            CompleteReminderSnapshot(reminders: [source], tags: []),
            deviceState: deviceState
        )
        let originalEditor = try #require(environment.router.formModel(for: source.id))
        if isDirty {
            originalEditor.title = "Unsaved edit"
        }

        environment.publish(
            CompleteReminderSnapshot(reminders: [snapshot(enabled: true)], tags: []),
            deviceState: deviceState
        )

        let currentEditor = try #require(environment.router.formModel(for: source.id))
        #expect(environment.listModel.items.first?.enabled == true)
        if isDirty {
            #expect(currentEditor === originalEditor)
            #expect(currentEditor.title == "Unsaved edit")
            #expect(!currentEditor.enabled)
            #expect(currentEditor.hasChanges)
        } else {
            #expect(currentEditor !== originalEditor)
            #expect(currentEditor.title == source.title)
            #expect(currentEditor.enabled)
            #expect(!currentEditor.hasChanges)
        }
    }

    private var inertActions: ReminderFormActions {
        ReminderFormActions(save: { draft, _, _ in .saved(draft.id) }, delete: { _ in })
    }

    private func actionCoordinator() -> ReminderActionCoordinator {
        ReminderActionCoordinator(
            handlers: ReminderActionHandlers(
                setEnabled: { .saved($0.reminderID) },
                delete: { _ in }
            )
        )
    }

    private func definition() -> ScheduleDefinition {
        ScheduleDefinition(
            source: SourceWallClock(
                year: 2040, month: 8, day: 31, hour: 9, minute: 30,
                timeZoneIdentifier: "America/New_York"
            ),
            rule: .daily(interval: 3),
            end: .onDate(SourceDate(year: 2040, month: 12, day: 31)),
            early: EarlyReminder(value: 5, unit: .minutes, mainEnabled: false),
            durationSeconds: 2_700,
            liveActivityWindow: LiveActivityWindow(beforeSeconds: 61, afterSeconds: 119)
        )
    }

    private func snapshot(
        enabled: Bool = false,
        schedule: ScheduleReadState? = nil
    ) -> ReminderSnapshot {
        ReminderSnapshot(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            title: "Visa renewal",
            notes: "Bring passport",
            urlString: "https://example.com/renewal",
            enabled: enabled,
            schedule: schedule ?? .valid(definition(), sourceVersion: 4, originalData: Data([4])),
            tagIDs: [UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!],
            createdAt: date("2040-01-01T00:00:00Z"),
            updatedAt: date("2040-07-01T00:00:00Z")
        )
    }

    private func date(_ value: String) -> Date {
        guard let date = ISO8601DateFormatter().date(from: value) else {
            preconditionFailure("Invalid ISO-8601 test fixture: \(value)")
        }
        return date
    }
}

private actor DuplicationSaveRecorder {
    private(set) var drafts: [ReminderDraft] = []

    func save(_ draft: ReminderDraft) -> SaveReminderOutcome {
        drafts.append(draft)
        return .saved(draft.id)
    }
}
