import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import Testing
@testable import NotificationManager

@MainActor
struct ReminderFormModelTests {
    @Test func newDraftKeepsFixedIdentityAndStartsWithFiveBlankScheduleSections() {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let model = ReminderFormModel(
            newReminderID: id,
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert
        )

        #expect(model.detachedDraft.id == id)
        #expect(model.sections == [
            .basicInformation,
            .dateAndTime,
            .repeatRule,
            .earlyReminder,
            .organization
        ])
        #expect(model.sourceDate == nil)
        #expect(model.sourceTime == nil)
        #expect(model.timeZoneIdentifier == nil)
        #expect(model.repeatRule == .none)
        #expect(!model.canSave)
    }

    @Test func existingLocalizedCustomRuleDoesNotPopulateEditableEnglish() {
        let model = ReminderFormModel(
            snapshot: validSnapshot(),
            savedRepeatPresentation: .custom(
                localizedSummary: "毎週月曜日に繰り返します。",
                canonicalEnglishDisclosure: "Every Monday."
            ),
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert
        )

        #expect(model.customRepeatText.isEmpty)
        #expect(model.currentLocalizedRepeatSummary == "毎週月曜日に繰り返します。")
        #expect(model.currentRepeatWasCustom)
        #expect(model.canonicalEnglishDisclosure == "Every Monday.")
        #expect(model.canSaveWithoutReplacingSchedule)

        model.sourceTime = SourceTime(hour: 10, minute: 45)

        #expect(model.currentRepeatWasCustom)
        #expect(model.currentLocalizedRepeatSummary == "毎週月曜日に繰り返します。")

        model.beginCustomReplacement()

        #expect(model.customRepeatText.isEmpty)
        #expect(model.isReplacingCustomRepeat)
        #expect(!model.canSave)
    }

    @Test func existingStandardSummaryRemainsAStandardPreset() {
        let model = ReminderFormModel(
            snapshot: validSnapshot(),
            savedRepeatPresentation: .standard(localizedSummary: "Every week."),
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert
        )

        #expect(model.currentLocalizedRepeatSummary == "Every week.")
        #expect(!model.currentRepeatWasCustom)
        #expect(model.canSaveWithoutReplacingSchedule)
    }

    @Test(arguments: [OpaqueScheduleFixture.unsupported, .corrupt])
    func opaqueScheduleAllowsMetadataAndDeleteWhilePreservingRawBytes(
        fixture: OpaqueScheduleFixture
    ) {
        let raw = Data([0xde, 0xad, 0xbe, 0xef])
        let snapshot = validSnapshot(schedule: fixture.schedule(raw: raw))
        let model = ReminderFormModel(
            snapshot: snapshot,
            savedRepeatPresentation: nil,
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert
        )

        model.title = "Updated title"
        model.notes = "Metadata only"
        model.enabled = false

        #expect(model.scheduleAccess == fixture.expectedAccess)
        #expect(model.canEditMetadata)
        #expect(model.canDelete)
        #expect(model.canSave)
        #expect(model.detachedDraft.originalScheduleData == raw)
        #expect(model.detachedDraft.scheduleChange == .preserveOriginal)
    }

    @Test func domainInvalidRepairSeedsOnlyDecodedSafeFields() {
        let raw = Data([1, 2, 3])
        let rule = RepeatRule.daily(interval: 2)
        let snapshot = validSnapshot(schedule: .domainInvalid(
            repairSeed: ScheduleRepairSeed(
                source: nil,
                rule: rule,
                end: .never,
                early: EarlyReminder(value: 10, unit: .minutes)
            ),
            originalData: raw,
            issues: [.invalidSourceDay]
        ))
        let model = ReminderFormModel(
            snapshot: snapshot,
            savedRepeatPresentation: nil,
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert
        )

        #expect(model.scheduleAccess == .repair(issues: [.invalidSourceDay]))
        #expect(model.sourceDate == nil)
        #expect(model.sourceTime == nil)
        #expect(model.timeZoneIdentifier == nil)
        #expect(model.repeatRule == rule)
        #expect(model.earlyReminder == EarlyReminder(value: 10, unit: .minutes))
        #expect(!model.canSave)
    }

    @Test func previewUsesFixedDraftIDAndShowsThreePhysicalNotifications() {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let model = ReminderFormModel(
            newReminderID: id,
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert
        )

        populateSchedule(model, rule: .daily(interval: 1))

        #expect(model.previewNotifications.count == 3)
        #expect(model.previewNotifications.allSatisfy { $0.reminderID == id })
        #expect(!model.showsPastEarlyWarning)
    }

    @Test func previewWarnsWhenEarlyAlertAlreadyPassed() {
        let model = ReminderFormModel(
            newReminderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            now: date("2040-08-31T13:00:00Z"),
            actions: .inert
        )
        model.title = "One time"
        model.sourceDate = SourceDate(year: 2040, month: 8, day: 31)
        model.sourceTime = SourceTime(hour: 13, minute: 30)
        model.timeZoneIdentifier = "Africa/Abidjan"
        model.earlyReminder = EarlyReminder(value: 60, unit: .minutes)

        #expect(model.previewNotifications.map(\.alertInstant) == [
            date("2040-08-31T13:30:00Z")
        ])
        #expect(model.showsPastEarlyWarning)
    }

    @Test func customReplacementRunsTaskThirteenSessionAndAppliesConfirmedSchedule() async {
        let model = ReminderFormModel(
            snapshot: validSnapshot(),
            savedRepeatPresentation: .custom(
                localizedSummary: "毎週月曜日に繰り返します。",
                canonicalEnglishDisclosure: "Every Monday."
            ),
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert,
            localizedRepeatSummary: { _ in "Every weekday." }
        )
        model.beginCustomReplacement()
        model.updateCustomRepeatText("every weekday")

        await model.submitCustomRepeat()

        guard case let .awaitingConfirmation(preview) = model.customRepeatState else {
            Issue.record("Expected a parsed Custom Repeat preview")
            return
        }
        #expect(preview.route == .deterministicEnglish)
        #expect(preview.canonicalEnglish == "Every weekday")
        #expect(preview.nextNotifications.notifications.count == 3)
        await model.confirmCustomRepeat()

        let expectedRule = RepeatRule.weekly(
            interval: 1,
            weekdaySetKind: .weekday,
            weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday]
        )
        #expect(model.repeatRule == expectedRule)
        #expect(model.currentLocalizedRepeatSummary == "Every weekday.")
        #expect(model.canonicalEnglishDisclosure == "Every weekday")
        #expect(model.customRepeatText == "every weekday")
        guard case let .replace(schedule) = model.detachedDraft.scheduleChange else {
            Issue.record("Expected confirmed Custom Repeat to replace the schedule")
            return
        }
        #expect(schedule.rule == expectedRule)
    }

    @Test func customRepeatSuggestionRequiresSelectionAndConfirmationBeforeApplying() async {
        let model = ReminderFormModel(
            snapshot: validSnapshot(),
            savedRepeatPresentation: .standard(localizedSummary: "Every week."),
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert
        )
        let originalRule = model.repeatRule
        model.beginCustomReplacement()
        model.updateCustomRepeatText("Every Tuseday")

        await model.submitCustomRepeat()

        #expect(model.customRepeatState == .awaitingSuggestion("Every Tuesday"))
        #expect(model.customRepeatText == "Every Tuseday")
        #expect(model.repeatRule == originalRule)

        await model.selectCustomRepeatSuggestion()

        #expect(model.customRepeatText == "Every Tuesday")
        guard case let .awaitingConfirmation(preview) = model.customRepeatState else {
            Issue.record("Expected the selected suggestion to produce a confirmation preview")
            return
        }
        #expect(preview.canonicalEnglish == "Every Tuesday")
        #expect(model.repeatRule == originalRule)

        await model.confirmCustomRepeat()

        #expect(model.repeatRule == .weekly(
            interval: 1,
            weekdaySetKind: .explicit,
            weekdays: [.tuesday]
        ))
    }

    @Test func readOnlyOpaqueScheduleRejectsProgrammaticScheduleMutations() {
        let raw = Data([0xff])
        let model = ReminderFormModel(
            snapshot: validSnapshot(schedule: .corrupt(originalData: raw)),
            savedRepeatPresentation: nil,
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert
        )
        let before = model.detachedDraft

        model.sourceDate = SourceDate(year: 2099, month: 1, day: 1)
        model.sourceTime = SourceTime(hour: 23, minute: 59)
        model.timeZoneIdentifier = "Asia/Tokyo"
        model.repeatRule = .daily(interval: 1)
        model.earlyReminder = EarlyReminder(value: 5, unit: .minutes)

        #expect(model.detachedDraft.date == before.date)
        #expect(model.detachedDraft.time == before.time)
        #expect(model.detachedDraft.timeZoneIdentifier == before.timeZoneIdentifier)
        #expect(model.detachedDraft.rule == before.rule)
        #expect(model.detachedDraft.early == before.early)
        #expect(model.detachedDraft.originalScheduleData == raw)
        #expect(model.detachedDraft.scheduleChange == .preserveOriginal)
    }

    @Test func customRawInputDoesNotEnterDetachedDraftOrAnotherFormSession() {
        let first = ReminderFormModel(
            snapshot: validSnapshot(),
            savedRepeatPresentation: nil,
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert
        )
        first.beginCustomReplacement()
        first.updateCustomRepeatText("every 3 days")
        let second = ReminderFormModel(
            snapshot: validSnapshot(),
            savedRepeatPresentation: nil,
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert
        )

        #expect(first.customRepeatText == "every 3 days")
        #expect(second.customRepeatText.isEmpty)
        #expect(first.detachedDraft.originalScheduleData == second.detachedDraft.originalScheduleData)
    }

    @Test func confirmationsReplayTheSameDetachedDraftThroughTheSaveAction() async {
        let recorder = SaveActionRecorder(outcomes: [
            .requiresCapacityConfirmation(CapacityWarning(
                reminderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
                earliestGroupID: AlertGroupID(
                    reminderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
                    baseOccurrenceInstant: date("2040-08-31T13:30:00Z")
                ),
                planningCapacity: 60
            )),
            .requiresExpiredScheduleConfirmation(ExpiredScheduleWarning(
                reminderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
                evaluationNow: date("2040-08-31T13:30:00Z")
            )),
            .saved(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!)
        ])
        let model = configuredNewModel(recorder: recorder)

        await model.save()
        #expect(model.saveState.isCapacityConfirmation)
        await model.confirmCapacitySave()
        #expect(model.saveState.isExpiredConfirmation)
        await model.confirmExpiredSave()

        let calls = await recorder.recordedCalls()
        #expect(calls.map(\.draftID) == Array(repeating: model.detachedDraft.id, count: 3))
        #expect(calls.map(\.capacityConsent) == [.notProvided, .acknowledged, .acknowledged])
        #expect(calls.map(\.expiredConsent) == [.notProvided, .notProvided, .acknowledged])
        #expect(model.saveState == .saved(model.detachedDraft.id))
    }

    @Test func saveFailureRetainsEveryDetachedDraftField() async {
        let actions = ReminderFormActions(
            save: { _, _, _ in throw SaveProbeError.failed },
            delete: { _ in }
        )
        let model = ReminderFormModel(
            newReminderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            now: date("2040-08-01T00:00:00Z"),
            actions: actions
        )
        populateSchedule(model, rule: .weekly(
            interval: 1,
            weekdaySetKind: .explicit,
            weekdays: [.monday]
        ))
        model.notes = "Keep this"
        let before = model.detachedDraft

        await model.save()

        #expect(model.detachedDraft == before)
        #expect(model.saveState == .failed(.save))
    }

    @Test func editDuringSuspendedSaveDiscardsStaleConfirmationOutcome() async {
        let gate = SuspendedSaveAction()
        let model = ReminderFormModel(
            newReminderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            now: date("2040-08-01T00:00:00Z"),
            actions: ReminderFormActions(
                save: { draft, _, _ in await gate.save(draft: draft) },
                delete: { _ in }
            )
        )
        populateSchedule(model, rule: .daily(interval: 1))
        let saveTask = Task { await model.save() }
        await gate.waitUntilCalled()

        model.title = "Edited while saving"
        await gate.resolve(.requiresCapacityConfirmation(CapacityWarning(
            reminderID: model.detachedDraft.id,
            earliestGroupID: AlertGroupID(
                reminderID: model.detachedDraft.id,
                baseOccurrenceInstant: date("2040-08-31T13:30:00Z")
            ),
            planningCapacity: 60
        )))
        await saveTask.value

        #expect(model.detachedDraft.title == "Edited while saving")
        #expect(model.saveState == .idle)
    }

    @Test func partialScheduleInputRemainsVisibleAndCannotBeSaved() {
        let model = ReminderFormModel(
            newReminderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert
        )
        populateSchedule(model, rule: .daily(interval: 1))

        model.updateSourceDateText("2040-")

        #expect(model.sourceDateText == "2040-")
        #expect(model.sourceDate == nil)
        #expect(!model.canSave)
        #expect(model.previewNotifications.isEmpty)

        model.updateSourceDateText("2040-08-31")
        model.earlyReminder = EarlyReminder(value: 5, unit: .minutes)
        #expect(model.canSave)

        model.updateEarlyReminderValueText("")

        #expect(model.earlyReminderValueText.isEmpty)
        #expect(!model.canSave)
        #expect(model.previewNotifications.isEmpty)
    }

    @Test func deleteWaitsForExplicitConfirmation() async {
        let recorder = DeleteActionRecorder()
        let model = ReminderFormModel(
            snapshot: validSnapshot(),
            savedRepeatPresentation: nil,
            now: date("2040-08-01T00:00:00Z"),
            actions: ReminderFormActions(
                save: { draft, _, _ in .saved(draft.id) },
                delete: { reminderID in await recorder.record(reminderID) }
            )
        )

        model.requestDeleteConfirmation()

        #expect(model.isDeleteConfirmationPresented)
        #expect(await recorder.recordedIDs().isEmpty)

        await model.confirmDelete()

        #expect(await recorder.recordedIDs() == [model.detachedDraft.id])
        #expect(model.saveState == .deleted)
    }

    @Test func repeatPresetsAndEndDateUseTheSourceAnchorWithoutLosingPartialInput() {
        let model = ReminderFormModel(
            newReminderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert
        )
        populateSchedule(model, rule: .none)

        #expect(model.applyRepeatPreset(.weekends))
        #expect(model.repeatRule == .weekly(
            interval: 1,
            weekdaySetKind: .weekend,
            weekdays: [.saturday, .sunday]
        ))
        #expect(model.applyRepeatPreset(.biweekly))
        #expect(model.repeatRule == .weekly(
            interval: 2,
            weekdaySetKind: .explicit,
            weekdays: [.friday]
        ))
        model.updateSourceDateText("2040-09-01")
        #expect(model.repeatRule == .weekly(
            interval: 2,
            weekdaySetKind: .explicit,
            weekdays: [.saturday]
        ))
        #expect(model.applyRepeatPreset(.every6Months))
        #expect(model.repeatRule == .monthly(interval: 6, selector: .anchorDay))

        model.setRepeatEndsOnDate(true)
        model.updateRepeatEndDateText("2041-")

        #expect(model.repeatEndDateText == "2041-")
        #expect(!model.canSave)
        #expect(model.previewNotifications.isEmpty)

        model.updateRepeatEndDateText("2041-08-31")

        #expect(model.repeatEnd == .onDate(SourceDate(year: 2041, month: 8, day: 31)))
        #expect(model.canSave)
    }

    @Test func fieldIssuesIdentifyMetadataTimeZoneAndEndDateFailures() {
        let model = ReminderFormModel(
            newReminderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert
        )
        populateSchedule(model, rule: .daily(interval: 1))

        model.title = "   "
        #expect(model.titleFieldIssue == .titleRequired)
        model.title = String(repeating: "a", count: ReminderLimits.titleBytes + 1)
        #expect(model.titleFieldIssue == .titleTooLarge)

        model.notes = String(repeating: "n", count: ReminderLimits.notesBytes + 1)
        #expect(model.notesFieldIssue == .notesTooLarge)

        model.urlString = "ftp://example.com/file"
        #expect(model.urlFieldIssue == .urlInvalid)

        model.timeZoneIdentifier = "Mars/Olympus_Mons"
        #expect(model.timeZoneFieldIssue == .timeZoneInvalid)

        model.timeZoneIdentifier = "America/New_York"
        model.setRepeatEndsOnDate(true)
        model.updateRepeatEndDateText("2040-08-30")
        #expect(model.repeatEndDateFieldIssue == .repeatEndBeforeStart)
        #expect(!model.repeatEndDateTextIsValid)
    }

    private func configuredNewModel(recorder: SaveActionRecorder) -> ReminderFormModel {
        let model = ReminderFormModel(
            newReminderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            now: date("2040-08-01T00:00:00Z"),
            actions: ReminderFormActions(
                save: { draft, capacityConsent, expiredConsent in
                    try await recorder.save(
                        draft: draft,
                        capacityConsent: capacityConsent,
                        expiredConsent: expiredConsent
                    )
                },
                delete: { _ in }
            )
        )
        populateSchedule(model, rule: .daily(interval: 1))
        return model
    }

    private func populateSchedule(_ model: ReminderFormModel, rule: RepeatRule) {
        model.title = "Travel insurance"
        model.sourceDate = SourceDate(year: 2040, month: 8, day: 31)
        model.sourceTime = SourceTime(hour: 9, minute: 30)
        model.timeZoneIdentifier = "America/New_York"
        model.repeatRule = rule
    }

    private func validSnapshot(
        schedule: ScheduleReadState? = nil
    ) -> ReminderSnapshot {
        let definition = ScheduleDefinition(
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
        return ReminderSnapshot(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            title: "Visa renewal",
            notes: nil,
            urlString: nil,
            enabled: true,
            schedule: schedule ?? .valid(definition, sourceVersion: 1, originalData: Data([1])),
            tagIDs: [],
            createdAt: date("2040-01-01T00:00:00Z"),
            updatedAt: date("2040-07-01T00:00:00Z")
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}

enum OpaqueScheduleFixture: Sendable, CaseIterable {
    case unsupported
    case corrupt

    func schedule(raw: Data) -> ScheduleReadState {
        switch self {
        case .unsupported: .unsupportedFuture(version: 2, originalData: raw)
        case .corrupt: .corrupt(originalData: raw)
        }
    }

    var expectedAccess: ReminderFormScheduleAccess {
        switch self {
        case .unsupported: .readOnly(.updateRequired)
        case .corrupt: .readOnly(.invalidSchedule)
        }
    }
}

private struct SaveActionCall: Sendable, Equatable {
    let draftID: UUID
    let capacityConsent: CapacityConsent
    let expiredConsent: ExpiredScheduleConsent
}

private actor SaveActionRecorder {
    private var outcomes: [SaveReminderOutcome]
    private var calls: [SaveActionCall] = []

    init(outcomes: [SaveReminderOutcome]) {
        self.outcomes = outcomes
    }

    func save(
        draft: ReminderDraft,
        capacityConsent: CapacityConsent,
        expiredConsent: ExpiredScheduleConsent
    ) throws -> SaveReminderOutcome {
        calls.append(SaveActionCall(
            draftID: draft.id,
            capacityConsent: capacityConsent,
            expiredConsent: expiredConsent
        ))
        guard !outcomes.isEmpty else { throw SaveProbeError.failed }
        return outcomes.removeFirst()
    }

    func recordedCalls() -> [SaveActionCall] { calls }
}

private actor SuspendedSaveAction {
    private var called = false
    private var callWaiters: [CheckedContinuation<Void, Never>] = []
    private var resultContinuation: CheckedContinuation<SaveReminderOutcome, Never>?

    func save(draft: ReminderDraft) async -> SaveReminderOutcome {
        called = true
        let waiters = callWaiters
        callWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
        }
    }

    func waitUntilCalled() async {
        guard !called else { return }
        await withCheckedContinuation { continuation in
            callWaiters.append(continuation)
        }
    }

    func resolve(_ outcome: SaveReminderOutcome) {
        resultContinuation?.resume(returning: outcome)
        resultContinuation = nil
    }
}

private actor DeleteActionRecorder {
    private var ids: [UUID] = []

    func record(_ id: UUID) {
        ids.append(id)
    }

    func recordedIDs() -> [UUID] { ids }
}

private enum SaveProbeError: Error {
    case failed
}

private extension ReminderFormActions {
    static let inert = Self(
        save: { draft, _, _ in .saved(draft.id) },
        delete: { _ in }
    )
}

private extension ReminderFormSaveState {
    var isCapacityConfirmation: Bool {
        if case .requiresCapacityConfirmation = self { true } else { false }
    }

    var isExpiredConfirmation: Bool {
        if case .requiresExpiredScheduleConfirmation = self { true } else { false }
    }
}
