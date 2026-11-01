import Foundation
import NotificationManagerDomain
import Testing

@testable import NotificationManagerApplication

@Suite("SaveReminderUseCase")
struct SaveReminderUseCaseTests {
    @Test func usesTheDraftUUIDForHypotheticalCapacityAndDurableSave() async throws {
        let draftID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let schedule = oneShotSchedule("2026-08-06T12:00:00Z")
        let repository = InMemoryReminderRepository(
            snapshot: CompleteReminderSnapshot(
                reminders: capacityFillers(count: 60, schedule: schedule),
                tags: []
            )
        )
        let reconciler = RecordingReconcileRequester()
        let clock = SequenceDateSource([
            testDate("2026-08-06T11:00:00Z"),
            testDate("2026-08-06T11:00:01Z"),
            testDate("2026-08-06T11:00:02Z")
        ])
        let useCase = makeSaveUseCase(
            repository: repository,
            reconciler: reconciler,
            clock: clock,
            deviceEnabled: true,
            authorization: .allowed
        )
        let draft = replacementDraft(id: draftID, schedule: schedule)

        let warningOutcome = try await useCase.execute(
            draft: draft,
            capacityConsent: .notProvided
        )
        guard case .requiresCapacityConfirmation(let warning) = warningOutcome else {
            Issue.record("Expected capacity confirmation, got \(warningOutcome)")
            return
        }
        #expect(warning.reminderID == draftID)
        #expect(warning.earliestGroupID.reminderID == draftID)
        #expect(await repository.savedMutations.isEmpty)

        let savedOutcome = try await useCase.execute(
            draft: draft,
            capacityConsent: .acknowledged
        )

        #expect(savedOutcome == .saved(draftID))
        #expect(await repository.savedMutations.map(\.id) == [draftID])
        #expect(await reconciler.reasons == [.reminderSaved(draftID)])
    }

    @Test func hypotheticalPlanningReplacesExistingReminderWithoutDuplication() async throws {
        let draftID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let fillerSchedule = oneShotSchedule("2026-08-06T12:00:00Z")
        let oneRequestSchedule = oneShotSchedule("2026-08-06T12:10:00Z")
        let twoRequestSchedule = ScheduleDefinition(
            source: oneRequestSchedule.source,
            rule: oneRequestSchedule.rule,
            end: oneRequestSchedule.end,
            early: EarlyReminder(value: 5, unit: .minutes)
        )
        let existing = reminderSnapshot(id: draftID, schedule: oneRequestSchedule)
        let repository = InMemoryReminderRepository(
            snapshot: CompleteReminderSnapshot(
                reminders: capacityFillers(count: 59, schedule: fillerSchedule) + [existing],
                tags: []
            )
        )
        let useCase = makeSaveUseCase(
            repository: repository,
            clock: SequenceDateSource([testDate("2026-08-06T11:00:00Z")]),
            deviceEnabled: true,
            authorization: .allowed
        )
        var draft = replacementDraft(id: draftID, schedule: twoRequestSchedule)
        draft = ReminderDraft(
            id: draft.id,
            title: draft.title,
            source: twoRequestSchedule.source,
            rule: twoRequestSchedule.rule,
            end: twoRequestSchedule.end,
            early: twoRequestSchedule.early,
            scheduleChange: .replace(twoRequestSchedule),
            originalScheduleData: existing.schedule.originalBytes,
            createdAt: draft.createdAt,
            updatedAt: draft.updatedAt
        )

        let outcome = try await useCase.execute(draft: draft)

        guard case .requiresCapacityConfirmation(let warning) = outcome else {
            Issue.record("Expected replacement schedule to exceed capacity, got \(outcome)")
            return
        }
        #expect(warning.reminderID == draftID)
        #expect(await repository.savedMutations.isEmpty)
    }

    @Test func evaluatesRecurringSchedulesAtFreshSaveTimeAndSelectsTheNextAlert() async throws {
        let repository = InMemoryReminderRepository()
        let clock = SequenceDateSource([
            testDate("2026-08-06T12:01:00Z"),
            testDate("2026-08-06T12:02:00Z")
        ])
        let useCase = makeSaveUseCase(
            repository: repository,
            clock: clock,
            deviceEnabled: false
        )
        let schedule = ScheduleDefinition(
            source: oneShotSchedule("2026-08-06T12:00:00Z").source,
            rule: .daily(interval: 1),
            end: .never,
            early: nil
        )
        let draft = replacementDraft(id: TestApplicationValues.reminderID, schedule: schedule)

        let outcome = try await useCase.execute(draft: draft)

        #expect(outcome == .saved(TestApplicationValues.reminderID))
        #expect(await repository.savedMutations.count == 1)
    }

