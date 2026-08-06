import Foundation
import Testing
import UserNotifications
import NotificationManagerDomain
import NotificationManager

struct NotificationRequestMaterializerTests {
    @Test func localeChangesOnlyLocalizedContent() throws {
        let logical = try oneShotRequest()
        let materializer = NotificationRequestMaterializer()

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
        let instant = date("2026-08-07T13:30:45Z")
        let request = try NotificationRequestMaterializer().materialize(
            oneShotRequest(alertInstant: instant),
            input: MaterializationInput(reminder: reminder(), locale: Locale(identifier: "en_US"))
        )
        let trigger = calendarTrigger(request)
        let components = trigger.dateComponents

        #expect(components.calendar?.identifier == .gregorian)
        #expect(components.timeZone?.identifier == "GMT")
        #expect(components.year == 2026)
        #expect(components.month == 8)
        #expect(components.day == 7)
        #expect(components.hour == 13)
        #expect(components.minute == 30)
        #expect(components.second == 45)
        #expect(trigger.repeats == false)
        #expect(trigger.nextTriggerDate() == instant)
    }

    @Test func repeatingUsesSourceIANAGregorianComponentsAndHasNextDate() throws {
        let components = RepeatingTriggerComponents(
            timeZoneIdentifier: "America/New_York",
            weekday: 2,
            hour: 9,
            minute: 30,
            second: 0
        )
        let request = try NotificationRequestMaterializer().materialize(
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
        #expect(actual.weekday == 2)
        #expect(actual.hour == 9)
        #expect(actual.minute == 30)
        #expect(actual.second == 0)
        #expect(trigger.repeats)
        #expect(trigger.nextTriggerDate() != nil)
    }

    @Test func identitySoundInterruptionAndRoutingFollowCurrentReminder() throws {
        let logical = try oneShotRequest()
        let reminderWithURL = reminder(urlString: "https://example.com/current")
        let withURL = try NotificationRequestMaterializer().materialize(
            logical,
            input: MaterializationInput(
                reminder: reminderWithURL,
                locale: Locale(identifier: "en_US")
            )
        )
        let withoutURL = try NotificationRequestMaterializer().materialize(
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
        let materializer = NotificationRequestMaterializer()

        let english = try materializer.materialize(
            logical,
            input: MaterializationInput(reminder: source, locale: Locale(identifier: "en_US"))
        ).content.body
        let japanese = try materializer.materialize(
            logical,
            input: MaterializationInput(reminder: source, locale: Locale(identifier: "ja_JP"))
        ).content.body

        #expect(english == "Every day.\nSource time: 09:30 (America/New_York).\nAt the scheduled time for August 7, 2026 at 09:30.")
        #expect(japanese == "毎日繰り返します。\n基準時刻: 09:30（America/New_York）。\n2026年8月7日09:30の予定時刻です。")
    }

    @Test func notesReplaceRecurrenceSummaryButKeepLocalizedSupplementalText() throws {
        let logical = try oneShotRequest()
        let materializer = NotificationRequestMaterializer()

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

        #expect(english == "Pack your passport.\nSource time: 09:30 (America/New_York).\nAt the scheduled time for August 7, 2026 at 09:30.")
        #expect(japanese == "パスポートを準備する。\n基準時刻: 09:30（America/New_York）。\n2026年8月7日09:30の予定時刻です。")
    }

    @Test func oneShotCollisionUsesMainThenConcreteSecondaryEarlyReasons() throws {
        let instant = date("2026-08-07T13:30:00Z")
        let nextBase = occurrence("2026-08-08T13:30:00Z", day: 8)
        let logical = try oneShotRequest(
            alertInstant: instant,
            reasons: [
                EffectiveAlert(kind: .early, baseOccurrence: nextBase, alertInstant: instant),
                EffectiveAlert(
                    kind: .main,
                    baseOccurrence: occurrence("2026-08-07T13:30:00Z", day: 7),
                    alertInstant: instant
                )
            ]
        )

        let english = try NotificationRequestMaterializer().materialize(
            logical,
            input: MaterializationInput(reminder: reminder(notes: "Trip."), locale: Locale(identifier: "en_US"))
        ).content.body
        let japanese = try NotificationRequestMaterializer().materialize(
            logical,
            input: MaterializationInput(reminder: reminder(notes: "旅行。"), locale: Locale(identifier: "ja_JP"))
        ).content.body

        #expect(english.hasSuffix("At the scheduled time for August 7, 2026 at 09:30. Also early for August 8, 2026 at 09:30."))
        #expect(japanese.hasSuffix("2026年8月7日09:30の予定時刻です。 さらに、2026年8月8日09:30の早期通知です。"))
    }

    @Test func repeatingContentIsStaticAcrossContributingOccurrenceDates() throws {
        let components = RepeatingTriggerComponents(
            timeZoneIdentifier: "America/New_York",
            hour: 9,
            minute: 30,
            second: 0
        )
        let first = repeatingRequest(
            components: components,
            contributingBaseInstant: date("2026-08-07T13:30:00Z"),
            contributors: [
                RepeatingTriggerContributor(kind: .main, sourceComponents: components),
                RepeatingTriggerContributor(kind: .early, sourceComponents: components)
            ]
        )
        let second = repeatingRequest(
            components: components,
            contributingBaseInstant: date("2032-12-30T14:30:00Z"),
            contributors: [
                RepeatingTriggerContributor(kind: .main, sourceComponents: components),
                RepeatingTriggerContributor(kind: .early, sourceComponents: components)
            ]
        )
        let input = MaterializationInput(reminder: reminder(notes: nil), locale: Locale(identifier: "en_US"))

        let firstBody = try NotificationRequestMaterializer().materialize(first, input: input).content.body
        let secondBody = try NotificationRequestMaterializer().materialize(second, input: input).content.body

        #expect(firstBody == secondBody)
        #expect(firstBody == "Every day.\nSource time: 09:30 (America/New_York).\nAt the scheduled time. Also early for the next occurrence.")
        #expect(!firstBody.contains("2026"))
        #expect(!firstBody.contains("2032"))
    }

    @Test func titleAndFinalBodyAreTruncatedWithoutMutatingPersistedStrings() throws {
        let originalTitle = String(repeating: "a", count: 300)
        let originalNotes = String(repeating: "👨‍👩‍👧‍👦", count: 300)
        let original = reminder(title: originalTitle, notes: originalNotes)

        let content = try NotificationRequestMaterializer().materialize(
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
            try NotificationRequestMaterializer().materialize(
                validOneShot,
                input: MaterializationInput(reminder: differentReminder, locale: Locale(identifier: "en_US"))
            )
        }

        #expect(throws: NotificationRequestMaterializationError.invalidSchedule) {
            try NotificationRequestMaterializer().materialize(
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
            try NotificationRequestMaterializer().materialize(
                wrongIdentifier,
                input: MaterializationInput(reminder: reminder(), locale: Locale(identifier: "en_US"))
            )
        }

        let fractionalInstant = Date(timeIntervalSince1970: 1.5)
        #expect(throws: NotificationRequestMaterializationError.invalidOneShotAlertInstant) {
            try NotificationRequestMaterializer().materialize(
                LogicalNotificationRequest(
                    identifier: "notification-manager.local.v1.o.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.1",
                    reminderID: reminderID,
                    payload: .oneShot(alertInstant: fractionalInstant, reasons: [
                        EffectiveAlert(
                            kind: .main,
                            baseOccurrence: occurrence("2026-08-07T13:30:00Z", day: 7),
                            alertInstant: fractionalInstant
                        )
                    ]),
                    contributingGroupIDs: [AlertGroupID(
                        reminderID: reminderID,
                        baseOccurrenceInstant: date("2026-08-07T13:30:00Z")
                    )]
                ),
                input: MaterializationInput(reminder: reminder(), locale: Locale(identifier: "en_US"))
            )
        }

        let emptyReasons = LogicalNotificationRequest(
            identifier: validOneShot.identifier,
            reminderID: reminderID,
            payload: .oneShot(alertInstant: date("2026-08-07T13:30:00Z"), reasons: []),
            contributingGroupIDs: validOneShot.contributingGroupIDs
        )
        #expect(throws: NotificationRequestMaterializationError.invalidOneShotReasons) {
            try NotificationRequestMaterializer().materialize(
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
            try NotificationRequestMaterializer().materialize(
                LogicalNotificationRequest(
                    identifier: "notification-manager.local.v1.r.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa." + String(repeating: "0", count: 64),
                    reminderID: reminderID,
                    payload: .repeating(components: invalidComponents, contributors: []),
                    contributingGroupIDs: [AlertGroupID(
                        reminderID: reminderID,
                        baseOccurrenceInstant: date("2026-08-07T13:30:00Z")
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
                baseOccurrenceInstant: date("2026-08-07T13:30:00Z")
            )]
        )
        #expect(throws: NotificationRequestMaterializationError.invalidRepeatingContributors) {
            try NotificationRequestMaterializer().materialize(
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
            try NotificationRequestMaterializer().materialize(
                noGroups,
                input: MaterializationInput(reminder: reminder(), locale: Locale(identifier: "en_US"))
            )
        }
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
                    year: 2026,
                    month: 8,
                    day: 7,
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
            createdAt: date("2026-08-01T00:00:00Z"),
            updatedAt: date("2026-08-01T00:00:00Z")
        )
    }

    private func oneShotRequest(
        alertInstant: Date = date("2026-08-07T13:30:00Z"),
        reasons: [EffectiveAlert]? = nil
    ) throws -> LogicalNotificationRequest {
        let resolvedReasons = reasons ?? [
            EffectiveAlert(
                kind: .main,
                baseOccurrence: occurrence("2026-08-07T13:30:00Z", day: 7),
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
            contributingGroupIDs: [AlertGroupID(
                reminderID: reminderID,
                baseOccurrenceInstant: date("2026-08-07T13:30:00Z")
            )]
        )
    }

    private func repeatingRequest(
        components: RepeatingTriggerComponents,
        contributingBaseInstant: Date = date("2026-08-07T13:30:00Z"),
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

    private func occurrence(_ instant: String, day: Int) -> BaseOccurrence {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "America/New_York")!
        components.year = 2026
        components.month = 8
        components.day = day
        components.hour = 9
        components.minute = 30
        components.second = 0
        return BaseOccurrence(instant: date(instant), sourceComponents: components)
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
