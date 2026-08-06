import Foundation
import Testing
import UserNotifications
import NotificationManagerDomain
@testable import NotificationManager

struct NotificationRequestMaterializerTests {
    @Test func localeChangesOnlyLocalizedContent() throws {
        let logical = try oneShotRequest()
        let materializer = testMaterializer()

        let english = try materializer.materialize(
            logical,
            input: MaterializationInput(reminder: reminder(), locale: Locale(identifier: "en_US"))
        )
        let japanese = try materializer.materialize(
            logical,
            input: MaterializationInput(reminder: reminder(), locale: Locale(identifier: "ja_JP"))
        )

        #expect(english.identifier == japanese.identifier)
        #expect(calendarTrigger(english).dateComponents == calendarTrigger(japanese).dateComponents)
        #expect(calendarTrigger(english).repeats == calendarTrigger(japanese).repeats)
        #expect(english.content.title == japanese.content.title)
        #expect(english.content.body != japanese.content.body)
        #expect(english.content.userInfo["notification-manager.reminder-id"] as? String
            == japanese.content.userInfo["notification-manager.reminder-id"] as? String)
    }

    @Test func oneShotUsesFullUTCGregorianComponentsAndExactNextDate() throws {
        let instant = date("2040-08-31T13:30:45Z")
        let request = try testMaterializer().materialize(
            oneShotRequest(alertInstant: instant),
            input: MaterializationInput(reminder: reminder(), locale: Locale(identifier: "en_US"))
        )
        let trigger = calendarTrigger(request)
        let components = trigger.dateComponents

        #expect(components.calendar?.identifier == .gregorian)
        #expect(components.timeZone?.identifier == "GMT")
        #expect(components.year == 2040)
        #expect(components.month == 8)
        #expect(components.day == 31)
        #expect(components.hour == 13)
        #expect(components.minute == 30)
        #expect(components.second == 45)
        #expect(trigger.repeats == false)
        #expect(trigger.nextTriggerDate() == instant)
    }

    @Test func repeatingUsesSourceIANAGregorianComponentsAndHasNextDate() throws {
        let components = RepeatingTriggerComponents(
            timeZoneIdentifier: "America/New_York",
            hour: 9,
            minute: 30,
            second: 0
        )
        let request = try testMaterializer().materialize(
            repeatingRequest(components: components),
            input: MaterializationInput(reminder: reminder(), locale: Locale(identifier: "en_US"))
        )
        let trigger = calendarTrigger(request)
        let actual = trigger.dateComponents

        #expect(actual.calendar?.identifier == .gregorian)
        #expect(actual.timeZone?.identifier == "America/New_York")
        #expect(actual.year == nil)
        #expect(actual.month == nil)
        #expect(actual.day == nil)
        #expect(actual.weekday == nil)
        #expect(actual.hour == 9)
        #expect(actual.minute == 30)
        #expect(actual.second == 0)
        #expect(trigger.repeats)
        #expect(trigger.nextTriggerDate() != nil)
    }

    @Test func identitySoundInterruptionAndRoutingFollowCurrentReminder() throws {
        let logical = try oneShotRequest()
        let reminderWithURL = reminder(urlString: "https://example.com/current")
        let withURL = try testMaterializer().materialize(
            logical,
            input: MaterializationInput(
                reminder: reminderWithURL,
                locale: Locale(identifier: "en_US")
            )
        )
        let withoutURL = try testMaterializer().materialize(
            logical,
            input: MaterializationInput(
                reminder: reminder(urlString: nil),
                locale: Locale(identifier: "en_US")
            )
        )

        #expect(withURL.identifier == logical.identifier)
        #expect(withURL.content.sound == .default)
        #expect(withURL.content.interruptionLevel == .active)
        #expect(withURL.content.categoryIdentifier == "notification-manager.open-link")
        #expect(withoutURL.content.categoryIdentifier == "")
        #expect(withURL.content.userInfo.count == 1)
        #expect(withURL.content.userInfo["notification-manager.reminder-id"] as? String
            == "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        #expect(withURL.content.userInfo.values.contains { $0 as? String == reminderWithURL.title } == false)
        #expect(withURL.content.userInfo.values.contains { $0 as? String == reminderWithURL.notes } == false)
        #expect(withURL.content.userInfo.values.contains { $0 as? String == reminderWithURL.urlString } == false)
    }

    @Test func englishAndJapaneseGeneratedTextAreCompleteSentences() throws {
        let logical = try oneShotRequest()
        let source = reminder(notes: nil)
        let materializer = testMaterializer()

        let english = try materializer.materialize(
            logical,
            input: MaterializationInput(reminder: source, locale: Locale(identifier: "en_US"))
        ).content.body
        let japanese = try materializer.materialize(
            logical,
            input: MaterializationInput(reminder: source, locale: Locale(identifier: "ja_JP"))
        ).content.body

        #expect(english == "Every day.\nSource time: 09:30 (America/New_York).\nAt the scheduled time for August 31, 2040 at 09:30.")
        #expect(japanese == "毎日繰り返します。\n基準時刻: 09:30（America/New_York）。\n2040年8月31日09:30の予定時刻です。")
    }

    @Test func notesReplaceRecurrenceSummaryButKeepLocalizedSupplementalText() throws {
        let logical = try oneShotRequest()
        let materializer = testMaterializer()

        let english = try materializer.materialize(
            logical,
            input: MaterializationInput(
                reminder: reminder(notes: "Pack your passport."),
                locale: Locale(identifier: "en_US")
            )
        ).content.body
        let japanese = try materializer.materialize(
            logical,
            input: MaterializationInput(
                reminder: reminder(notes: "パスポートを準備する。"),
                locale: Locale(identifier: "ja_JP")
            )
        ).content.body

        #expect(english == "Pack your passport.\nSource time: 09:30 (America/New_York).\nAt the scheduled time for August 31, 2040 at 09:30.")
        #expect(japanese == "パスポートを準備する。\n基準時刻: 09:30（America/New_York）。\n2040年8月31日09:30の予定時刻です。")
    }

    @Test func oneShotCollisionUsesMainThenConcreteSecondaryEarlyReasons() throws {
        let instant = date("2040-08-31T13:30:00Z")
        let nextBase = occurrence("2040-09-01T13:30:00Z", month: 9, day: 1)
        let logical = try oneShotRequest(
            alertInstant: instant,
            reasons: [
                EffectiveAlert(kind: .early, baseOccurrence: nextBase, alertInstant: instant),
                EffectiveAlert(
                    kind: .main,
                    baseOccurrence: occurrence("2040-08-31T13:30:00Z", day: 31),
                    alertInstant: instant
                )
            ]
        )

        let english = try testMaterializer().materialize(
            logical,
            input: MaterializationInput(reminder: reminder(notes: "Trip."), locale: Locale(identifier: "en_US"))
        ).content.body
        let japanese = try testMaterializer().materialize(
            logical,
            input: MaterializationInput(reminder: reminder(notes: "旅行。"), locale: Locale(identifier: "ja_JP"))
        ).content.body

        #expect(english.hasSuffix("At the scheduled time for August 31, 2040 at 09:30. Also early for September 1, 2040 at 09:30."))
        #expect(japanese.hasSuffix("2040年8月31日09:30の予定時刻です。 さらに、2040年9月1日09:30の早期通知です。"))
    }

    @Test func repeatingContentIsStaticAcrossContributingOccurrenceDates() throws {
        let sourceComponents = RepeatingTriggerComponents(
            timeZoneIdentifier: "America/New_York",
            hour: 9,
            minute: 30,
            second: 0
        )
        let triggerComponents = RepeatingTriggerComponents(
            timeZoneIdentifier: "America/New_York",
            hour: 9,
            minute: 25,
            second: 0
        )
        let contributor = RepeatingTriggerContributor(
            kind: .early,
            sourceComponents: sourceComponents
        )
        let first = repeatingRequest(
            components: triggerComponents,
            contributingBaseInstant: date("2040-09-01T13:30:00Z"),
            contributors: [contributor]
        )
        let second = repeatingRequest(
            components: triggerComponents,
            contributingBaseInstant: date("2041-12-31T14:30:00Z"),
            contributors: [contributor]
        )
        let early = EarlyReminder(value: 5, unit: .minutes, mainEnabled: false)
        let firstInput = MaterializationInput(
            reminder: reminder(
                notes: nil,
                schedule: validScheduleState(
                    early: early
                )
            ),
            locale: Locale(identifier: "en_US"),
            evaluationNow: date("2040-08-31T13:30:00Z"),
            recurrenceEnvironment: .foundation
        )
        let secondInput = MaterializationInput(
            reminder: reminder(
                notes: nil,
                schedule: validScheduleState(
                    source: SourceWallClock(
                        year: 2041,
                        month: 12,
                        day: 30,
                        hour: 9,
                        minute: 30,
                        timeZoneIdentifier: "America/New_York"
                    ),
                    early: early
                )
            ),
            locale: Locale(identifier: "en_US"),
            evaluationNow: date("2041-12-30T14:30:00Z"),
            recurrenceEnvironment: .foundation
        )

        let firstBody = try testMaterializer().materialize(first, input: firstInput).content.body
        let secondBody = try testMaterializer().materialize(second, input: secondInput).content.body

        #expect(firstBody == secondBody)
        #expect(firstBody == "Every day.\nSource time: 09:30 (America/New_York).\nEarly reminder for the next occurrence.")
        #expect(!firstBody.contains("2040"))
        #expect(!firstBody.contains("2041"))
    }

    @Test func titleAndFinalBodyAreTruncatedWithoutMutatingPersistedStrings() throws {
        let originalTitle = String(repeating: "a", count: 300)
        let originalNotes = String(repeating: "👨‍👩‍👧‍👦", count: 300)
        let original = reminder(title: originalTitle, notes: originalNotes)

        let content = try testMaterializer().materialize(
            oneShotRequest(),
            input: MaterializationInput(reminder: original, locale: Locale(identifier: "ja_JP"))
        ).content

        #expect(content.title == String(repeating: "a", count: 253) + "…")
        #expect(content.title.utf8.count == 256)
        #expect(content.body.utf8.count <= 2_048)
        #expect(content.body.hasSuffix("…"))
        #expect(!content.body.contains("�"))
        #expect(original.title == originalTitle)
        #expect(original.notes == originalNotes)
    }

    @Test func invalidInputsHavePreciseMaterializationErrors() throws {
        let validOneShot = try oneShotRequest()
        let differentReminder = reminder(id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
        #expect(throws: NotificationRequestMaterializationError.reminderIDMismatch) {
            try testMaterializer().materialize(
                validOneShot,
                input: MaterializationInput(reminder: differentReminder, locale: Locale(identifier: "en_US"))
            )
        }

        #expect(throws: NotificationRequestMaterializationError.invalidSchedule) {
            try testMaterializer().materialize(
                validOneShot,
                input: MaterializationInput(
                    reminder: reminder(schedule: .corrupt(originalData: Data([0]))),
                    locale: Locale(identifier: "en_US")
                )
            )
        }

        let wrongIdentifier = LogicalNotificationRequest(
            identifier: "notification-manager.local.v1.o.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.0",
            reminderID: validOneShot.reminderID,
            payload: validOneShot.payload,
            contributingGroupIDs: validOneShot.contributingGroupIDs
        )
        #expect(throws: NotificationRequestMaterializationError.identifierDoesNotMatchPayload) {
            try testMaterializer().materialize(
                wrongIdentifier,
                input: MaterializationInput(reminder: reminder(), locale: Locale(identifier: "en_US"))
            )
        }

        let fractionalInstant = Date(timeIntervalSince1970: 1.5)
        #expect(throws: NotificationRequestMaterializationError.invalidOneShotAlertInstant) {
            try testMaterializer().materialize(
                LogicalNotificationRequest(
                    identifier: "notification-manager.local.v1.o.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.1",
                    reminderID: reminderID,
                    payload: .oneShot(alertInstant: fractionalInstant, reasons: [
                        EffectiveAlert(
                            kind: .main,
                            baseOccurrence: occurrence("2040-08-31T13:30:00Z", day: 31),
                            alertInstant: fractionalInstant
                        )
                    ]),
                    contributingGroupIDs: [AlertGroupID(
                        reminderID: reminderID,
                        baseOccurrenceInstant: date("2040-08-31T13:30:00Z")
                    )]
                ),
                input: MaterializationInput(reminder: reminder(), locale: Locale(identifier: "en_US"))
            )
        }

        let emptyReasons = LogicalNotificationRequest(
            identifier: validOneShot.identifier,
            reminderID: reminderID,
            payload: .oneShot(alertInstant: date("2040-08-31T13:30:00Z"), reasons: []),
            contributingGroupIDs: validOneShot.contributingGroupIDs
        )
        #expect(throws: NotificationRequestMaterializationError.invalidOneShotReasons) {
            try testMaterializer().materialize(
                emptyReasons,
                input: MaterializationInput(reminder: reminder(), locale: Locale(identifier: "en_US"))
            )
        }

        let invalidComponents = RepeatingTriggerComponents(
            timeZoneIdentifier: "Not/A_Zone",
            hour: 9,
            minute: 30,
            second: 0
        )
        #expect(throws: NotificationRequestMaterializationError.invalidRepeatingComponents) {
            try testMaterializer().materialize(
                LogicalNotificationRequest(
                    identifier: "notification-manager.local.v1.r.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa." + String(repeating: "0", count: 64),
                    reminderID: reminderID,
                    payload: .repeating(components: invalidComponents, contributors: []),
                    contributingGroupIDs: [AlertGroupID(
                        reminderID: reminderID,
                        baseOccurrenceInstant: date("2040-08-31T13:30:00Z")
                    )]
                ),
                input: MaterializationInput(reminder: reminder(), locale: Locale(identifier: "en_US"))
            )
        }

        let validComponents = RepeatingTriggerComponents(
            timeZoneIdentifier: "America/New_York",
            hour: 9,
            minute: 30,
            second: 0
        )
        let emptyContributors = LogicalNotificationRequest(
            identifier: try NotificationIdentifierCodec().repeatingIdentifier(
                reminderID: reminderID,
                components: validComponents
            ),
            reminderID: reminderID,
            payload: .repeating(components: validComponents, contributors: []),
            contributingGroupIDs: [AlertGroupID(
                reminderID: reminderID,
                baseOccurrenceInstant: date("2040-08-31T13:30:00Z")
            )]
        )
        #expect(throws: NotificationRequestMaterializationError.invalidRepeatingContributors) {
            try testMaterializer().materialize(
                emptyContributors,
                input: MaterializationInput(reminder: reminder(), locale: Locale(identifier: "en_US"))
            )
        }

        let noGroups = LogicalNotificationRequest(
            identifier: validOneShot.identifier,
            reminderID: reminderID,
            payload: validOneShot.payload,
            contributingGroupIDs: []
        )
        #expect(throws: NotificationRequestMaterializationError.invalidContributingGroups) {
            try testMaterializer().materialize(
                noGroups,
                input: MaterializationInput(reminder: reminder(), locale: Locale(identifier: "en_US"))
            )
        }
    }

    @Test func rejectsLogicalPayloadAndFanOutNotDerivedFromCurrentSchedule() throws {
        let base = occurrence("2040-08-31T13:30:00Z", day: 31)
        let main = EffectiveAlert(kind: .main, baseOccurrence: base, alertInstant: base.instant)
        let valid = try oneShotRequest(reasons: [main])

        let unrelatedGroups = LogicalNotificationRequest(
            identifier: valid.identifier,
            reminderID: reminderID,
            payload: valid.payload,
            contributingGroupIDs: valid.contributingGroupIDs.union([
                AlertGroupID(
                    reminderID: reminderID,
                    baseOccurrenceInstant: date("2040-09-01T13:30:00Z")
                )
            ])
        )
        #expect(throws: NotificationRequestMaterializationError.logicalContributorMismatch) {
            try testMaterializer().materialize(
                unrelatedGroups,
                input: MaterializationInput(reminder: reminder(), locale: Locale(identifier: "en_US"))
            )
        }

        let duplicateReasons = LogicalNotificationRequest(
            identifier: valid.identifier,
            reminderID: reminderID,
            payload: .oneShot(alertInstant: base.instant, reasons: [main, main]),
            contributingGroupIDs: valid.contributingGroupIDs
        )
        #expect(throws: NotificationRequestMaterializationError.duplicateLogicalContributors) {
            try testMaterializer().materialize(
                duplicateReasons,
                input: MaterializationInput(reminder: reminder(), locale: Locale(identifier: "en_US"))
            )
        }

        let earlyInstant = date("2040-08-31T13:25:00Z")
        let disallowedEarly = try oneShotRequest(
            alertInstant: earlyInstant,
            reasons: [EffectiveAlert(
                kind: .early,
                baseOccurrence: base,
                alertInstant: earlyInstant
            )]
        )
        #expect(throws: NotificationRequestMaterializationError.reasonKindNotAllowed) {
            try testMaterializer().materialize(
                disallowedEarly,
                input: MaterializationInput(reminder: reminder(), locale: Locale(identifier: "en_US"))
            )
        }

        let mainDisabled = reminder(schedule: validScheduleState(
            early: EarlyReminder(value: 5, unit: .minutes, mainEnabled: false)
        ))
        #expect(throws: NotificationRequestMaterializationError.reasonKindNotAllowed) {
            try testMaterializer().materialize(
                valid,
                input: MaterializationInput(reminder: mainDisabled, locale: Locale(identifier: "en_US"))
            )
        }

        let wrongMainInstant = date("2040-08-31T13:31:00Z")
        let wrongMain = try oneShotRequest(
            alertInstant: wrongMainInstant,
            reasons: [EffectiveAlert(
                kind: .main,
                baseOccurrence: base,
                alertInstant: wrongMainInstant
            )]
        )
        #expect(throws: NotificationRequestMaterializationError.oneShotPayloadNotDerivable) {
            try testMaterializer().materialize(
                wrongMain,
                input: MaterializationInput(reminder: reminder(), locale: Locale(identifier: "en_US"))
            )
        }

        let source = RepeatingTriggerComponents(
            timeZoneIdentifier: "America/New_York",
            hour: 9,
            minute: 30,
            second: 0
        )
        let wrongTarget = RepeatingTriggerComponents(
            timeZoneIdentifier: "America/New_York",
            hour: 10,
            minute: 30,
            second: 0
        )
        let staleRepeating = repeatingRequest(
            components: wrongTarget,
            contributors: [RepeatingTriggerContributor(kind: .main, sourceComponents: source)]
        )
        #expect(throws: NotificationRequestMaterializationError.repeatingPayloadNotDerivable) {
            try testMaterializer().materialize(
                staleRepeating,
                input: MaterializationInput(reminder: reminder(), locale: Locale(identifier: "en_US"))
            )
        }

        let duplicateContributor = RepeatingTriggerContributor(
            kind: .main,
            sourceComponents: source
        )
        #expect(throws: NotificationRequestMaterializationError.duplicateLogicalContributors) {
            try testMaterializer().materialize(
                repeatingRequest(
                    components: source,
                    contributors: [duplicateContributor, duplicateContributor]
                ),
                input: MaterializationInput(reminder: reminder(), locale: Locale(identifier: "en_US"))
            )
        }

        let extraFanOut = LogicalNotificationRequest(
            identifier: try NotificationIdentifierCodec().repeatingIdentifier(
                reminderID: reminderID,
                components: source
            ),
            reminderID: reminderID,
            payload: .repeating(components: source, contributors: [duplicateContributor]),
            contributingGroupIDs: [
                AlertGroupID(
                    reminderID: reminderID,
                    baseOccurrenceInstant: date("2040-08-31T13:30:00Z")
                ),
                AlertGroupID(
                    reminderID: reminderID,
                    baseOccurrenceInstant: date("2040-09-01T13:30:00Z")
                )
            ]
        )
        #expect(throws: NotificationRequestMaterializationError.logicalContributorMismatch) {
            try testMaterializer().materialize(
                extraFanOut,
                input: MaterializationInput(reminder: reminder(), locale: Locale(identifier: "en_US"))
            )
        }
    }

    @Test func rejectsRepeatingPayloadExcludedFromCompleteTask7Plan() throws {
        let dailySource = RepeatingTriggerComponents(
            timeZoneIdentifier: "America/New_York",
            hour: 9,
            minute: 30,
            second: 0
        )
        let collision = repeatingRequest(
            components: dailySource,
            contributors: [RepeatingTriggerContributor(
                kind: .main,
                sourceComponents: dailySource
            )]
        )
        let collisionReminder = reminder(schedule: validScheduleState(
            early: EarlyReminder(value: 1, unit: .days)
        ))
        #expect(throws: NotificationRequestMaterializationError.repeatingPayloadNotDerivable) {
            try testMaterializer().materialize(
                collision,
                input: MaterializationInput(
                    reminder: collisionReminder,
                    locale: Locale(identifier: "en_US")
                )
            )
        }

        let dynamicSource = RepeatingTriggerComponents(
            timeZoneIdentifier: "America/New_York",
            hour: 3,
            minute: 30,
            second: 0
        )
        let dynamicTarget = RepeatingTriggerComponents(
            timeZoneIdentifier: "America/New_York",
            hour: 1,
            minute: 30,
            second: 0
        )
        let dynamic = repeatingRequest(
            components: dynamicTarget,
            contributingBaseInstant: date("2040-09-01T07:30:00Z"),
            contributors: [RepeatingTriggerContributor(
                kind: .early,
                sourceComponents: dynamicSource
            )]
        )
        let dynamicReminder = reminder(schedule: validScheduleState(
            source: SourceWallClock(
                year: 2040,
                month: 8,
                day: 31,
                hour: 3,
                minute: 30,
                timeZoneIdentifier: "America/New_York"
            ),
            early: EarlyReminder(value: 2, unit: .hours, mainEnabled: false)
        ))
        #expect(throws: NotificationRequestMaterializationError.repeatingPayloadNotDerivable) {
            try testMaterializer().materialize(
                dynamic,
                input: MaterializationInput(
                    reminder: dynamicReminder,
                    locale: Locale(identifier: "en_US"),
                    evaluationNow: date("2040-08-31T07:30:00Z"),
                    recurrenceEnvironment: .foundation
                )
            )
        }
    }

    @Test func propagatesRepeatingPlanningOperationalErrorsWithoutPayloadMapping() throws {
        let components = RepeatingTriggerComponents(
            timeZoneIdentifier: "America/New_York",
            hour: 9,
            minute: 30,
            second: 0
        )
        let request = repeatingRequest(components: components)

        #expect(throws: LogicalNotificationPlannerError.invalidEvaluationNow) {
            try testMaterializer().materialize(
                request,
                input: MaterializationInput(
                    reminder: reminder(),
                    locale: Locale(identifier: "en_US"),
                    evaluationNow: Date(timeIntervalSinceReferenceDate: .infinity),
                    recurrenceEnvironment: .foundation
                )
            )
        }
        #expect(throws: SourceWallClockResolutionError.unknownTimeZone) {
            try testMaterializer().materialize(
                request,
                input: MaterializationInput(
                    reminder: reminder(),
                    locale: Locale(identifier: "en_US"),
                    evaluationNow: date("2040-08-31T13:30:00Z"),
                    recurrenceEnvironment: FailAfterFirstTimeZoneLookupEnvironment()
                )
            )
        }
    }

    @Test func oneShotValidationDoesNotInvokeRepeatingPlanningContext() throws {
        let logical = try oneShotRequest()
        let materialized = try testMaterializer().materialize(
            logical,
            input: MaterializationInput(
                reminder: reminder(),
                locale: Locale(identifier: "en_US"),
                evaluationNow: Date(timeIntervalSinceReferenceDate: .infinity),
                recurrenceEnvironment: FailAfterFirstTimeZoneLookupEnvironment()
            )
        )

        #expect(materialized.identifier == logical.identifier)
    }

    @Test func expiredFixtureUsesInjectedTriggerVerificationInsteadOfWallClock() throws {
        let expired = date("2026-08-07T13:30:00Z")
        let expiredSchedule = ScheduleDefinition(
            source: SourceWallClock(
                year: 2026,
                month: 8,
                day: 7,
                hour: 9,
                minute: 30,
                timeZoneIdentifier: "America/New_York"
            ),
            rule: .none,
            end: .never,
            early: nil
        )
        var sourceComponents = DateComponents()
        sourceComponents.calendar = Calendar(identifier: .gregorian)
        sourceComponents.timeZone = TimeZone(identifier: "America/New_York")!
        sourceComponents.year = 2026
        sourceComponents.month = 8
        sourceComponents.day = 7
        sourceComponents.hour = 9
        sourceComponents.minute = 30
        sourceComponents.second = 0
        sourceComponents.weekday = sourceComponents.calendar?.component(
            .weekday,
            from: expired
        )
        let request = try oneShotRequest(
            alertInstant: expired,
            reasons: [EffectiveAlert(
                kind: .main,
                baseOccurrence: BaseOccurrence(
                    instant: expired,
                    sourceComponents: sourceComponents
                ),
                alertInstant: expired
            )]
        )
        let input = MaterializationInput(
            reminder: reminder(schedule: .valid(
                expiredSchedule,
                sourceVersion: 1,
                originalData: Data([1])
            )),
            locale: Locale(identifier: "en_US")
        )

        #expect(throws: NotificationRequestMaterializationError.oneShotTriggerDateMismatch) {
            try NotificationRequestMaterializer(triggerDateVerifier: { _, _ in false })
                .materialize(request, input: input)
        }
        let accepted = try NotificationRequestMaterializer(
            triggerDateVerifier: { _, expected in expected == expired }
        ).materialize(request, input: input)
        #expect(calendarTrigger(accepted).dateComponents.year == 2026)
    }

    @Test func productionTriggerVerificationHasOneLiveFutureSmokeCheck() throws {
        let minute = 60.0
        let future = Date(
            timeIntervalSince1970: (Date().timeIntervalSince1970 / minute).rounded(.up) * minute
                + (7 * 24 * 60 * 60)
        )
        let timeZone = TimeZone(identifier: "Etc/UTC")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .weekday],
            from: future
        )
        let source = SourceWallClock(
            year: components.year!,
            month: components.month!,
            day: components.day!,
            hour: components.hour!,
            minute: components.minute!,
            timeZoneIdentifier: timeZone.identifier
        )
        let schedule = ScheduleDefinition(
            source: source,
            rule: .none,
            end: .never,
            early: nil
        )
        let base = BaseOccurrence(instant: future, sourceComponents: components)
        let request = try oneShotRequest(
            alertInstant: future,
            reasons: [EffectiveAlert(kind: .main, baseOccurrence: base, alertInstant: future)]
        )
        let input = MaterializationInput(
            reminder: reminder(schedule: .valid(
                schedule,
                sourceVersion: 1,
                originalData: Data([1])
            )),
            locale: Locale(identifier: "en_US")
        )

        let materialized = try NotificationRequestMaterializer().materialize(request, input: input)

        #expect(calendarTrigger(materialized).nextTriggerDate() == future)
    }

    private let reminderID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!

    private func reminder(
        id: String = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
        title: String = "Trip checklist",
        notes: String? = nil,
        urlString: String? = "https://example.com/current",
        schedule: ScheduleReadState? = nil
    ) -> ReminderSnapshot {
        let resolvedSchedule = schedule ?? .valid(
            ScheduleDefinition(
                source: SourceWallClock(
                    year: 2040,
                    month: 8,
                    day: 31,
                    hour: 9,
                    minute: 30,
                    timeZoneIdentifier: "America/New_York"
                ),
                rule: .daily(interval: 1),
                end: .never,
                early: nil
            ),
            sourceVersion: 1,
            originalData: Data([1])
        )
        return ReminderSnapshot(
            id: UUID(uuidString: id)!,
            title: title,
            notes: notes,
            urlString: urlString,
            enabled: true,
            schedule: resolvedSchedule,
            tagIDs: [],
            createdAt: date("2040-08-01T00:00:00Z"),
            updatedAt: date("2040-08-01T00:00:00Z")
        )
    }

    private func validScheduleState(
        source: SourceWallClock? = nil,
        rule: RepeatRule = .daily(interval: 1),
        early: EarlyReminder? = nil
    ) -> ScheduleReadState {
        .valid(
            ScheduleDefinition(
                source: source ?? SourceWallClock(
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
            ),
            sourceVersion: 1,
            originalData: Data([1])
        )
    }

    private func oneShotRequest(
        alertInstant: Date = date("2040-08-31T13:30:00Z"),
        reasons: [EffectiveAlert]? = nil
    ) throws -> LogicalNotificationRequest {
        let resolvedReasons = reasons ?? [
            EffectiveAlert(
                kind: .main,
                baseOccurrence: occurrence("2040-08-31T13:30:00Z", day: 31),
                alertInstant: alertInstant
            )
        ]
        return LogicalNotificationRequest(
            identifier: try NotificationIdentifierCodec().oneShotIdentifier(
                reminderID: reminderID,
                alertInstant: alertInstant
            ),
            reminderID: reminderID,
            payload: .oneShot(alertInstant: alertInstant, reasons: resolvedReasons),
            contributingGroupIDs: Set(resolvedReasons.map {
                AlertGroupID(
                    reminderID: reminderID,
                    baseOccurrenceInstant: $0.baseOccurrence.instant
                )
            })
        )
    }

    private func repeatingRequest(
        components: RepeatingTriggerComponents,
        contributingBaseInstant: Date = date("2040-09-01T13:30:00Z"),
        contributors: [RepeatingTriggerContributor]? = nil
    ) -> LogicalNotificationRequest {
        LogicalNotificationRequest(
            identifier: try! NotificationIdentifierCodec().repeatingIdentifier(
                reminderID: reminderID,
                components: components
            ),
            reminderID: reminderID,
            payload: .repeating(
                components: components,
                contributors: contributors ?? [
                    RepeatingTriggerContributor(kind: .main, sourceComponents: components)
                ]
            ),
            contributingGroupIDs: [AlertGroupID(
                reminderID: reminderID,
                baseOccurrenceInstant: contributingBaseInstant
            )]
        )
    }

    private func occurrence(_ instant: String, month: Int = 8, day: Int) -> BaseOccurrence {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "America/New_York")!
        components.year = 2040
        components.month = month
        components.day = day
        components.hour = 9
        components.minute = 30
        components.second = 0
        let resolvedInstant = date(instant)
        components.weekday = components.calendar?.component(.weekday, from: resolvedInstant)
        return BaseOccurrence(instant: resolvedInstant, sourceComponents: components)
    }

    private func testMaterializer() -> NotificationRequestMaterializer {
        NotificationRequestMaterializer(triggerDateVerifier: { _, _ in true })
    }

    private func calendarTrigger(_ request: UNNotificationRequest) -> UNCalendarNotificationTrigger {
        guard let trigger = request.trigger as? UNCalendarNotificationTrigger else {
            Issue.record("Expected UNCalendarNotificationTrigger")
            preconditionFailure("Expected UNCalendarNotificationTrigger")
        }
        return trigger
    }
}

private func date(_ value: String) -> Date {
    guard let value = ISO8601DateFormatter().date(from: value) else {
        preconditionFailure("Invalid date fixture")
    }
    return value
}

private extension MaterializationInput {
    init(reminder: ReminderSnapshot, locale: Locale) {
        self.init(
            reminder: reminder,
            locale: locale,
            evaluationNow: date("2040-08-31T13:30:00Z"),
            recurrenceEnvironment: .foundation
        )
    }
}

private final class FailAfterFirstTimeZoneLookupEnvironment: RecurrenceEnvironment, @unchecked Sendable {
    private let lock = NSLock()
    private var lookupCount = 0

    func timeZone(identifier: String) -> TimeZone? {
        lock.lock()
        lookupCount += 1
        let shouldResolve = lookupCount == 1
        lock.unlock()
        return shouldResolve ? TimeZone(identifier: identifier) : nil
    }

    func gregorianCalendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
