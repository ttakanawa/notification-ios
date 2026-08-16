import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import Testing

@testable import NotificationManager

@MainActor
struct ReminderFormModelTests {
    @Test func newDraftNormalizesFractionalTimestampAndCanSave() {
        let expectedTimestamp = date("2040-08-01T02:30:45Z")
        let model = ReminderFormModel(
            newReminderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            now: expectedTimestamp.addingTimeInterval(0.75),
            actions: .inert,
            defaultTimeZone: TimeZone(identifier: "Asia/Tokyo")!
        )

        model.title = "Test"

        #expect(model.detachedDraft.createdAt == expectedTimestamp)
        #expect(model.detachedDraft.updatedAt == expectedTimestamp)
        #expect(model.canSave)
    }

    @Test func newDraftStartsAtTheNextWholeHourInTheInjectedTimeZone() {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let model = ReminderFormModel(
            newReminderID: id,
            now: date("2040-08-01T02:30:45Z"),
            actions: .inert,
            defaultTimeZone: TimeZone(identifier: "Asia/Tokyo")!
        )

        #expect(model.detachedDraft.id == id)
        #expect(model.sourceDate == SourceDate(year: 2040, month: 8, day: 1))
        #expect(model.sourceTime == SourceTime(hour: 12, minute: 0))
        #expect(model.timeZoneIdentifier == "Asia/Tokyo")
        #expect(model.previewNotifications.count == 1)
        #expect(
            model.detachedDraft.scheduleChange
                == .replace(
                    ScheduleDefinition(
                        source: SourceWallClock(
                            year: 2040, month: 8, day: 1, hour: 12, minute: 0,
                            timeZoneIdentifier: "Asia/Tokyo"
                        ),
                        rule: .none,
                        end: .never,
                        early: nil
                    )))
    }

    @Test func newDraftAdvancesAnExactHourAndRollsAcrossMidnight() {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let exactHour = ReminderFormModel(
            newReminderID: id,
            now: date("2040-08-01T02:00:00Z"),
            actions: .inert,
            defaultTimeZone: timeZone
        )
        #expect(exactHour.sourceDate == SourceDate(year: 2040, month: 8, day: 1))
        #expect(exactHour.sourceTime == SourceTime(hour: 12, minute: 0))

        let rollover = ReminderFormModel(
            newReminderID: id,
            now: date("2040-08-01T14:30:00Z"),
            actions: .inert,
            defaultTimeZone: timeZone
        )
        #expect(rollover.sourceDate == SourceDate(year: 2040, month: 8, day: 2))
        #expect(rollover.sourceTime == SourceTime(hour: 0, minute: 0))
    }

    @Test func newDraftSkipsTheNewYorkSpringForwardGap() {
        let model = ReminderFormModel(
            newReminderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            now: date("2040-03-11T06:30:00Z"),
            actions: .inert,
            defaultTimeZone: TimeZone(identifier: "America/New_York")!
        )

        #expect(model.sourceDate == SourceDate(year: 2040, month: 3, day: 11))
        #expect(model.sourceTime == SourceTime(hour: 3, minute: 0))
        #expect(model.timeZoneIdentifier == "America/New_York")
    }

    @Test func newDraftFallsBackToGMTForAnUnknownInjectedTimeZoneIdentifier() {
        let model = ReminderFormModel(
            newReminderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            now: date("2040-08-01T02:30:45Z"),
            actions: .inert,
            defaultTimeZone: TimeZone(identifier: "UTC")!
        )

        #expect(model.sourceDate == SourceDate(year: 2040, month: 8, day: 1))
        #expect(model.sourceTime == SourceTime(hour: 3, minute: 0))
        #expect(model.timeZoneIdentifier == "GMT")
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

    @Test func existingReminderTracksSemanticChangesAndReturnsCleanAtBaseline() {
        let model = ReminderFormModel(
            snapshot: validSnapshot(rule: .daily(interval: 1)),
            savedRepeatPresentation: .standard(localizedSummary: "Every day."),
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert
        )

        #expect(!model.hasChanges)

        model.title = "Updated"
        #expect(model.hasChanges)
        model.title = "Visa renewal"
        #expect(!model.hasChanges)

        model.updateSourceDate(from: date("2040-09-01T16:00:00Z"))
        #expect(model.hasChanges)

        model.updateSourceDate(from: date("2040-08-31T16:00:00Z"))
        #expect(!model.hasChanges)
        #expect(model.detachedDraft.scheduleChange != .preserveOriginal)
    }

    @Test func pickerSelectionsUpdateOnlyTheirOwnWallClockComponents() {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let zone = TimeZone(identifier: "Asia/Tokyo")!
        let model = ReminderFormModel(
            newReminderID: id,
            now: date("2040-08-01T02:30:00Z"),
            actions: .inert,
            defaultTimeZone: zone
        )

        model.updateSourceDate(from: date("2040-09-15T03:00:00Z"))
        #expect(model.sourceDate == SourceDate(year: 2040, month: 9, day: 15))
        #expect(model.sourceTime == SourceTime(hour: 12, minute: 0))

        model.updateSourceTime(from: date("2001-01-01T09:45:00Z"))
        #expect(model.sourceDate == SourceDate(year: 2040, month: 9, day: 15))
        #expect(model.sourceTime == SourceTime(hour: 18, minute: 45))
    }

    @Test func pickerValuesUseStableUnrelatedComponentsAndPreviewFallback() {
        let zone = TimeZone(identifier: "Asia/Tokyo")!
        let model = ReminderFormModel(
            newReminderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            now: date("2040-08-01T02:30:45Z"),
            actions: .inert,
            defaultTimeZone: zone
        )

        #expect(model.pickerTimeZone == zone)
        #expect(model.sourceDatePickerValue == date("2040-08-01T03:00:00Z"))
        #expect(model.sourceTimePickerValue == date("2001-01-01T03:00:00Z"))
        #expect(model.missingPickerDefaultValue == date("2040-08-01T03:00:00Z"))
    }

    @Test func changingTimeZoneKeepsWallClockComponentsAndChangesPreviewInstant() {
        let model = ReminderFormModel(
            snapshot: validSnapshot(rule: .none),
            savedRepeatPresentation: .standard(localizedSummary: "Never."),
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert
        )
        let sourceDate = model.sourceDate
        let sourceTime = model.sourceTime

        #expect(model.previewNotifications.first?.alertInstant == date("2040-08-31T13:30:00Z"))

        model.timeZoneIdentifier = "Asia/Tokyo"

        #expect(model.sourceDate == sourceDate)
        #expect(model.sourceTime == sourceTime)
        #expect(model.pickerTimeZone == TimeZone(identifier: "Asia/Tokyo"))
        #expect(model.previewNotifications.first?.alertInstant == date("2040-08-31T00:30:00Z"))
    }

    @Test func pickerEditsParticipateInDirtyTrackingAndDiscard() {
        let model = ReminderFormModel(
            snapshot: validSnapshot(rule: .none),
            savedRepeatPresentation: .standard(localizedSummary: "Never."),
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert
        )

        model.updateSourceDate(from: date("2040-09-15T16:00:00Z"))
        model.updateSourceTime(from: date("2001-01-01T14:45:00Z"))

        #expect(model.hasChanges)
        #expect(model.sourceDate == SourceDate(year: 2040, month: 9, day: 15))
        #expect(model.sourceTime == SourceTime(hour: 9, minute: 45))

        model.discardChanges()

        #expect(!model.hasChanges)
        #expect(model.sourceDate == SourceDate(year: 2040, month: 8, day: 31))
        #expect(model.sourceTime == SourceTime(hour: 9, minute: 30))
    }

    @Test func existingOutOfRangeEarlyReminderIsPreservedUntilUnitChanges() {
        let model = ReminderFormModel(
            snapshot: validSnapshot(early: EarlyReminder(value: 90, unit: .minutes)),
            savedRepeatPresentation: .standard(localizedSummary: "Every week."),
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert
        )

        #expect(model.earlyReminder == EarlyReminder(value: 90, unit: .minutes))
        #expect(model.earlyReminderAmountChoices == Array(1...59) + [90])
        #expect(!model.hasChanges)

        model.updateEarlyReminderUnit(.hours)

        #expect(model.earlyReminder == EarlyReminder(value: 23, unit: .hours))
        #expect(model.hasChanges)
    }

    @Test func invalidURLRemainsDirtyUntilRestoredToTheRegisteredBaseline() {
        let model = existingModel()

        model.urlString = "not-a-url"

        #expect(model.hasChanges)
        #expect(model.urlFieldIssue == .urlInvalid)
        #expect(!model.canSave)

        model.urlString = nil

        #expect(!model.hasChanges)
    }

    @Test func invalidCustomRepeatTextIsRetainedUntilChangesAreDiscarded() {
        let model = existingModel()

        model.beginCustomReplacement()
        model.updateCustomRepeatText("not a repeat rule")

        #expect(model.customRepeatText == "not a repeat rule")
        #expect(model.hasChanges)
        #expect(!model.canSave)

        model.discardChanges()

        #expect(model.customRepeatText.isEmpty)
        #expect(!model.isReplacingCustomRepeat)
        #expect(!model.hasChanges)
    }

    @Test func existingReminderTracksEveryEditableFieldSemantically() {
        let tagID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!

        let metadataModel = existingModel()
        metadataModel.notes = "Note"
        #expect(metadataModel.hasChanges)
        metadataModel.notes = nil
        #expect(!metadataModel.hasChanges)
        metadataModel.urlString = "https://example.com"
        #expect(metadataModel.hasChanges)
        metadataModel.urlString = nil
        #expect(!metadataModel.hasChanges)
        metadataModel.enabled = false
        #expect(metadataModel.hasChanges)
        metadataModel.enabled = true
        #expect(!metadataModel.hasChanges)
        metadataModel.tagIDs = [tagID]
        #expect(metadataModel.hasChanges)
        metadataModel.tagIDs = []
        #expect(!metadataModel.hasChanges)

        let sourceModel = existingModel()
        sourceModel.sourceDate = SourceDate(year: 2040, month: 9, day: 1)
        #expect(sourceModel.hasChanges)
        sourceModel.sourceDate = SourceDate(year: 2040, month: 8, day: 31)
        #expect(!sourceModel.hasChanges)
        sourceModel.sourceTime = SourceTime(hour: 10, minute: 45)
        #expect(sourceModel.hasChanges)
        sourceModel.sourceTime = SourceTime(hour: 9, minute: 30)
        #expect(!sourceModel.hasChanges)
        sourceModel.timeZoneIdentifier = "Asia/Manila"
        #expect(sourceModel.hasChanges)
        sourceModel.timeZoneIdentifier = "America/New_York"
        #expect(!sourceModel.hasChanges)

        let repeatModel = existingModel()
        repeatModel.repeatRule = .weekly(
            interval: 1,
            weekdaySetKind: .explicit,
            weekdays: [.monday]
        )
        #expect(repeatModel.hasChanges)
        repeatModel.repeatRule = .daily(interval: 1)
        #expect(!repeatModel.hasChanges)
        repeatModel.repeatEnd = .onDate(SourceDate(year: 2040, month: 9, day: 30))
        #expect(repeatModel.hasChanges)
        repeatModel.repeatEnd = .never
        #expect(!repeatModel.hasChanges)

        let earlyModel = ReminderFormModel(
            snapshot: validSnapshot(
                rule: .daily(interval: 1),
                early: EarlyReminder(value: 5, unit: .minutes)
            ),
            savedRepeatPresentation: .standard(localizedSummary: "Every day."),
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert
        )
        earlyModel.earlyReminder = EarlyReminder(value: 1, unit: .minutes)
        #expect(earlyModel.hasChanges)
        earlyModel.earlyReminder = EarlyReminder(value: 5, unit: .minutes)
        #expect(!earlyModel.hasChanges)

        let customReplacementModel = existingModel()
        customReplacementModel.beginCustomReplacement()
        #expect(customReplacementModel.hasChanges)
        customReplacementModel.repeatRule = .daily(interval: 1)
        #expect(!customReplacementModel.hasChanges)

        let customTextModel = existingModel()
        customTextModel.beginCustomReplacement()
        customTextModel.updateCustomRepeatText("every 3 days")
        #expect(customTextModel.hasChanges)
        customTextModel.repeatRule = .daily(interval: 1)
        #expect(!customTextModel.hasChanges)
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
        let snapshot = validSnapshot(
            schedule: .domainInvalid(
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

    @Test func expiredNewReminderCanSaveAfterExpiredScheduleConfirmation() async {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let recorder = SaveActionRecorder(outcomes: [
            .requiresExpiredScheduleConfirmation(
                ExpiredScheduleWarning(
                    reminderID: id,
                    evaluationNow: date("2040-08-01T00:00:00Z")
                )),
            .saved(id)
        ])
        let model = ReminderFormModel(
            newReminderID: id,
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
        model.title = "Expired one-shot reminder"
        model.sourceDate = SourceDate(year: 2040, month: 7, day: 31)
        model.sourceTime = SourceTime(hour: 9, minute: 30)
        model.timeZoneIdentifier = "America/New_York"

        #expect(model.previewNotifications.isEmpty)
        #expect(model.canSave)

        await model.save()
        #expect(await model.confirmExpiredSave())
        #expect(
            await recorder.recordedCalls().map(\.expiredConsent) == [
                .notProvided,
                .acknowledged
            ])
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

        #expect(
            model.previewNotifications.map(\.alertInstant) == [
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

        guard case .awaitingConfirmation(let preview) = model.customRepeatState else {
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
        guard case .replace(let schedule) = model.detachedDraft.scheduleChange else {
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
        guard case .awaitingConfirmation(let preview) = model.customRepeatState else {
            Issue.record("Expected the selected suggestion to produce a confirmation preview")
            return
        }
        #expect(preview.canonicalEnglish == "Every Tuesday")
        #expect(model.repeatRule == originalRule)

        await model.confirmCustomRepeat()

        #expect(
            model.repeatRule
                == .weekly(
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
        #expect(
            first.detachedDraft.originalScheduleData == second.detachedDraft.originalScheduleData)
    }

    @Test func confirmationsReplayTheSameDetachedDraftThroughTheSaveAction() async {
        let recorder = SaveActionRecorder(outcomes: [
            .requiresCapacityConfirmation(
                CapacityWarning(
                    reminderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
                    earliestGroupID: AlertGroupID(
                        reminderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
                        baseOccurrenceInstant: date("2040-08-31T13:30:00Z")
                    ),
                    planningCapacity: 60
                )),
            .requiresExpiredScheduleConfirmation(
                ExpiredScheduleWarning(
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

    @Test func expiredConfirmationIsConsumedBeforeAlertAutoDismissAndRunsExactlyOnce() async {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let recorder = SaveActionRecorder(outcomes: [
            .requiresExpiredScheduleConfirmation(
                ExpiredScheduleWarning(
                    reminderID: id,
                    evaluationNow: date("2040-08-31T13:30:00Z")
                )),
            .saved(id)
        ])
        let model = configuredNewModel(recorder: recorder)

        await model.save()
        #expect(model.consumeExpiredScheduleConfirmation())

        model.dismissPendingConfirmation()
        let saved = await model.performConfirmedExpiredScheduleSave()
        let staleReplay = await model.performConfirmedExpiredScheduleSave()

        #expect(saved)
        #expect(!staleReplay)
        #expect(
            await recorder.recordedCalls().map(\.expiredConsent) == [
                .notProvided,
                .acknowledged
            ])
        #expect(model.saveState == .saved(id))
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
        populateSchedule(
            model,
            rule: .weekly(
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
        await gate.resolve(
            .requiresCapacityConfirmation(
                CapacityWarning(
                    reminderID: model.detachedDraft.id,
                    earliestGroupID: AlertGroupID(
                        reminderID: model.detachedDraft.id,
                        baseOccurrenceInstant: date("2040-08-31T13:30:00Z")
                    ),
                    planningCapacity: 60
                )))
        _ = await saveTask.value

        #expect(model.detachedDraft.title == "Edited while saving")
        #expect(model.saveState == .idle)
    }

    @Test func discardRestoresBaselineAndClearsTransientState() async {
        let model = ReminderFormModel(
            snapshot: validSnapshot(),
            savedRepeatPresentation: .custom(
                localizedSummary: "毎週月曜日に繰り返します。",
                canonicalEnglishDisclosure: "Every Monday"
            ),
            now: date("2040-08-01T00:00:00Z"),
            actions: ReminderFormActions(
                save: { _, _, _ in throw SaveProbeError.failed },
                delete: { _ in }
            )
        )
        model.title = "Changed"
        _ = await model.save()
        #expect(model.saveState == .failed(.save))

        model.requestDeleteConfirmation()
        model.discardChanges()

        #expect(model.title == "Visa renewal")
        #expect(model.saveState == .idle)
        #expect(!model.isDeleteConfirmationPresented)
        #expect(!model.hasChanges)
        #expect(model.currentLocalizedRepeatSummary == "毎週月曜日に繰り返します。")
        #expect(model.canonicalEnglishDisclosure == "Every Monday")
    }

    @Test func discardDuringSuspendedSaveDiscardsStaleCapacityOutcome() async {
        let gate = SuspendedSaveAction()
        let model = ReminderFormModel(
            snapshot: validSnapshot(),
            savedRepeatPresentation: .standard(localizedSummary: "Every week."),
            now: date("2040-08-01T00:00:00Z"),
            actions: ReminderFormActions(
                save: { draft, _, _ in await gate.save(draft: draft) },
                delete: { _ in }
            )
        )
        model.title = "Changed while saving"
        let saveTask = Task { await model.save() }
        await gate.waitUntilCalled()

        model.discardChanges()
        await gate.resolve(
            .requiresCapacityConfirmation(
                CapacityWarning(
                    reminderID: model.detachedDraft.id,
                    earliestGroupID: AlertGroupID(
                        reminderID: model.detachedDraft.id,
                        baseOccurrenceInstant: date("2040-08-31T13:30:00Z")
                    ),
                    planningCapacity: 60
                )))
        _ = await saveTask.value

        #expect(model.title == "Visa renewal")
        #expect(model.saveState == .idle)
        #expect(!model.hasChanges)
    }

    @Test func discardThenNewSaveKeepsNewSaveActiveWhenEarlierSaveCompletes() async {
        let gate = SuspendedSaveAction()
        let model = ReminderFormModel(
            snapshot: validSnapshot(),
            savedRepeatPresentation: .standard(localizedSummary: "Every week."),
            now: date("2040-08-01T00:00:00Z"),
            actions: ReminderFormActions(
                save: { draft, _, _ in await gate.save(draft: draft) },
                delete: { _ in }
            )
        )
        model.title = "First save"
        let firstSave = Task { await model.save() }
        await gate.waitUntilCalled()

        model.discardChanges()
        let secondSave = Task { await model.save() }
        await gate.waitUntilCalled(times: 2)

        await gate.resolve(.saved(model.detachedDraft.id))
        await Task.yield()

        #expect(model.saveState == .saving)

        await gate.resolve(.saved(model.detachedDraft.id))
        _ = await firstSave.value
        _ = await secondSave.value
    }

    @Test func selectingCustomFromNoneUsesFiveMinuteDefault() {
        let model = ReminderFormModel(
            newReminderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert
        )
        populateSchedule(model, rule: .daily(interval: 1))

        model.applyEarlyReminderChoice(.custom)

        #expect(model.earlyReminderChoice == .custom)
        #expect(model.earlyReminder == EarlyReminder(value: 5, unit: .minutes))
        #expect(model.earlyReminderAmountChoices == Array(1...59))
    }

    @Test func clearingExistingRequiredTimeZoneKeepsInvalidReplacementIntent() {
        let zoneModel = ReminderFormModel(
            snapshot: validSnapshot(),
            savedRepeatPresentation: .standard(localizedSummary: "Every week."),
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert
        )
        zoneModel.timeZoneIdentifier = nil

        #expect(zoneModel.timeZoneFieldIssue == .timeZoneRequired)
        #expect(!zoneModel.canSave)
        #expect(zoneModel.detachedDraft.scheduleChange == .preserveOriginal)
    }

    @Test func metadataOnlyUIValidationIgnoresStaleOpaqueScheduleBytes() {
        let stale = Data(repeating: 0xFF, count: ReminderLimits.scheduleBytes + 1)
        let model = ReminderFormModel(
            snapshot: validSnapshot(
                schedule: .unsupportedFuture(
                    version: 99,
                    originalData: stale
                )),
            savedRepeatPresentation: nil,
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert
        )

        model.title = "Metadata edit"

        #expect(model.canSave)
        #expect(model.detachedDraft.originalScheduleData == stale)
        #expect(model.detachedDraft.scheduleChange == .preserveOriginal)
    }

    @Test func sourceDateEditRecomputesEveryAnchorDependentRepeatSummary() {
        let cases: [(RepeatRule, SavedRepeatPresentation)] = [
            (
                .weekly(interval: 1, weekdaySetKind: .explicit, weekdays: [.friday]),
                .standard(localizedSummary: "stale weekly")
            ),
            (
                .weekly(interval: 2, weekdaySetKind: .explicit, weekdays: [.friday]),
                .standard(localizedSummary: "stale biweekly")
            ),
            (
                .monthly(interval: 1, selector: .anchorDay),
                .standard(localizedSummary: "stale monthly")
            ),
            (
                .yearly(interval: 1, month: nil, selector: .anchorMonthDay),
                .standard(localizedSummary: "stale yearly")
            ),
            (
                .monthly(interval: 2, selector: .anchorDay),
                .custom(
                    localizedSummary: "stale custom",
                    canonicalEnglishDisclosure: "Every 2 months on day 31"
                )
            )
        ]

        for (rule, presentation) in cases {
            let model = ReminderFormModel(
                snapshot: validSnapshot(rule: rule),
                savedRepeatPresentation: presentation,
                now: date("2040-08-01T00:00:00Z"),
                actions: .inert,
                localizedRepeatSummary: { schedule in
                    "localized-\(schedule.source.year)-\(schedule.source.month)-\(schedule.source.day)"
                }
            )

            model.updateSourceDate(from: date("2040-09-01T16:00:00Z"))

            #expect(model.currentLocalizedRepeatSummary == "localized-2040-9-1")
            if case .custom = presentation {
                #expect(model.canonicalEnglishDisclosure == nil)
            }
        }
    }

    @Test func earlyPresetAndCustomTransitionsUpdateDetachedDraftExactly() {
        let model = ReminderFormModel(
            newReminderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert
        )
        populateSchedule(model, rule: .daily(interval: 1))

        model.applyEarlyReminderChoice(.thirtySeconds)
        #expect(model.earlyReminderChoice == .thirtySeconds)
        #expect(model.earlyReminder == EarlyReminder(value: 30, unit: .seconds))

        model.applyEarlyReminderChoice(.custom)
        model.updateEarlyReminderAmount(59)
        #expect(model.earlyReminder == EarlyReminder(value: 59, unit: .seconds))

        model.updateEarlyReminderUnit(.hours)
        #expect(model.earlyReminder == EarlyReminder(value: 23, unit: .hours))
        #expect(model.earlyReminderAmountChoices == Array(1...23))

        model.applyEarlyReminderChoice(.oneMinute)
        #expect(model.earlyReminderChoice == .oneMinute)
        #expect(model.earlyReminder == EarlyReminder(value: 1, unit: .minutes))

        model.updateMainNotificationEnabled(false)
        model.applyEarlyReminderChoice(.fiveMinutes)
        #expect(model.earlyReminderChoice == .fiveMinutes)
        #expect(
            model.earlyReminder
                == EarlyReminder(
                    value: 5,
                    unit: .minutes,
                    mainEnabled: false
                ))

        model.applyEarlyReminderChoice(.none)
        #expect(model.earlyReminderChoice == .none)
        #expect(model.earlyReminder == nil)

        model.applyEarlyReminderChoice(.custom)
        model.updateEarlyReminderAmount(1)
        #expect(model.earlyReminderChoice == .custom)
        #expect(model.earlyReminder == EarlyReminder(value: 1, unit: .minutes))
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

    @Test func repeatPresetsUseTheSourceAnchor() {
        let model = ReminderFormModel(
            newReminderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert
        )
        populateSchedule(model, rule: .none)

        #expect(model.applyRepeatPreset(.weekends))
        #expect(
            model.repeatRule
                == .weekly(
                    interval: 1,
                    weekdaySetKind: .weekend,
                    weekdays: [.saturday, .sunday]
                ))
        #expect(model.applyRepeatPreset(.biweekly))
        #expect(
            model.repeatRule
                == .weekly(
                    interval: 2,
                    weekdaySetKind: .explicit,
                    weekdays: [.friday]
                ))
        model.updateSourceDate(from: date("2040-09-01T16:00:00Z"))
        #expect(
            model.repeatRule
                == .weekly(
                    interval: 2,
                    weekdaySetKind: .explicit,
                    weekdays: [.saturday]
                ))
        #expect(model.applyRepeatPreset(.every6Months))
        #expect(model.repeatRule == .monthly(interval: 6, selector: .anchorDay))
    }

    @Test func repeatEndPickerStoresSourceZoneDate() {
        let model = configuredNewModel(recorder: SaveActionRecorder(outcomes: []))
        let sourceDate = model.sourceDate
        let sourceTime = model.sourceTime
        let timeZoneIdentifier = model.timeZoneIdentifier
        let repeatRule = model.repeatRule
        let earlyReminder = model.earlyReminder

        model.setRepeatEndsOnDate(true)
        #expect(model.repeatEnd == .never)
        #expect(model.repeatEndDatePickerValue == nil)
        #expect(!model.canSave)
        #expect(model.previewNotifications.isEmpty)

        model.updateRepeatEndDate(from: date("2040-09-30T16:00:00Z"))

        #expect(model.repeatEnd == .onDate(SourceDate(year: 2040, month: 9, day: 30)))
        #expect(model.repeatEndDatePickerValue == date("2040-09-30T16:00:00Z"))
        #expect(model.repeatEndDateFieldIssue == nil)
        #expect(model.canSave)
        #expect(model.sourceDate == sourceDate)
        #expect(model.sourceTime == sourceTime)
        #expect(model.timeZoneIdentifier == timeZoneIdentifier)
        #expect(model.repeatRule == repeatRule)
        #expect(model.earlyReminder == earlyReminder)
    }

    @Test func fieldIssuesIdentifyMetadataTimeZoneAndEndDateFailures() {
        let model = ReminderFormModel(
            newReminderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert
        )
        populateSchedule(model, rule: .daily(interval: 1))

        model.title = "   "
        #expect(model.titleFieldIssue == nil)
        #expect(!model.canSave)

        model.title = String(repeating: "a", count: ReminderLimits.titleBytes + 1)
        #expect(model.titleFieldIssue == .titleTooLarge)
        #expect(!model.canSave)

        model.notes = String(repeating: "n", count: ReminderLimits.notesBytes + 1)
        #expect(model.notesFieldIssue == .notesTooLarge)

        model.urlString = "ftp://example.com/file"
        #expect(model.urlFieldIssue == .urlInvalid)

        model.timeZoneIdentifier = "Mars/Olympus_Mons"
        #expect(model.timeZoneFieldIssue == .timeZoneInvalid)

        model.timeZoneIdentifier = "America/New_York"
        model.setRepeatEndsOnDate(true)
        model.updateRepeatEndDate(from: date("2040-08-30T16:00:00Z"))
        #expect(model.repeatEndDateFieldIssue == .repeatEndBeforeStart)
        #expect(!model.canSave)
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

    private func existingModel() -> ReminderFormModel {
        ReminderFormModel(
            snapshot: validSnapshot(rule: .daily(interval: 1)),
            savedRepeatPresentation: .standard(localizedSummary: "Every day."),
            now: date("2040-08-01T00:00:00Z"),
            actions: .inert
        )
    }

    private func populateSchedule(_ model: ReminderFormModel, rule: RepeatRule) {
        model.title = "Travel insurance"
        model.sourceDate = SourceDate(year: 2040, month: 8, day: 31)
        model.sourceTime = SourceTime(hour: 9, minute: 30)
        model.timeZoneIdentifier = "America/New_York"
        model.repeatRule = rule
    }

    private func validSnapshot(
        schedule: ScheduleReadState? = nil,
        rule: RepeatRule = .weekly(
            interval: 1,
            weekdaySetKind: .explicit,
            weekdays: [.monday]
        ),
        early: EarlyReminder? = nil
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
            rule: rule,
            end: .never,
            early: early
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
        guard let date = ISO8601DateFormatter().date(from: value) else {
            preconditionFailure("Invalid ISO-8601 test fixture: \(value)")
        }
        return date
    }
}

enum OpaqueScheduleFixture: Sendable, CaseIterable {
    case unsupported
    case corrupt

    func schedule(raw: Data) -> ScheduleReadState {
        switch self {
        case .unsupported: .unsupportedFuture(version: 3, originalData: raw)
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
        calls.append(
            SaveActionCall(
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
    private var callCount = 0
    private var callWaiters: [(times: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var resultContinuations: [CheckedContinuation<SaveReminderOutcome, Never>] = []

    func save(draft: ReminderDraft) async -> SaveReminderOutcome {
        callCount += 1
        let readyWaiters = callWaiters.filter { $0.times <= callCount }
        callWaiters.removeAll { $0.times <= callCount }
        for waiter in readyWaiters {
            waiter.continuation.resume()
        }
        return await withCheckedContinuation { continuation in
            resultContinuations.append(continuation)
        }
    }

    func waitUntilCalled(times: Int = 1) async {
        guard callCount < times else { return }
        await withCheckedContinuation { continuation in
            callWaiters.append((times: times, continuation: continuation))
        }
    }

    func resolve(_ outcome: SaveReminderOutcome) {
        guard !resultContinuations.isEmpty else { return }
        resultContinuations.removeFirst().resume(returning: outcome)
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

extension ReminderFormActions {
    fileprivate static let inert = Self(
        save: { draft, _, _ in .saved(draft.id) },
        delete: { _ in }
    )
}

extension ReminderFormSaveState {
    fileprivate var isCapacityConfirmation: Bool {
        if case .requiresCapacityConfirmation = self { true } else { false }
    }

    fileprivate var isExpiredConfirmation: Bool {
        if case .requiresExpiredScheduleConfirmation = self { true } else { false }
    }
}