    @Test func newExpiredReminderRequiresConsentBeforeCreate() async throws {
        let repository = InMemoryReminderRepository(snapshot: .init(reminders: [], tags: []))
        let useCase = makeSaveUseCase(
            repository: repository,
            clock: SequenceDateSource([
                testDate("2026-08-06T12:00:00Z"),
                testDate("2026-08-06T12:00:01Z"),
                testDate("2026-08-06T12:00:02Z")
            ]),
            deviceEnabled: false
        )
        let draft = replacementDraft(
            id: TestApplicationValues.reminderID,
            schedule: oneShotSchedule("2026-08-05T12:00:00Z")
        )

        #expect(
            try await useCase.execute(draft: draft)
                == .requiresExpiredScheduleConfirmation(
                    ExpiredScheduleWarning(
                        reminderID: draft.id,
                        evaluationNow: testDate("2026-08-06T12:00:00Z")
                    )))
        #expect(await repository.savedMutations.isEmpty)

        #expect(
            try await useCase.execute(
                draft: draft,
                expiredScheduleConsent: .acknowledged
            ) == .saved(draft.id))
        #expect(await repository.savedMutations.count == 1)
    }

    @Test func commitBoundaryRequestsExpiredConsentForANewReminderWhoseOnlyAlertJustPassed()
        async throws
    {
        let repository = InMemoryReminderRepository()
        let reconciler = RecordingReconcileRequester()
        let clock = SequenceDateSource([
            testDate("2026-08-06T11:59:59Z"),
            testDate("2026-08-06T12:00:00Z")
        ])
        let useCase = SaveReminderUseCase(
            repository: repository,
            scheduleCodec: TestScheduleCodec(),
            preferenceStore: FixedDeviceNotificationPreferenceStore(enabled: false),
            authorizationState: { .allowed },
            reconcileRequester: reconciler,
            now: clock.now,
            recurrenceEnvironment: FoundationRecurrenceEnvironment()
        )
        let draft = replacementDraft(
            id: TestApplicationValues.reminderID,
            schedule: oneShotSchedule("2026-08-06T12:00:00Z")
        )

        #expect(
            try await useCase.execute(draft: draft, capacityConsent: .acknowledged)
                == .requiresExpiredScheduleConfirmation(
                    ExpiredScheduleWarning(
                        reminderID: draft.id,
                        evaluationNow: testDate("2026-08-06T12:00:00Z")
                    )))
        #expect(await repository.reminders.isEmpty)
        #expect(await reconciler.reasons.isEmpty)
    }

    @Test func commitBoundaryRequestsExpiredConsentForAnExistingScheduleEdit() async throws {
        let raw = Data("old-schedule".utf8)
        let schedule = oneShotSchedule("2026-08-06T12:00:00Z")
        let existing = reminderSnapshot(
            id: TestApplicationValues.reminderID,
            schedule: schedule,
            scheduleData: raw
        )
        let repository = InMemoryReminderRepository(
            snapshot: CompleteReminderSnapshot(
                reminders: [existing],
                tags: []
            ))
        let useCase = makeSaveUseCase(
            repository: repository,
            clock: SequenceDateSource([
                testDate("2026-08-06T11:59:59Z"),
                testDate("2026-08-06T12:00:00Z")
            ]),
            deviceEnabled: false
        )
        let draft = existingReplacementDraft(
            id: TestApplicationValues.reminderID,
            schedule: schedule,
            originalData: raw
        )

        let outcome = try await useCase.execute(draft: draft)

        guard case .requiresExpiredScheduleConfirmation(let warning) = outcome else {
            Issue.record("Expected expired-schedule confirmation, got \(outcome)")
            return
        }
        #expect(warning.reminderID == draft.id)
        #expect(warning.evaluationNow == testDate("2026-08-06T12:00:00Z"))
        #expect(await repository.savedMutations.isEmpty)
    }

    @Test func ongoingRangeSavesWithoutExpiredScheduleConsent() async throws {
        let repository = InMemoryReminderRepository()
        let useCase = makeSaveUseCase(
            repository: repository,
            clock: SequenceDateSource([
                testDate("2026-08-06T12:30:00Z"),
                testDate("2026-08-06T12:30:01Z")
            ]),
            deviceEnabled: false
        )
        let schedule = ScheduleDefinition(
            source: oneShotSchedule("2026-08-06T12:00:00Z").source,
            rule: .none,
            end: .never,
            early: nil,
            durationSeconds: 3_600
        )
        let draft = replacementDraft(id: TestApplicationValues.reminderID, schedule: schedule)

        #expect(try await useCase.execute(draft: draft) == .saved(draft.id))
        #expect(await repository.savedMutations.count == 1)
    }

    @Test func rangeThatEndsDuringSaveRequiresFreshExpiredConsent() async throws {
        let repository = InMemoryReminderRepository()
        let end = testDate("2026-08-06T13:00:00Z")
        let useCase = makeSaveUseCase(
            repository: repository,
            clock: SequenceDateSource([end.addingTimeInterval(-1), end]),
            deviceEnabled: false
        )
        let schedule = ScheduleDefinition(
            source: oneShotSchedule("2026-08-06T12:00:00Z").source,
            rule: .none,
            end: .never,
            early: nil,
            durationSeconds: 3_600
        )
        let draft = replacementDraft(id: TestApplicationValues.reminderID, schedule: schedule)

        #expect(
            try await useCase.execute(draft: draft)
                == .requiresExpiredScheduleConfirmation(
                    ExpiredScheduleWarning(reminderID: draft.id, evaluationNow: end)))
        #expect(await repository.savedMutations.isEmpty)
    }

    @Test func existingScheduleReplacementCanBeSavedExhaustedOnlyWithConsent() async throws {
        let raw = Data("old-schedule".utf8)
        let schedule = oneShotSchedule("2026-08-05T12:00:00Z")
        let existing = reminderSnapshot(
            id: TestApplicationValues.reminderID,
            schedule: oneShotSchedule("2026-08-07T12:00:00Z"),
            scheduleData: raw
        )
        let repository = InMemoryReminderRepository(
            snapshot: CompleteReminderSnapshot(
                reminders: [existing],
                tags: []
            ))
        let reconciler = RecordingReconcileRequester()
        let clock = SequenceDateSource([
            testDate("2026-08-06T12:00:00Z"),
            testDate("2026-08-06T12:00:01Z"),
            testDate("2026-08-06T12:00:02Z")
        ])
        let useCase = makeSaveUseCase(
            repository: repository,
            reconciler: reconciler,
            clock: clock,
            deviceEnabled: false
        )
        let draft = existingReplacementDraft(
            id: TestApplicationValues.reminderID,
            schedule: schedule,
            originalData: raw
        )

        let confirmation = try await useCase.execute(draft: draft)
        #expect(
            confirmation
                == .requiresExpiredScheduleConfirmation(
                    ExpiredScheduleWarning(
                        reminderID: draft.id,
                        evaluationNow: testDate("2026-08-06T12:00:00Z")
                    )
                ))
        #expect(await repository.savedMutations.isEmpty)

        let saved = try await useCase.execute(
            draft: draft,
            expiredScheduleConsent: .acknowledged
        )
        #expect(saved == .saved(draft.id))
        #expect(await repository.savedMutations.first?.enabled == true)
        #expect(await reconciler.reasons == [.reminderSaved(draft.id)])
    }

    @Test func metadataOnlyEditOfAnExhaustedValidScheduleSavesWithoutExpiredConsent() async throws {
        let raw = Data([0x00, 0xFE, 0x01])
        let schedule = oneShotSchedule("2026-08-05T12:00:00Z")
        let snapshot = reminderSnapshot(
            id: TestApplicationValues.reminderID,
            schedule: schedule,
            scheduleData: raw
        )
        let repository = InMemoryReminderRepository(
            snapshot: CompleteReminderSnapshot(reminders: [snapshot], tags: [])
        )
        let draft = ReminderDraft(snapshot: snapshot)
        let useCase = makeSaveUseCase(
            repository: repository,
            clock: SequenceDateSource([testDate("2026-08-06T12:00:00Z")]),
            deviceEnabled: false
        )

        let outcome = try await useCase.execute(draft: draft)

        #expect(outcome == .saved(draft.id))
        #expect(
            await repository.savedMutations.first?.command
                == .updateMetadataPreservingCurrentSchedule
        )
        #expect(try await repository.reminder(id: draft.id)?.schedule.originalBytes == raw)
    }

    @Test func opaqueMetadataEditPreservesRawBytesWithoutDecodingOrReencoding() async throws {
        let raw = Data([0xFF, 0x00, 0x80, 0x7B])
        let snapshot = ReminderSnapshot(
            id: TestApplicationValues.reminderID,
            title: "Imported",
            notes: nil,
            urlString: nil,
            enabled: true,
            schedule: .unsupportedFuture(version: 99, originalData: raw),
            tagIDs: [],
            createdAt: testDate("2026-08-01T00:00:00Z"),
            updatedAt: testDate("2026-08-01T00:00:00Z")
        )
        let repository = InMemoryReminderRepository(
            snapshot: CompleteReminderSnapshot(reminders: [snapshot], tags: [])
        )
        let codec = TestScheduleCodec()
        let useCase = makeSaveUseCase(
            repository: repository,
            codec: codec,
            clock: SequenceDateSource([
                testDate("2026-08-06T12:00:00Z"),
                testDate("2026-08-06T12:00:01Z")
            ]),
            deviceEnabled: true,
            authorization: .allowed
        )
        var draft = ReminderDraft(snapshot: snapshot)
        draft.notes = "Metadata only"

        let outcome = try await useCase.execute(draft: draft)

        #expect(outcome == .saved(draft.id))
        #expect(codec.decodeCount == 0)
        #expect(codec.encodeCount == 0)
        #expect(
            await repository.savedMutations.first?.command
                == .updateMetadataPreservingCurrentSchedule
        )
        #expect(try await repository.reminder(id: draft.id)?.schedule.originalBytes == raw)
    }

    @Test func metadataValidationDoesNotRejectStaleDraftBytesWhenDurableBytesAreCurrent()
        async throws
    {
        let current = Data("current-schedule".utf8)
        let snapshot = reminderSnapshot(
            id: TestApplicationValues.reminderID,
            schedule: oneShotSchedule("2026-08-07T12:00:00Z"),
            scheduleData: current
        )
        let repository = InMemoryReminderRepository(
            snapshot: CompleteReminderSnapshot(
                reminders: [snapshot],
                tags: []
            ))
        let stale = Data(repeating: 0xFF, count: ReminderLimits.scheduleBytes + 1)
        let draft = ReminderDraft(
            id: snapshot.id,
            title: "Metadata edit",
            scheduleChange: .preserveOriginal,
            originalScheduleData: stale,
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt
        )
        let useCase = makeSaveUseCase(
            repository: repository,
            clock: SequenceDateSource([testDate("2026-08-06T12:00:00Z")]),
            deviceEnabled: false
        )

        let outcome = try await useCase.execute(draft: draft)

        #expect(outcome == .saved(snapshot.id))
        #expect(try await repository.reminder(id: snapshot.id)?.schedule.originalBytes == current)
    }

    @Test func deviceToggleOffBypassesCapacitySnapshotAcquisition() async throws {
        let repository = InMemoryReminderRepository(fetchError: .snapshot)
        let useCase = makeSaveUseCase(
            repository: repository,
            clock: SequenceDateSource([
                testDate("2026-08-06T11:00:00Z"),
                testDate("2026-08-06T11:00:01Z")
            ]),
            deviceEnabled: false,
            authorization: .allowed
        )
        let draft = replacementDraft(
            id: TestApplicationValues.reminderID,
            schedule: oneShotSchedule("2026-08-06T12:00:00Z")
        )

        #expect(try await useCase.execute(draft: draft) == .saved(draft.id))
        #expect(await repository.snapshotFetchCount == 0)
    }

    @Test func disallowedAuthorizationBypassesCapacitySnapshotAcquisition() async throws {
        let repository = InMemoryReminderRepository(fetchError: .snapshot)
        let useCase = makeSaveUseCase(
            repository: repository,
            clock: SequenceDateSource([
                testDate("2026-08-06T11:00:00Z"),
                testDate("2026-08-06T11:00:01Z")
            ]),
            deviceEnabled: true,
            authorization: .denied
        )
        let draft = replacementDraft(
            id: TestApplicationValues.reminderID,
            schedule: oneShotSchedule("2026-08-06T12:00:00Z")
        )

        #expect(try await useCase.execute(draft: draft) == .saved(draft.id))
        #expect(await repository.snapshotFetchCount == 0)
    }

    @Test func encodingFinishesBeforeAnyRepositoryOperation() async throws {
        let trace = LockedApplicationTrace()
        let repository = InMemoryReminderRepository(trace: trace)
        let codec = TestScheduleCodec(trace: trace)
        let useCase = makeSaveUseCase(
            repository: repository,
            codec: codec,
            clock: SequenceDateSource([
                testDate("2026-08-06T11:00:00Z"),
                testDate("2026-08-06T11:00:01Z")
            ]),
            deviceEnabled: true,
            authorization: .allowed
        )
        let draft = replacementDraft(
            id: TestApplicationValues.reminderID,
            schedule: oneShotSchedule("2026-08-06T12:00:00Z")
        )

        _ = try await useCase.execute(draft: draft, capacityConsent: .acknowledged)

        #expect(trace.events.prefix(3) == [.scheduleEncoded, .snapshotFetched, .repositorySaved])
    }

    @Test func encodeFailureLeavesRepositoryAndReconcileUntouched() async throws {
        let repository = InMemoryReminderRepository()
        let reconciler = RecordingReconcileRequester()
        let codec = TestScheduleCodec(encodeError: .encode)
        let useCase = makeSaveUseCase(
            repository: repository,
            reconciler: reconciler,
            codec: codec,
            clock: SequenceDateSource([testDate("2026-08-06T11:00:00Z")]),
            deviceEnabled: true,
            authorization: .allowed
        )
        let draft = replacementDraft(
            id: TestApplicationValues.reminderID,
            schedule: oneShotSchedule("2026-08-06T12:00:00Z")
        )

        await #expect(throws: CodecTestError.encode) {
            try await useCase.execute(draft: draft)
        }
        #expect(await repository.snapshotFetchCount == 0)
        #expect(await repository.saveAttempts == 0)
        #expect(await reconciler.reasons.isEmpty)
    }

    @Test func persistenceFailureRetainsDetachedDraftAndSuppressesReconcile() async throws {
        let repository = InMemoryReminderRepository(saveError: .save)
        let reconciler = RecordingReconcileRequester()
        let useCase = makeSaveUseCase(
            repository: repository,
            reconciler: reconciler,
            clock: SequenceDateSource([
                testDate("2026-08-06T11:00:00Z"),
                testDate("2026-08-06T11:00:01Z")
            ]),
            deviceEnabled: false
        )
        let draft = replacementDraft(
            id: TestApplicationValues.reminderID,
            schedule: oneShotSchedule("2026-08-06T12:00:00Z")
        )
        let detachedInput = draft

        await #expect(throws: RepositoryTestError.save) {
            try await useCase.execute(draft: draft)
        }
        #expect(draft == detachedInput)
        #expect(await repository.saveAttempts == 1)
        #expect(await repository.savedMutations.isEmpty)
        #expect(await reconciler.reasons.isEmpty)
    }

    @Test func appliesExactAggregateValidationAndPersistsCanonicalValues() async throws {
        let repository = InMemoryReminderRepository()
        let useCase = makeSaveUseCase(
            repository: repository,
            clock: SequenceDateSource([
                testDate("2026-08-06T11:00:00Z"),
                testDate("2026-08-06T11:00:01Z")
            ]),
            deviceEnabled: false
        )
        var draft = replacementDraft(
            id: TestApplicationValues.reminderID,
            schedule: oneShotSchedule("2026-08-06T12:00:00Z")
        )
        draft.urlString = "HTTPS://EXAMPLE.COM:443/a%2Fb"

        _ = try await useCase.execute(draft: draft)

        #expect(await repository.savedMutations.first?.urlString == "https://example.com/a%2Fb")
        #expect(
            await repository.savedMutations.first?.updatedAt
                == testDate("2026-08-06T11:00:01Z")
        )
    }

    @Test func aggregateValidationFailurePreventsPersistence() async throws {
        let repository = InMemoryReminderRepository()
        let useCase = makeSaveUseCase(
            repository: repository,
            clock: SequenceDateSource([testDate("2026-08-06T11:00:00Z")]),
            deviceEnabled: false
        )
        var draft = replacementDraft(
            id: TestApplicationValues.reminderID,
            schedule: oneShotSchedule("2026-08-06T12:00:00Z")
        )
        draft.title = " \n\t "

        await #expect(throws: ReminderValidationIssue.titleEmpty) {
            try await useCase.execute(draft: draft)
        }
        #expect(await repository.saveAttempts == 0)
    }

    @Test func deviceNotificationsOffStillUsesUpdateIntentAndCannotResurrectADeletedReminder()
        async throws
    {
        let raw = Data("current-schedule".utf8)
        let existing = reminderSnapshot(
            id: TestApplicationValues.reminderID,
            schedule: oneShotSchedule("2026-08-07T12:00:00Z"),
            scheduleData: raw
        )
        let repository = InMemoryReminderRepository(
            snapshot: CompleteReminderSnapshot(
                reminders: [existing],
                tags: []
            ))
        var draft = ReminderDraft(snapshot: existing)
        draft.title = "Stale edit"
        try await repository.delete(id: existing.id)
        let useCase = makeSaveUseCase(
            repository: repository,
            clock: SequenceDateSource([testDate("2026-08-06T12:00:00Z")]),
            deviceEnabled: false
        )

        await #expect(throws: RepositoryTestError.reminderNotFound(existing.id)) {
            try await useCase.execute(draft: draft)
        }

        #expect(await repository.savedMutations.isEmpty)
        #expect(try await repository.fetchCompleteSnapshot().reminders.isEmpty)
    }

    @Test func deniedAuthorizationStillUsesReplaceIntentAndCannotResurrectADeletedReminder()
        async throws
    {
        let oldSchedule = oneShotSchedule("2026-08-07T12:00:00Z")
        let replacement = oneShotSchedule("2026-08-08T12:00:00Z")
        let existing = reminderSnapshot(
            id: TestApplicationValues.reminderID,
            schedule: oldSchedule
        )
        let repository = InMemoryReminderRepository(
            snapshot: CompleteReminderSnapshot(
                reminders: [existing],
                tags: []
            ))
        let draft = existingReplacementDraft(
            id: existing.id,
            schedule: replacement,
            originalData: existing.schedule.originalBytes
        )
        try await repository.delete(id: existing.id)
        let useCase = makeSaveUseCase(
            repository: repository,
            clock: SequenceDateSource([
                testDate("2026-08-06T12:00:00Z"),
                testDate("2026-08-06T12:00:01Z")
            ]),
            deviceEnabled: true,
            authorization: .denied
        )

        await #expect(throws: RepositoryTestError.reminderNotFound(existing.id)) {
            try await useCase.execute(draft: draft)
        }

        #expect(await repository.snapshotFetchCount == 0)
        #expect(await repository.savedMutations.isEmpty)
        #expect(try await repository.fetchCompleteSnapshot().reminders.isEmpty)
    }

    @Test func aSuccessfulCreateIsReturnedByAFreshRepositorySnapshot() async throws {
        let repository = InMemoryReminderRepository()
        let useCase = makeSaveUseCase(
            repository: repository,
            clock: SequenceDateSource([
                testDate("2026-08-06T11:00:00Z"),
                testDate("2026-08-06T11:00:01Z")
            ]),
            deviceEnabled: false
        )
        let draft = replacementDraft(
            id: TestApplicationValues.reminderID,
            schedule: oneShotSchedule("2026-08-07T12:00:00Z")
        )

        _ = try await useCase.execute(draft: draft)

        let snapshot = try await repository.fetchCompleteSnapshot()
        #expect(snapshot.reminders.map(\.id) == [draft.id])
        guard case .create = await repository.savedMutations.first?.command else {
            Issue.record("Expected a create mutation command")
            return
        }
    }
}

