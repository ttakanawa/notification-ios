import Foundation

public enum NotificationRequestValidationError: Error, Sendable, Equatable {
    case reminderIDMismatch
    case invalidSchedule
    case invalidContributingGroups
    case contributorIdentityMismatch
    case duplicateContributors
    case reasonKindNotAllowed
    case oneShotAlertNotDerivable
    case repeatingPayloadNotDerivable
}

public struct NotificationRequestValidationContext: Sendable {
    public let evaluationNow: Date
    public let recurrenceEnvironment: any RecurrenceEnvironment

    public init(
        evaluationNow: Date,
        recurrenceEnvironment: any RecurrenceEnvironment
    ) {
        self.evaluationNow = evaluationNow
        self.recurrenceEnvironment = recurrenceEnvironment
    }
}

public struct LogicalNotificationRequestValidator: Sendable {
    public init() {}

    public func validate(
        _ request: LogicalNotificationRequest,
        for reminder: ReminderSnapshot,
        context: NotificationRequestValidationContext
    ) throws {
        guard request.reminderID == reminder.id else {
            throw NotificationRequestValidationError.reminderIDMismatch
        }
        guard case .valid(let schedule, _, _) = reminder.schedule else {
            throw NotificationRequestValidationError.invalidSchedule
        }
        guard !request.contributingGroupIDs.isEmpty,
            request.contributingGroupIDs.allSatisfy({
                $0.reminderID == request.reminderID
                    && isFiniteIntegralSecond($0.baseOccurrenceInstant)
            })
        else {
            throw NotificationRequestValidationError.invalidContributingGroups
        }

        switch request.payload {
        case .oneShot(let alertInstant, let reasons):
            try validateOneShot(
                alertInstant: alertInstant,
                reasons: reasons,
                groups: request.contributingGroupIDs,
                reminderID: request.reminderID,
                schedule: schedule,
                environment: context.recurrenceEnvironment
            )
        case .repeating(_, let contributors):
            try validateRepeating(
                request: request,
                contributors: contributors,
                groups: request.contributingGroupIDs,
                schedule: schedule,
                reminder: reminder,
                context: context
            )
        }
    }

    private func validateOneShot(
        alertInstant: Date,
        reasons: [EffectiveAlert],
        groups: Set<AlertGroupID>,
        reminderID: UUID,
        schedule: ScheduleDefinition,
        environment: any RecurrenceEnvironment
    ) throws {
        guard !reasons.isEmpty else {
            throw NotificationRequestValidationError.oneShotAlertNotDerivable
        }

        var identities: Set<ReasonIdentity> = []
        for reason in reasons {
            guard identities.insert(ReasonIdentity(reason)).inserted else {
                throw NotificationRequestValidationError.duplicateContributors
            }
        }

        let expectedGroups = Set(
            reasons.map {
                AlertGroupID(
                    reminderID: reminderID,
                    baseOccurrenceInstant: $0.baseOccurrence.instant
                )
            })
        guard groups == expectedGroups else {
            throw NotificationRequestValidationError.contributorIdentityMismatch
        }

        for reason in reasons {
            guard reason.alertInstant == alertInstant,
                kindIsAllowed(reason.kind, schedule: schedule)
            else {
                if reason.alertInstant == alertInstant {
                    throw NotificationRequestValidationError.reasonKindNotAllowed
                }
                throw NotificationRequestValidationError.oneShotAlertNotDerivable
            }
            guard
                try reasonIsDerivable(
                    reason,
                    schedule: schedule,
                    environment: environment
                )
            else {
                throw NotificationRequestValidationError.oneShotAlertNotDerivable
            }
        }
    }

    private func validateRepeating(
        request: LogicalNotificationRequest,
        contributors: [RepeatingTriggerContributor],
        groups: Set<AlertGroupID>,
        schedule: ScheduleDefinition,
        reminder: ReminderSnapshot,
        context: NotificationRequestValidationContext
    ) throws {
        var identities: Set<RepeatingContributorIdentity> = []
        for contributor in contributors {
            guard identities.insert(RepeatingContributorIdentity(contributor)).inserted else {
                throw NotificationRequestValidationError.duplicateContributors
            }
        }
        guard groups.count == 1,
            let group = groups.first,
            try isBaseOccurrence(
                group.baseOccurrenceInstant,
                of: schedule,
                environment: context.recurrenceEnvironment
            )
        else {
            throw NotificationRequestValidationError.contributorIdentityMismatch
        }

        let plan = try LogicalNotificationPlanner().plan(
            PlannerInput(
                snapshot: CompleteReminderSnapshot(reminders: [reminder], tags: []),
                evaluationNow: context.evaluationNow,
                deviceNotificationsEnabled: true,
                authorizationAllowsScheduling: true,
                capacity: 60,
                recurrenceEnvironment: context.recurrenceEnvironment
            ))
        guard plan.requests.contains(request) else {
            throw NotificationRequestValidationError.repeatingPayloadNotDerivable
        }
    }

