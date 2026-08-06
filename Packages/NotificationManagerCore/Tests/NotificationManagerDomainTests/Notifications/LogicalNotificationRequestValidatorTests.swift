import Foundation
import Testing
@testable import NotificationManagerDomain

@Suite("Notifications.LogicalNotificationRequestValidator")
struct LogicalNotificationRequestValidatorTests {
    @Test func acceptsExactOneShotReasonAndContributorIdentities() throws {
        try validator.validate(oneShotRequest(), for: schedule())

        let collisionSchedule = schedule(early: EarlyReminder(value: 1, unit: .days))
        let first = baseOccurrence("2040-08-31T13:30:00Z", day: 31)
        let second = baseOccurrence("2040-09-01T13:30:00Z", month: 9, day: 1)
        try validator.validate(
            oneShotRequest(
                reasons: [
                    EffectiveAlert(kind: .main, baseOccurrence: first, alertInstant: first.instant),
                    EffectiveAlert(kind: .early, baseOccurrence: second, alertInstant: first.instant)
                ],
                groupInstants: [first.instant, second.instant]
            ),
            for: collisionSchedule
        )
    }

    @Test func rejectsMissingExtraAndUnrelatedOneShotContributorGroups() throws {
        let reason = mainReason()
        let variants: [[Date]] = [
            [reason.baseOccurrence.instant, date("2040-09-01T13:30:00Z")],
            [date("2040-09-01T13:30:00Z")]
        ]

        for groupInstants in variants {
            #expect(throws: LogicalNotificationRequestValidationError.contributorIdentityMismatch) {
                try validator.validate(
                    oneShotRequest(reasons: [reason], groupInstants: groupInstants),
                    for: schedule()
                )
            }
        }
    }

    @Test func rejectsDuplicateOneShotReasons() throws {
        let reason = mainReason()
        #expect(throws: LogicalNotificationRequestValidationError.duplicateContributors) {
            try validator.validate(
                oneShotRequest(reasons: [reason, reason]),
                for: schedule()
            )
        }
    }

    @Test func rejectsReasonKindsDisallowedByCurrentEarlyPolicy() throws {
        let base = baseOccurrence("2040-08-31T13:30:00Z", day: 31)
        let early = EffectiveAlert(
            kind: .early,
            baseOccurrence: base,
            alertInstant: date("2040-08-31T13:25:00Z")
        )
        #expect(throws: LogicalNotificationRequestValidationError.reasonKindNotAllowed) {
            try validator.validate(oneShotRequest(
                alertInstant: early.alertInstant,
                reasons: [early]
            ), for: schedule(early: nil))
        }

        #expect(throws: LogicalNotificationRequestValidationError.reasonKindNotAllowed) {
            try validator.validate(
                oneShotRequest(reasons: [mainReason()]),
                for: schedule(early: EarlyReminder(value: 5, unit: .minutes, mainEnabled: false))
            )
        }
    }

    @Test func rejectsOneShotReasonWhoseOccurrenceOrAlertIsNotDerivable() throws {
        let wrongOccurrence = baseOccurrence("2040-08-31T13:31:00Z", day: 31, minute: 31)
        let wrongBaseReason = EffectiveAlert(
            kind: .main,
            baseOccurrence: wrongOccurrence,
            alertInstant: wrongOccurrence.instant
        )
        #expect(throws: LogicalNotificationRequestValidationError.oneShotAlertNotDerivable) {
            try validator.validate(oneShotRequest(reasons: [wrongBaseReason]), for: schedule())
        }

        let forgedComponents = baseOccurrence(
            "2040-08-31T13:30:00Z",
            day: 31,
            minute: 31
        )
        let forgedBaseReason = EffectiveAlert(
            kind: .main,
            baseOccurrence: forgedComponents,
            alertInstant: forgedComponents.instant
        )
        #expect(throws: LogicalNotificationRequestValidationError.oneShotAlertNotDerivable) {
            try validator.validate(oneShotRequest(reasons: [forgedBaseReason]), for: schedule())
        }

        let base = baseOccurrence("2040-08-31T13:30:00Z", day: 31)
        let wrongAlert = EffectiveAlert(
            kind: .main,
            baseOccurrence: base,
            alertInstant: date("2040-08-31T13:31:00Z")
        )
        #expect(throws: LogicalNotificationRequestValidationError.oneShotAlertNotDerivable) {
            try validator.validate(oneShotRequest(
                alertInstant: wrongAlert.alertInstant,
                reasons: [wrongAlert]
            ), for: schedule())
        }
    }

    @Test func acceptsOnlyRepeatingCandidateStructurallyProducedByCurrentSchedule() throws {
        let source = repeatingComponents(hour: 9, minute: 30)
        try validator.validate(repeatingRequest(
            components: source,
            contributors: [RepeatingTriggerContributor(kind: .main, sourceComponents: source)]
        ), for: schedule())

        let earlySchedule = schedule(
            early: EarlyReminder(value: 5, unit: .minutes, mainEnabled: false)
        )
        let earlyTarget = repeatingComponents(hour: 9, minute: 25)
        try validator.validate(repeatingRequest(
            components: earlyTarget,
            contributors: [RepeatingTriggerContributor(kind: .early, sourceComponents: source)]
        ), for: earlySchedule)
    }

    @Test func rejectsRepeatingTargetSourceKindAndRuleNotDerivableFromSchedule() throws {
        let source = repeatingComponents(hour: 9, minute: 30)
        let wrongTarget = repeatingComponents(hour: 10, minute: 30)
        let wrongSource = repeatingComponents(weekday: 2, hour: 9, minute: 30)
        let earlyTarget = repeatingComponents(hour: 9, minute: 25)
        let fixtures: [(LogicalNotificationRequest, ScheduleDefinition)] = [
            (
                repeatingRequest(
                    components: wrongTarget,
                    contributors: [RepeatingTriggerContributor(kind: .main, sourceComponents: source)]
                ),
                schedule()
            ),
            (
                repeatingRequest(
                    components: source,
                    contributors: [RepeatingTriggerContributor(kind: .main, sourceComponents: wrongSource)]
                ),
                schedule()
            ),
            (
                repeatingRequest(
                    components: earlyTarget,
                    contributors: [RepeatingTriggerContributor(kind: .early, sourceComponents: source)]
                ),
                schedule(early: nil)
            ),
            (
                repeatingRequest(
                    components: source,
                    contributors: [RepeatingTriggerContributor(kind: .main, sourceComponents: source)]
                ),
                schedule(early: EarlyReminder(value: 5, unit: .minutes, mainEnabled: false))
            ),
            (
                repeatingRequest(
                    components: source,
                    contributors: [RepeatingTriggerContributor(kind: .main, sourceComponents: source)]
                ),
                schedule(rule: .daily(interval: 2))
            )
        ]

        for (request, schedule) in fixtures {
            #expect(throws: LogicalNotificationRequestValidationError.repeatingPayloadNotDerivable) {
                try validator.validate(request, for: schedule)
            }
        }
    }

    @Test func rejectsDuplicateRepeatingContributorsAndUnrelatedFanOutGroups() throws {
        let source = repeatingComponents(hour: 9, minute: 30)
        let contributor = RepeatingTriggerContributor(kind: .main, sourceComponents: source)
        #expect(throws: LogicalNotificationRequestValidationError.duplicateContributors) {
            try validator.validate(repeatingRequest(
                components: source,
                contributors: [contributor, contributor]
            ), for: schedule())
        }

        #expect(throws: LogicalNotificationRequestValidationError.contributorIdentityMismatch) {
            try validator.validate(repeatingRequest(
                components: source,
                contributors: [contributor],
                groupInstants: [
                    date("2040-08-31T13:30:00Z"),
                    date("2040-09-01T13:30:00Z")
                ]
            ), for: schedule())
        }

        #expect(throws: LogicalNotificationRequestValidationError.contributorIdentityMismatch) {
            try validator.validate(repeatingRequest(
                components: source,
                contributors: [contributor],
                groupInstants: [date("2040-08-31T13:31:00Z")]
            ), for: schedule())
        }
    }

    private let validator = LogicalNotificationRequestValidator()
    private let reminderID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!

    private func schedule(
        rule: RepeatRule = .daily(interval: 1),
        early: EarlyReminder? = nil
    ) -> ScheduleDefinition {
        ScheduleDefinition(
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
    }

    private func mainReason() -> EffectiveAlert {
        let base = baseOccurrence("2040-08-31T13:30:00Z", day: 31)
        return EffectiveAlert(kind: .main, baseOccurrence: base, alertInstant: base.instant)
    }

    private func oneShotRequest(
        alertInstant: Date = date("2040-08-31T13:30:00Z"),
        reasons: [EffectiveAlert]? = nil,
        groupInstants: [Date]? = nil
    ) -> LogicalNotificationRequest {
        let resolvedReasons = reasons ?? [mainReason()]
        let resolvedGroups = groupInstants ?? resolvedReasons.map(\.baseOccurrence.instant)
        return LogicalNotificationRequest(
            identifier: try! NotificationIdentifierCodec().oneShotIdentifier(
                reminderID: reminderID,
                alertInstant: alertInstant
            ),
            reminderID: reminderID,
            payload: .oneShot(alertInstant: alertInstant, reasons: resolvedReasons),
            contributingGroupIDs: Set(resolvedGroups.map {
                AlertGroupID(reminderID: reminderID, baseOccurrenceInstant: $0)
            })
        )
    }

    private func repeatingRequest(
        components: RepeatingTriggerComponents,
        contributors: [RepeatingTriggerContributor],
        groupInstants: [Date] = [date("2040-08-31T13:30:00Z")]
    ) -> LogicalNotificationRequest {
        LogicalNotificationRequest(
            identifier: try! NotificationIdentifierCodec().repeatingIdentifier(
                reminderID: reminderID,
                components: components
            ),
            reminderID: reminderID,
            payload: .repeating(components: components, contributors: contributors),
            contributingGroupIDs: Set(groupInstants.map {
                AlertGroupID(reminderID: reminderID, baseOccurrenceInstant: $0)
            })
        )
    }

    private func repeatingComponents(
        weekday: Int? = nil,
        hour: Int,
        minute: Int
    ) -> RepeatingTriggerComponents {
        RepeatingTriggerComponents(
            timeZoneIdentifier: "America/New_York",
            weekday: weekday,
            hour: hour,
            minute: minute,
            second: 0
        )
    }

    private func baseOccurrence(
        _ instant: String,
        month: Int = 8,
        day: Int,
        minute: Int = 30
    ) -> BaseOccurrence {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "America/New_York")!
        components.year = 2040
        components.month = month
        components.day = day
        components.hour = 9
        components.minute = minute
        components.second = 0
        let resolvedInstant = date(instant)
        components.weekday = components.calendar?.component(.weekday, from: resolvedInstant)
        return BaseOccurrence(instant: resolvedInstant, sourceComponents: components)
    }
}

private func date(_ value: String) -> Date {
    guard let result = ISO8601DateFormatter().date(from: value) else {
        preconditionFailure("Invalid fixture date")
    }
    return result
}