func testDate(_ value: String) -> Date {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) { return date }
    guard let date = ISO8601DateFormatter().date(from: value) else {
        preconditionFailure("Invalid ISO-8601 test fixture: \(value)")
    }
    return date
}

func oneShotSchedule(_ value: String) -> ScheduleDefinition {
    let date = testDate(value)
    var calendar = Calendar(identifier: .gregorian)
    guard let utc = TimeZone(secondsFromGMT: 0) else {
        preconditionFailure("Foundation must provide the zero-offset time zone")
    }
    calendar.timeZone = utc
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    guard
        let year = components.year,
        let month = components.month,
        let day = components.day,
        let hour = components.hour,
        let minute = components.minute
    else {
        preconditionFailure("Gregorian date fixture must provide complete wall-clock components")
    }
    return ScheduleDefinition(
        source: SourceWallClock(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            timeZoneIdentifier: "Africa/Abidjan"
        ),
        rule: .none,
        end: .never,
        early: nil
    )
}

func replacementDraft(id: UUID, schedule: ScheduleDefinition) -> ReminderDraft {
    ReminderDraft(
        id: id,
        title: "Flight check-in",
        source: schedule.source,
        rule: schedule.rule,
        end: schedule.end,
        early: schedule.early,
        scheduleChange: .replace(schedule),
        createdAt: testDate("2026-08-01T00:00:00Z"),
        updatedAt: testDate("2026-08-01T00:00:00Z")
    )
}