    private func reasonIsDerivable(
        _ reason: EffectiveAlert,
        schedule: ScheduleDefinition,
        environment: any RecurrenceEnvironment
    ) throws -> Bool {
        guard isFiniteIntegralSecond(reason.alertInstant),
            let derived = try baseOccurrence(
                at: reason.baseOccurrence.instant,
                of: schedule,
                environment: environment
            ),
            sourceComponentsMatch(
                reason.baseOccurrence.sourceComponents,
                derived.sourceComponents
            )
        else {
            return false
        }
        switch reason.kind {
        case .main:
            return reason.alertInstant == reason.baseOccurrence.instant
        case .early:
            guard let early = schedule.early,
                let timeZone = environment.timeZone(
                    identifier: schedule.source.timeZoneIdentifier
                )
            else {
                return false
            }
            let calendar = environment.gregorianCalendar(in: timeZone)
            return try earlyAlertInstant(
                for: reason.baseOccurrence.instant,
                early: early,
                rule: schedule.rule,
                calendar: calendar
            ) == reason.alertInstant
        }
    }

    private func isBaseOccurrence(
        _ instant: Date,
        of schedule: ScheduleDefinition,
        environment: any RecurrenceEnvironment
    ) throws -> Bool {
        try baseOccurrence(
            at: instant,
            of: schedule,
            environment: environment
        ) != nil
    }

    private func baseOccurrence(
        at instant: Date,
        of schedule: ScheduleDefinition,
        environment: any RecurrenceEnvironment
    ) throws -> BaseOccurrence? {
        guard isFiniteIntegralSecond(instant),
            let upperBound = Calendar(identifier: .gregorian).date(
                byAdding: .second,
                value: 1,
                to: instant
            )
        else {
            return nil
        }
        let occurrences = try FoundationRecurrenceEngine().baseOccurrences(
            for: schedule,
            in: instant..<upperBound,
            environment: environment
        )
        let iterator = occurrences.makeIterator()
        guard let occurrence = iterator.next(), occurrence.instant == instant else {
            return nil
        }
        return occurrence
    }

    private func sourceComponentsMatch(
        _ supplied: DateComponents,
        _ derived: DateComponents
    ) -> Bool {
        supplied.calendar?.identifier == .gregorian
            && supplied.timeZone?.identifier == derived.timeZone?.identifier
            && supplied.year == derived.year
            && supplied.month == derived.month
            && supplied.day == derived.day
            && supplied.hour == derived.hour
            && supplied.minute == derived.minute
            && supplied.second == derived.second
            && supplied.weekday == derived.weekday
    }

    private func kindIsAllowed(
        _ kind: AlertKind,
        schedule: ScheduleDefinition
    ) -> Bool {
        switch kind {
        case .main:
            schedule.early?.mainEnabled != false
        case .early:
            schedule.early != nil
        }
    }

    private func isFiniteIntegralSecond(_ date: Date) -> Bool {
        let seconds = date.timeIntervalSince1970
        return seconds.isFinite && seconds.rounded(.towardZero) == seconds
    }
}

private struct ReasonIdentity: Hashable {
    let kind: Int
    let baseInstant: Date
    let alertInstant: Date

    init(_ reason: EffectiveAlert) {
        kind = reason.kind == .main ? 0 : 1
        baseInstant = reason.baseOccurrence.instant
        alertInstant = reason.alertInstant
    }
}

private struct RepeatingContributorIdentity: Hashable {
    let kind: Int
    let components: RepeatingComponentsIdentity

    init(_ contributor: RepeatingTriggerContributor) {
        kind = contributor.kind == .main ? 0 : 1
        components = RepeatingComponentsIdentity(contributor.sourceComponents)
    }
}

private struct RepeatingComponentsIdentity: Hashable {
    let timeZoneIdentifier: String
    let month: Int?
    let day: Int?
    let weekday: Int?
    let hour: Int
    let minute: Int
    let second: Int

    init(_ components: RepeatingTriggerComponents) {
        timeZoneIdentifier = components.timeZoneIdentifier
        month = components.month
        day = components.day
        weekday = components.weekday
        hour = components.hour
        minute = components.minute
        second = components.second
    }
}
