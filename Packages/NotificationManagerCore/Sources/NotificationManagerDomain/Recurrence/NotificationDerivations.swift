import Foundation

public enum AlertKind: Sendable, Equatable {
    case main
    case early
}

public struct EffectiveAlert: Sendable, Equatable {
    public let kind: AlertKind
    public let baseOccurrence: BaseOccurrence
    public let alertInstant: Date

    public init(kind: AlertKind, baseOccurrence: BaseOccurrence, alertInstant: Date) {
        self.kind = kind
        self.baseOccurrence = baseOccurrence
        self.alertInstant = alertInstant
    }
}

public struct AlertGroup: Sendable, Equatable {
    public let baseOccurrence: BaseOccurrence
    public let alerts: [EffectiveAlert]

    public init(baseOccurrence: BaseOccurrence, alerts: [EffectiveAlert]) {
        self.baseOccurrence = baseOccurrence
        self.alerts = alerts
    }
}

public enum NotificationDerivationError: Error, Sendable, Equatable {
    case arithmeticOverflow
}

public struct AlertGroupCursor {
    private var baseOccurrences: AnyIterator<BaseOccurrence>
    private let schedule: ScheduleDefinition
    private let calendar: Calendar

    init(
        baseOccurrences: AnyIterator<BaseOccurrence>,
        schedule: ScheduleDefinition,
        calendar: Calendar
    ) {
        self.baseOccurrences = baseOccurrences
        self.schedule = schedule
        self.calendar = calendar
    }

    public mutating func next() throws -> AlertGroup? {
        guard let occurrence = baseOccurrences.next() else { return nil }

        var alerts: [EffectiveAlert] = []
        if let early = schedule.early {
            let instant = try earlyAlertInstant(
                for: occurrence.instant,
                early: early,
                rule: schedule.rule,
                calendar: calendar
            )
            alerts.append(
                EffectiveAlert(
                    kind: .early,
                    baseOccurrence: occurrence,
                    alertInstant: instant
                ))
        }
        if schedule.early?.mainEnabled != false {
            alerts.append(
                EffectiveAlert(
                    kind: .main,
                    baseOccurrence: occurrence,
                    alertInstant: occurrence.instant
                ))
        }
        return AlertGroup(baseOccurrence: occurrence, alerts: alerts)
    }
}

func earlyAlertInstant(
    for baseInstant: Date,
    early: EarlyReminder,
    rule: RepeatRule,
    calendar: Calendar
) throws -> Date {
    if usesCalendarOffset(early.unit, rule: rule) {
        let component: Calendar.Component =
            switch early.unit {
            case .days: .day
            case .weeks: .weekOfYear
            case .minutes, .hours:
                preconditionFailure("Fixed-duration unit reached calendar offset")
            }
        guard
            let result = calendar.date(
                byAdding: component,
                value: -early.value,
                to: baseInstant
            )
        else {
            throw NotificationDerivationError.arithmeticOverflow
        }
        return result
    }

    let secondsPerUnit: Int64 =
        switch early.unit {
        case .minutes: 60
        case .hours: 3_600
        case .days: 86_400
        case .weeks: 604_800
        }
    let (seconds, overflow) = Int64(early.value).multipliedReportingOverflow(
        by: secondsPerUnit
    )
    guard !overflow else { throw NotificationDerivationError.arithmeticOverflow }
    let result = baseInstant.addingTimeInterval(-Double(seconds))
    guard result.timeIntervalSinceReferenceDate.isFinite else {
        throw NotificationDerivationError.arithmeticOverflow
    }
    return result
}

private func usesCalendarOffset(_ unit: EarlyReminderUnit, rule: RepeatRule) -> Bool {
    switch (unit, rule) {
    case (.days, .hourly), (.weeks, .hourly):
        false
    case (.days, _), (.weeks, _):
        true
    case (.minutes, _), (.hours, _):
        false
    }
}

public struct PhysicalNotification: Sendable, Equatable {
    public let reminderID: UUID
    public let alertInstant: Date
    public let primaryReason: EffectiveAlert
    public let reasons: [EffectiveAlert]
    public let contributingBaseOccurrences: [BaseOccurrence]

    public init(reminderID: UUID, alertInstant: Date, reasons: [EffectiveAlert]) {
        precondition(!reasons.isEmpty, "A physical notification requires at least one reason")
        precondition(
            reasons.allSatisfy { $0.alertInstant == alertInstant },
            "All reasons must contribute to the physical notification instant"
        )

        let orderedReasons = reasons.enumerated().sorted { lhs, rhs in
            if lhs.element.kind != rhs.element.kind {
                return lhs.element.kind == .main
            }
            if lhs.element.baseOccurrence.instant != rhs.element.baseOccurrence.instant {
                return lhs.element.baseOccurrence.instant < rhs.element.baseOccurrence.instant
            }
            return lhs.offset < rhs.offset
        }.map(\.element)

        var occurrences: [BaseOccurrence] = []
        for reason in orderedReasons where !occurrences.contains(reason.baseOccurrence) {
            occurrences.append(reason.baseOccurrence)
        }

        self.reminderID = reminderID
        self.alertInstant = alertInstant
        primaryReason = orderedReasons[0]
        self.reasons = orderedReasons
        contributingBaseOccurrences = occurrences
    }
}