func existingReplacementDraft(
    id: UUID,
    schedule: ScheduleDefinition,
    originalData: Data
) -> ReminderDraft {
    ReminderDraft(
        id: id,
        title: "Flight check-in",
        source: schedule.source,
        rule: schedule.rule,
        end: schedule.end,
        early: schedule.early,
        scheduleChange: .replace(schedule),
        originalScheduleData: originalData,
        createdAt: testDate("2026-08-01T00:00:00Z"),
        updatedAt: testDate("2026-08-01T00:00:00Z")
    )
}

func reminderSnapshot(
    id: UUID,
    schedule: ScheduleDefinition,
    scheduleData: Data = Data("existing-schedule".utf8),
    title: String = "Existing",
    tagIDs: Set<UUID> = []
) -> ReminderSnapshot {
    ReminderSnapshot(
        id: id,
        title: title,
        notes: nil,
        urlString: nil,
        enabled: true,
        schedule: .valid(schedule, sourceVersion: 1, originalData: scheduleData),
        tagIDs: tagIDs,
        createdAt: testDate("2026-08-01T00:00:00Z"),
        updatedAt: testDate("2026-08-01T00:00:00Z")
    )
}

func capacityFillers(count: Int, schedule: ScheduleDefinition) -> [ReminderSnapshot] {
    (1...count).map { value in
        let suffix = String(format: "%012X", value)
        guard let id = UUID(uuidString: "00000000-0000-0000-0000-\(suffix)") else {
            preconditionFailure("Generated capacity filler UUID must be valid: \(suffix)")
        }
        return reminderSnapshot(
            id: id,
            schedule: schedule,
            title: "Filler \(value)"
        )
    }
}

