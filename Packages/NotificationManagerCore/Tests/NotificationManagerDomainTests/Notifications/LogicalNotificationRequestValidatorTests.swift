import Foundation
import Testing

@testable import NotificationManagerDomain

@Suite("Notifications.LogicalNotificationRequestValidator")
struct LogicalNotificationRequestValidatorTests {
    @Test func rejectsMismatchedReminderIDForOneShotAndRepeatingRequests() throws {
        let source = repeatingComponents(hour: 9, minute: 30)
        let requests = [
            oneShotRequest(),
            repeatingRequest(
                components: source,
                contributors: [
                    RepeatingTriggerContributor(
                        kind: .main,
                        sourceComponents: source
                    )
                ]
            )
        ]
        let differentReminder = reminder(
            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        )

        for request in requests {
            #expect(throws: NotificationRequestValidationError.reminderIDMismatch) {
                try validator.validate(request, for: differentReminder)
            }
        }
    }

    @Test func rejectsInvalidScheduleStatesForOneShotAndRepeatingRequests() throws {
        let source = repeatingComponents(hour: 9, minute: 30)
        let requests = [
            oneShotRequest(),
            repeatingRequest(
                components: source,
                contributors: [
                    RepeatingTriggerContributor(
                        kind: .main,
                        sourceComponents: source
                    )
                ]
            )
        ]
        let invalidSchedules: [ScheduleReadState] = [
            .unsupportedFuture(version: 3, originalData: Data([3])),
            .corrupt(originalData: Data([0])),
            .domainInvalid(
                repairSeed: ScheduleRepairSeed(),
                originalData: Data([1]),
                issues: [.invalidTimeZone]
            )
        ]

        for request in requests {
            for invalidSchedule in invalidSchedules {
                #expect(throws: NotificationRequestValidationError.invalidSchedule) {
                    try validator.validate(
                        request,
                        for: reminder(schedule: invalidSchedule)
                    )
                }
            }
        }
    }

    @Test func acceptsExactOneShotReasonAndContributorIdentities() throws {
        try validator.validate(oneShotRequest(), for: schedule())

        let collisionSchedule = schedule(early: EarlyReminder(value: 1, unit: .days))
        let first = baseOccurrence("2040-08-31T13:30:00Z", day: 31)
        let second = baseOccurrence("2040-09-01T13:30:00Z", month: 9, day: 1)
        try validator.validate(
            oneShotRequest(
                reasons: [
                    EffectiveAlert(kind: .main, baseOccurrence: first, alertInstant: first.instant),
                    EffectiveAlert(
                        kind: .early, baseOccurrence: second, alertInstant: first.instant)
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
            #expect(throws: NotificationRequestValidationError.contributorIdentityMismatch) {
                try validator.validate(
                    oneShotRequest(reasons: [reason], groupInstants: groupInstants),
                    for: schedule()
                )
            }
        }
    }

    @Test func rejectsDuplicateOneShotReasons() throws {
        let reason = mainReason()
        #expect(throws: NotificationRequestValidationError.duplicateContributors) {
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
        #expect(throws: NotificationRequestValidationError.reasonKindNotAllowed) {
            try validator.validate(
                oneShotRequest(
                    alertInstant: early.alertInstant,
                    reasons: [early]
                ), for: schedule(early: nil))
        }

        #expect(throws: NotificationRequestValidationError.reasonKindNotAllowed) {
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
        #expect(throws: NotificationRequestValidationError.oneShotAlertNotDerivable) {
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
        #expect(throws: NotificationRequestValidationError.oneShotAlertNotDerivable) {
            try validator.validate(oneShotRequest(reasons: [forgedBaseReason]), for: schedule())
        }

        let base = baseOccurrence("2040-08-31T13:30:00Z", day: 31)
        let wrongAlert = EffectiveAlert(
            kind: .main,
            baseOccurrence: base,
            alertInstant: date("2040-08-31T13:31:00Z")
        )
        #expect(throws: NotificationRequestValidationError.oneShotAlertNotDerivable) {
            try validator.validate(
                oneShotRequest(
                    alertInstant: wrongAlert.alertInstant,
                    reasons: [wrongAlert]
                ), for: schedule())
        }
    }

    @Test func acceptsOnlyRepeatingCandidateStructurallyProducedByCurrentSchedule() throws {
        let source = repeatingComponents(hour: 9, minute: 30)
        try validator.validate(
            repeatingRequest(
                components: source,
                contributors: [RepeatingTriggerContributor(kind: .main, sourceComponents: source)]
            ), for: schedule())

        let earlySchedule = schedule(
            early: EarlyReminder(value: 5, unit: .minutes, mainEnabled: false)
        )
        let earlyTarget = repeatingComponents(hour: 9, minute: 25)
        try validator.validate(
            repeatingRequest(
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
                    contributors: [
                        RepeatingTriggerContributor(kind: .main, sourceComponents: source)
                    ]
                ),
                schedule()
            ),
            (
                repeatingRequest(
                    components: source,
                    contributors: [
                        RepeatingTriggerContributor(kind: .main, sourceComponents: wrongSource)
                    ]
                ),
                schedule()
            ),
            (
                repeatingRequest(
                    components: earlyTarget,
                    contributors: [
                        RepeatingTriggerContributor(kind: .early, sourceComponents: source)
                    ]
                ),
                schedule(early: nil)
            ),
            (
                repeatingRequest(
                    components: source,
                    contributors: [
                        RepeatingTriggerContributor(kind: .main, sourceComponents: source)
                    ]
                ),
                schedule(early: EarlyReminder(value: 5, unit: .minutes, mainEnabled: false))
            ),
            (
                repeatingRequest(
                    components: source,
                    contributors: [
                        RepeatingTriggerContributor(kind: .main, sourceComponents: source)
                    ],
                    groupInstants: [date("2040-09-02T13:30:00Z")]
                ),
                schedule(rule: .daily(interval: 2))
            )
        ]

        for (request, schedule) in fixtures {
            #expect(throws: NotificationRequestValidationError.repeatingPayloadNotDerivable) {
                try validator.validate(request, for: schedule)
            }
        }
    }

    @Test func rejectsDuplicateRepeatingContributorsAndUnrelatedFanOutGroups() throws {
        let source = repeatingComponents(hour: 9, minute: 30)
        let contributor = RepeatingTriggerContributor(kind: .main, sourceComponents: source)
        #expect(throws: NotificationRequestValidationError.duplicateContributors) {
            try validator.validate(
                repeatingRequest(
                    components: source,
                    contributors: [contributor, contributor]
                ), for: schedule())
        }

        #expect(throws: NotificationRequestValidationError.contributorIdentityMismatch) {
            try validator.validate(
                repeatingRequest(
                    components: source,
                    contributors: [contributor],
                    groupInstants: [
                        date("2040-08-31T13:30:00Z"),
                        date("2040-09-01T13:30:00Z")
                    ]
                ), for: schedule())
        }

        #expect(throws: NotificationRequestValidationError.contributorIdentityMismatch) {
            try validator.validate(
                repeatingRequest(
                    components: source,
                    contributors: [contributor],
                    groupInstants: [date("2040-08-31T13:31:00Z")]
                ), for: schedule())
        }
    }

    @Test func rejectsDirectRepeatingMainWhenEarlyPathCollidesAcrossOccurrences() throws {
        let definition = schedule(early: EarlyReminder(value: 1, unit: .days))
        let source = repeatingComponents(hour: 9, minute: 30)
        let forged = repeatingRequest(
            components: source,
            contributors: [
                RepeatingTriggerContributor(
                    kind: .main,
                    sourceComponents: source
                )
            ],
            groupInstants: [date("2040-09-01T13:30:00Z")]
        )

        #expect(throws: NotificationRequestValidationError.repeatingPayloadNotDerivable) {
            try validator.validate(forged, for: definition)
        }
    }

    @Test func rejectsDirectRepeatingEarlyWhoseResidueChangesAtTimeZoneTransition() throws {
        let definition = ScheduleDefinition(
            source: SourceWallClock(
                year: 2040,
                month: 8,
                day: 31,
                hour: 3,
                minute: 30,
                timeZoneIdentifier: "America/New_York"
            ),
            rule: .daily(interval: 1),
            end: .never,
            early: EarlyReminder(value: 2, unit: .hours, mainEnabled: false)
        )
        let source = RepeatingTriggerComponents(
            timeZoneIdentifier: "America/New_York",
            hour: 3,
            minute: 30,
            second: 0
        )
        let forged = repeatingRequest(
            components: RepeatingTriggerComponents(
                timeZoneIdentifier: "America/New_York",
                hour: 1,
                minute: 30,
                second: 0
            ),
            contributors: [
                RepeatingTriggerContributor(
                    kind: .early,
                    sourceComponents: source
                )
            ],
            groupInstants: [date("2040-09-01T07:30:00Z")]
        )

        #expect(throws: NotificationRequestValidationError.repeatingPayloadNotDerivable) {
            try validator.validate(forged, for: definition)
        }
    }

    @Test func acceptsExactMemberOfValidMultiCandidateCollection() throws {
        let definition = weeklyFridaySaturdaySchedule()
        let saturday = repeatingComponents(weekday: 7, hour: 9, minute: 30)

        try validator.validate(
            repeatingRequest(
                components: saturday,
                contributors: [
                    RepeatingTriggerContributor(
                        kind: .main,
                        sourceComponents: saturday
                    )
                ],
                groupInstants: [date("2040-09-01T13:30:00Z")]
            ), for: definition)
    }

    @Test func rejectsCandidateWithMismatchedBaselineFromValidMultiCandidateCollection() throws {
        let definition = weeklyFridaySaturdaySchedule()
        let saturday = repeatingComponents(weekday: 7, hour: 9, minute: 30)
        let wrongBaseline = repeatingRequest(
            components: saturday,
            contributors: [
                RepeatingTriggerContributor(
                    kind: .main,
                    sourceComponents: saturday
                )
            ],
            groupInstants: [date("2040-09-07T13:30:00Z")]
        )

        #expect(throws: NotificationRequestValidationError.repeatingPayloadNotDerivable) {
            try validator.validate(wrongBaseline, for: definition)
        }
    }

    @Test func propagatesInvalidEvaluationNowFromRepeatingPlanning() throws {
        let source = repeatingComponents(hour: 9, minute: 30)
        let request = repeatingRequest(
            components: source,
            contributors: [
                RepeatingTriggerContributor(
                    kind: .main,
                    sourceComponents: source
                )
            ]
        )
        let invalidContext = FixedValidationHarness(
            evaluationNow: Date(timeIntervalSinceReferenceDate: .infinity)
        )

        #expect(throws: LogicalNotificationPlannerError.invalidEvaluationNow) {
            try invalidContext.validate(request, for: schedule())
        }
    }

    @Test func propagatesMissingTimeZoneFromRepeatingPlanning() throws {
        let source = repeatingComponents(hour: 9, minute: 30)
        let request = repeatingRequest(
            components: source,
            contributors: [
                RepeatingTriggerContributor(
                    kind: .main,
                    sourceComponents: source
                )
            ]
        )
        let failingContext = FixedValidationHarness(
            evaluationNow: date("2040-08-31T13:30:00Z"),
            recurrenceEnvironment: FailAfterFirstTimeZoneLookupEnvironment()
        )

        #expect(throws: SourceWallClockResolutionError.unknownTimeZone) {
            try failingContext.validate(request, for: schedule())
        }
    }

    private let validator = FixedValidationHarness(
        evaluationNow: date("2040-08-31T13:30:00Z")
    )
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

    private func weeklyFridaySaturdaySchedule() -> ScheduleDefinition {
        schedule(
            rule: .weekly(
                interval: 1,
                weekdaySetKind: .explicit,
                weekdays: [.friday, .saturday]
            ))
    }

    private func reminder(
        id: UUID? = nil,
        schedule scheduleState: ScheduleReadState? = nil
    ) -> ReminderSnapshot {
        ReminderSnapshot(
            id: id ?? reminderID,
            title: "Validation fixture",
            notes: nil,
            urlString: nil,
            enabled: true,
            schedule: scheduleState
                ?? .valid(
                    schedule(),
                    sourceVersion: 1,
                    originalData: Data([1])
                ),
            tagIDs: [],
            createdAt: date("2040-08-31T13:30:00Z"),
            updatedAt: date("2040-08-31T13:30:00Z")
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
        guard
            let identifier = try? NotificationIdentifierCodec().oneShotIdentifier(
                reminderID: reminderID,
                alertInstant: alertInstant
            )
        else {
            preconditionFailure("Valid one-shot request fixture must produce an identifier")
        }
        return LogicalNotificationRequest(
            identifier: identifier,
            reminderID: reminderID,
            payload: .oneShot(alertInstant: alertInstant, reasons: resolvedReasons),
            contributingGroupIDs: Set(
                resolvedGroups.map {
                    AlertGroupID(reminderID: reminderID, baseOccurrenceInstant: $0)
                })
        )
    }

    private func repeatingRequest(
        components: RepeatingTriggerComponents,
        contributors: [RepeatingTriggerContributor],
        groupInstants: [Date] = [date("2040-09-01T13:30:00Z")]
    ) -> LogicalNotificationRequest {
        guard
            let identifier = try? NotificationIdentifierCodec().repeatingIdentifier(
                reminderID: reminderID,
                components: components
            )
        else {
            preconditionFailure("Valid repeating request fixture must produce an identifier")
        }
        return LogicalNotificationRequest(
            identifier: identifier,
            reminderID: reminderID,
            payload: .repeating(components: components, contributors: contributors),
            contributingGroupIDs: Set(
                groupInstants.map {
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

private struct FixedValidationHarness {
    let evaluationNow: Date
    let recurrenceEnvironment: any RecurrenceEnvironment

    init(
        evaluationNow: Date,
        recurrenceEnvironment: any RecurrenceEnvironment = FoundationRecurrenceEnvironment()
    ) {
        self.evaluationNow = evaluationNow
        self.recurrenceEnvironment = recurrenceEnvironment
    }

    func validate(
        _ request: LogicalNotificationRequest,
        for schedule: ScheduleDefinition
    ) throws {
        let reminder = ReminderSnapshot(
            id: request.reminderID,
            title: "Validation fixture",
            notes: nil,
            urlString: nil,
            enabled: true,
            schedule: .valid(schedule, sourceVersion: 1, originalData: Data([1])),
            tagIDs: [],
            createdAt: evaluationNow,
            updatedAt: evaluationNow
        )
        try LogicalNotificationRequestValidator().validate(
            request,
            for: reminder,
            context: NotificationRequestValidationContext(
                evaluationNow: evaluationNow,
                recurrenceEnvironment: recurrenceEnvironment
            )
        )
    }

    func validate(
        _ request: LogicalNotificationRequest,
        for reminder: ReminderSnapshot
    ) throws {
        try LogicalNotificationRequestValidator().validate(
            request,
            for: reminder,
            context: NotificationRequestValidationContext(
                evaluationNow: evaluationNow,
                recurrenceEnvironment: recurrenceEnvironment
            )
        )
    }
}

private final class FailAfterFirstTimeZoneLookupEnvironment: RecurrenceEnvironment,
    @unchecked Sendable
{
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

private func date(_ value: String) -> Date {
    guard let result = ISO8601DateFormatter().date(from: value) else {
        preconditionFailure("Invalid fixture date")
    }
    return result
}