func makeSaveUseCase(
    repository: InMemoryReminderRepository,
    reconciler: RecordingReconcileRequester = RecordingReconcileRequester(),
    codec: TestScheduleCodec = TestScheduleCodec(),
    clock: SequenceDateSource,
    deviceEnabled: Bool,
    authorization: DeviceAuthorizationSchedulingState = .allowed
) -> SaveReminderUseCase {
    SaveReminderUseCase(
        repository: repository,
        scheduleCodec: codec,
        preferenceStore: FixedDeviceNotificationPreferenceStore(enabled: deviceEnabled),
        authorizationState: { authorization },
        reconcileRequester: reconciler,
        now: clock.now,
        recurrenceEnvironment: FoundationRecurrenceEnvironment()
    )
}

enum TestApplicationValues {
    static let reminderID = UUID(uuidString: "123E4567-E89B-12D3-A456-426614174000")!
}

final class SequenceDateSource: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Date]

    init(_ values: [Date]) {
        self.values = values
    }

    func now() -> Date {
        lock.withLock {
            precondition(!values.isEmpty, "The test clock was read too many times")
            return values.removeFirst()
        }
    }
}

enum CodecTestError: Error, Equatable {
    case encode
}

final class TestScheduleCodec: SchedulePayloadCoding, @unchecked Sendable {
    private let lock = NSLock()
    private let encodedData: Data
    private let encodedVersion: UInt32
    private let encodeError: CodecTestError?
    private let trace: LockedApplicationTrace?
    private var storedDecodeCount = 0
    private var storedEncodeCount = 0

    init(
        encodedData: Data = Data("encoded-schedule".utf8),
        encodedVersion: UInt32 = 1,
        encodeError: CodecTestError? = nil,
        trace: LockedApplicationTrace? = nil
    ) {
        self.encodedData = encodedData
        self.encodedVersion = encodedVersion
        self.encodeError = encodeError
        self.trace = trace
    }

    var decodeCount: Int { lock.withLock { storedDecodeCount } }
    var encodeCount: Int { lock.withLock { storedEncodeCount } }

    func decode(_ data: Data) -> ScheduleReadState {
        lock.withLock { storedDecodeCount += 1 }
        trace?.record(.scheduleDecoded)
        return .corrupt(originalData: data)
    }

    func encodeCurrent(_ definition: ScheduleDefinition) throws -> EncodedSchedulePayload {
        lock.withLock { storedEncodeCount += 1 }
        trace?.record(.scheduleEncoded)
        if let encodeError { throw encodeError }
        return EncodedSchedulePayload(version: encodedVersion, data: encodedData)
    }
}

enum RepositoryTestError: Error, Equatable {
    case snapshot
    case save
    case delete
    case reminderNotFound(UUID)
    case duplicateReminderID(UUID)
    case scheduleReplacementNotAllowed(UUID)
    case tagNotFound(UUID)
}

actor InMemoryReminderRepository: ReminderRepository {
    private(set) var reminders: [UUID: ReminderSnapshot]
    private(set) var savedMutations: [EncodedReminderMutation] = []
    private(set) var savedTagMutations: [EncodedTagMutation] = []
    private(set) var snapshotFetchCount = 0
    private(set) var saveAttempts = 0
    private var tagsByID: [UUID: TagSnapshot]
    private let fetchError: RepositoryTestError?
    private let saveError: RepositoryTestError?
    private let deleteError: RepositoryTestError?
    private let deleteTagBeforeNextSaveID: UUID?
    private let trace: LockedApplicationTrace?

    init(
        snapshot: CompleteReminderSnapshot = CompleteReminderSnapshot(reminders: [], tags: []),
        fetchError: RepositoryTestError? = nil,
        saveError: RepositoryTestError? = nil,
        deleteError: RepositoryTestError? = nil,
        deleteTagBeforeNextSaveID: UUID? = nil,
        trace: LockedApplicationTrace? = nil
    ) {
        reminders = Dictionary(uniqueKeysWithValues: snapshot.reminders.map { ($0.id, $0) })
        tagsByID = Dictionary(uniqueKeysWithValues: snapshot.tags.map { ($0.id, $0) })
        self.fetchError = fetchError
        self.saveError = saveError
        self.deleteError = deleteError
        self.deleteTagBeforeNextSaveID = deleteTagBeforeNextSaveID
        self.trace = trace
    }

    func fetchCompleteSnapshot() async throws -> CompleteReminderSnapshot {
        snapshotFetchCount += 1
        trace?.record(.snapshotFetched)
        if let fetchError { throw fetchError }
        return CompleteReminderSnapshot(
            reminders: reminders.values.sorted { $0.id.uuidString < $1.id.uuidString },
            tags: tagsByID.values.sorted { $0.id.uuidString < $1.id.uuidString }
        )
    }

    func reminder(id: UUID) async throws -> ReminderSnapshot? {
        reminders[id]
    }

    func save(_ mutation: EncodedReminderMutation) async throws -> ReminderSnapshot {
        saveAttempts += 1
        if let saveError { throw saveError }
        let schedule: ScheduleReadState
        switch mutation.command {
        case .create(let scheduleData):
            guard reminders[mutation.id] == nil else {
                throw RepositoryTestError.duplicateReminderID(mutation.id)
            }
            schedule = .corrupt(originalData: scheduleData)
        case .updateMetadataPreservingCurrentSchedule:
            guard let current = reminders[mutation.id] else {
                throw RepositoryTestError.reminderNotFound(mutation.id)
            }
            schedule = current.schedule
        case .replaceSchedule(let scheduleData):
            guard let current = reminders[mutation.id] else {
                throw RepositoryTestError.reminderNotFound(mutation.id)
            }
            switch current.schedule {
            case .valid, .domainInvalid:
                break
            case .unsupportedFuture, .corrupt:
                throw RepositoryTestError.scheduleReplacementNotAllowed(mutation.id)
            }
            schedule = .corrupt(originalData: scheduleData)
        }
        if let missingTagID = mutation.tagIDs.first(where: { tagsByID[$0] == nil }) {
            throw RepositoryTestError.tagNotFound(missingTagID)
        }
        trace?.record(.repositorySaved)
        savedMutations.append(mutation)
        let saved = ReminderSnapshot(
            id: mutation.id,
            title: mutation.title,
            notes: mutation.notes,
            urlString: mutation.urlString,
            enabled: mutation.enabled,
            schedule: schedule,
            tagIDs: mutation.tagIDs,
            createdAt: mutation.createdAt,
            updatedAt: mutation.updatedAt
        )
        reminders[mutation.id] = saved
        return saved
    }

    func delete(id: UUID) async throws {
        trace?.record(.repositoryDeleted)
        if let deleteError { throw deleteError }
        guard reminders[id] != nil else { throw RepositoryTestError.reminderNotFound(id) }
        reminders[id] = nil
    }

    func saveTag(_ mutation: EncodedTagMutation) async throws -> TagSnapshot {
        if deleteTagBeforeNextSaveID == mutation.id {
            tagsByID[mutation.id] = nil
        }
        switch mutation.command {
        case .create:
            guard tagsByID[mutation.id] == nil else {
                throw TagRepositoryError.duplicateID(mutation.id)
            }
        case .update:
            guard tagsByID[mutation.id] != nil else {
                throw TagRepositoryError.notFound(mutation.id)
            }
        }
        if tagsByID.values.contains(where: {
            $0.id != mutation.id
                && TagNameNormalizerV1.trimmedDisplayName($0.name)
                    == TagNameNormalizerV1.trimmedDisplayName(mutation.name)
        }) {
            throw TagRepositoryError.duplicateName(
                TagNameNormalizerV1.trimmedDisplayName(mutation.name))
        }
        trace?.record(.tagSaved)
        let tag = TagSnapshot(
            id: mutation.id,
            name: mutation.name,
            normalizedName: mutation.normalizedName,
            normalizationVersion: mutation.normalizationVersion,
            createdAt: mutation.createdAt,
            updatedAt: mutation.updatedAt
        )
        tagsByID[tag.id] = tag
        savedTagMutations.append(mutation)
        return tag
    }

    func deleteTag(id: UUID) async throws {
        guard tagsByID[id] != nil else { throw TagRepositoryError.notFound(id) }
        trace?.record(.tagDeleted)
        tagsByID[id] = nil
        reminders = reminders.mapValues { reminder in
            ReminderSnapshot(
                id: reminder.id,
                title: reminder.title,
                notes: reminder.notes,
                urlString: reminder.urlString,
                enabled: reminder.enabled,
                schedule: reminder.schedule,
                tagIDs: reminder.tagIDs.subtracting([id]),
                createdAt: reminder.createdAt,
                updatedAt: reminder.updatedAt
            )
        }
    }

    func storedTag(id: UUID) -> TagSnapshot? {
        tagsByID[id]
    }
}

struct FixedDeviceNotificationPreferenceStore: DeviceNotificationPreferenceStore {
    let enabled: Bool

    func isEnabled() async -> Bool { enabled }
    func setEnabled(_ enabled: Bool) async {}
}

actor RecordingReconcileRequester: ReconcileRequesting {
    private(set) var reasons: [ReconcileReason] = []
    private let trace: LockedApplicationTrace?

    init(trace: LockedApplicationTrace? = nil) {
        self.trace = trace
    }

    func requestReconcile(_ reason: ReconcileReason) async {
        trace?.record(.reconcileRequested)
        reasons.append(reason)
    }
}

enum ApplicationTraceEvent: Sendable, Equatable {
    case scheduleEncoded
    case scheduleDecoded
    case snapshotFetched
    case repositorySaved
    case repositoryDeleted
    case notificationsCleaned
    case reconcileRequested
    case tagSaved
    case tagDeleted
}

final class LockedApplicationTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [ApplicationTraceEvent] = []

    var events: [ApplicationTraceEvent] { lock.withLock { storedEvents } }

    func record(_ event: ApplicationTraceEvent) {
        lock.withLock { storedEvents.append(event) }
    }
}

extension ScheduleReadState {
    var originalBytes: Data {
        switch self {
        case .valid(_, _, let data),
            .unsupportedFuture(_, let data),
            .corrupt(let data),
            .domainInvalid(_, let data, _):
            data
        }
    }
}
