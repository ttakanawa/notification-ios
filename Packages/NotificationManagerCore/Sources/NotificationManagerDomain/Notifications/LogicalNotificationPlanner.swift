import Foundation

public struct PlannerInput: Sendable {
    public let snapshot: CompleteReminderSnapshot
    public let evaluationNow: Date
    public let deviceNotificationsEnabled: Bool
    public let authorizationAllowsScheduling: Bool
    public let capacity: Int
    public let recurrenceEnvironment: any RecurrenceEnvironment

    public init(
        snapshot: CompleteReminderSnapshot,
        evaluationNow: Date,
        deviceNotificationsEnabled: Bool,
        authorizationAllowsScheduling: Bool,
        capacity: Int,
        recurrenceEnvironment: any RecurrenceEnvironment
    ) {
        self.snapshot = snapshot
        self.evaluationNow = evaluationNow
        self.deviceNotificationsEnabled = deviceNotificationsEnabled
        self.authorizationAllowsScheduling = authorizationAllowsScheduling
        self.capacity = capacity
        self.recurrenceEnvironment = recurrenceEnvironment
    }
}

public enum LogicalNotificationPlannerError: Error, Sendable, Equatable {
    case invalidCapacity(Int)
    case invalidEvaluationNow
    case duplicateReminderID(UUID)
}

public struct AlertGroupID: Sendable, Equatable, Hashable {
    public let reminderID: UUID
    public let baseOccurrenceInstant: Date

    public init(reminderID: UUID, baseOccurrenceInstant: Date) {
        self.reminderID = reminderID
        self.baseOccurrenceInstant = baseOccurrenceInstant
    }
}

public enum AlertGroupSchedulingOutcome: Sendable, Equatable {
    case scheduled
    case unscheduledCapacity
    case unscheduledError
}

public enum LogicalNotificationPayload: Sendable, Equatable {
    case oneShot(alertInstant: Date, reasons: [EffectiveAlert])
    case repeating(
        components: RepeatingTriggerComponents,
        contributors: [RepeatingTriggerContributor]
    )
}

public struct LogicalNotificationRequest: Sendable, Equatable {
    public let identifier: String
    public let reminderID: UUID
    public let payload: LogicalNotificationPayload
    public let contributingGroupIDs: Set<AlertGroupID>

    public init(
        identifier: String,
        reminderID: UUID,
        payload: LogicalNotificationPayload,
        contributingGroupIDs: Set<AlertGroupID>
    ) {
        self.identifier = identifier
        self.reminderID = reminderID
        self.payload = payload
        self.contributingGroupIDs = contributingGroupIDs
    }

    public var isRepeating: Bool {
        if case .repeating = payload { return true }
        return false
    }

    public var oneShotAlertInstant: Date? {
        guard case .oneShot(let alertInstant, _) = payload else { return nil }
        return alertInstant
    }

    public var oneShotReasons: [EffectiveAlert] {
        guard case .oneShot(_, let reasons) = payload else { return [] }
        return reasons
    }
}

public struct LogicalPlan: Sendable, Equatable {
    public let requests: [LogicalNotificationRequest]
    public let outcomes: [AlertGroupID: AlertGroupSchedulingOutcome]
    public let selectedGroupIDs: [AlertGroupID]
    public let scheduledThrough: [UUID: Date]
    public let reminderStatuses: [UUID: ReminderStatus]

    public init(
        requests: [LogicalNotificationRequest],
        outcomes: [AlertGroupID: AlertGroupSchedulingOutcome],
        selectedGroupIDs: [AlertGroupID],
        scheduledThrough: [UUID: Date],
        reminderStatuses: [UUID: ReminderStatus]
    ) {
        self.requests = requests
        self.outcomes = outcomes
        self.selectedGroupIDs = selectedGroupIDs
        self.scheduledThrough = scheduledThrough
        self.reminderStatuses = reminderStatuses
    }
}

public struct LogicalNotificationPlanner: Sendable {
    private let dependencies: LogicalNotificationPlannerDependencies

    public init() {
        dependencies = .production
    }

    init(dependencies: LogicalNotificationPlannerDependencies) {
        self.dependencies = dependencies
    }

    public func plan(_ input: PlannerInput) throws -> LogicalPlan {
        guard (0...60).contains(input.capacity) else {
            throw LogicalNotificationPlannerError.invalidCapacity(input.capacity)
        }
        guard input.evaluationNow.timeIntervalSinceReferenceDate.isFinite else {
            throw LogicalNotificationPlannerError.invalidEvaluationNow
        }

        // Stage 1: classify the complete snapshot and exclude every non-active reminder.
        let classification = try classifyReminders(input)

        guard input.deviceNotificationsEnabled,
            input.authorizationAllowsScheduling
        else {
            return LogicalPlan(
                requests: [],
                outcomes: [:],
                selectedGroupIDs: [],
                scheduledThrough: [:],
                reminderStatuses: classification.statuses
            )
        }

        // Stage 2: obtain one earliest future group per active reminder.
        var states = try initialPlanningStates(
            classification.active,
            evaluationNow: input.evaluationNow,
            environment: input.recurrenceEnvironment
        )

        let baselineOrder = states.indices.sorted {
            groupPrecedes(states[$0].earliest, states[$1].earliest)
        }

        // Stage 3: allocate every baseline group atomically before any continuation.
        var allocation = allocateBaselines(
            states: states,
            order: baselineOrder,
            capacity: input.capacity
        )

        // Stage 4: replace a baseline with its complete repeating collection only
        // when the prospective collection fits as one atomic unit.
        let repeatingSelection = selectRepeatingReplacements(
            states: states,
            order: baselineOrder,
            allocation: allocation,
            input: input
        )

        // Stage 5: merge-sort rolling heads. Overflow retires only that reminder.
        let heads = initialContinuationHeads(
            states: &states,
            allocation: allocation,
            repeatingSelection: repeatingSelection
        )
        allocateContinuations(
            states: &states,
            initialHeads: heads,
            capacity: input.capacity,
            repeatingByReminder: repeatingSelection.byReminder,
            allocation: &allocation
        )

        // Stage 6: merge selected groups into the final locale-independent requests.
        let requests = try logicalRequests(
            selectedGroups: allocation.selectedGroups,
            repeatingByReminder: repeatingSelection.byReminder
        )
        let scheduledThrough = scheduledThrough(
            allocation.selectedGroups,
            repeatingByReminder: repeatingSelection.byReminder
        )

        return LogicalPlan(
            requests: requests,
            outcomes: allocation.outcomes,
            selectedGroupIDs: allocation.selectedGroupIDs,
            scheduledThrough: scheduledThrough,
            reminderStatuses: classification.statuses
        )
    }

    private func classifyReminders(_ input: PlannerInput) throws -> ReminderClassification {
        let reminders = try uniqueReminders(input.snapshot.reminders)
        var statuses: [UUID: ReminderStatus] = [:]
        var active: [(ReminderSnapshot, ScheduleDefinition)] = []
        for reminder in reminders {
            let status = try ReminderStatusCalculator().status(
                schedule: reminder.schedule,
                enabled: reminder.enabled,
                after: input.evaluationNow,
                environment: input.recurrenceEnvironment
            )
            statuses[reminder.id] = status
            guard status.primary == .active,
                case .valid(let schedule, _, _) = reminder.schedule
            else {
                continue
            }
            active.append((reminder, schedule))
        }
        return ReminderClassification(statuses: statuses, active: active)
    }

    private func initialPlanningStates(
        _ active: [(ReminderSnapshot, ScheduleDefinition)],
        evaluationNow: Date,
        environment: any RecurrenceEnvironment
    ) throws -> [ReminderPlanningState] {
        var states: [ReminderPlanningState] = []
        for (reminder, schedule) in active {
            var cursor = try FutureAlertGroupCursor(
                reminderID: reminder.id,
                schedule: schedule,
                evaluationNow: evaluationNow,
                environment: environment
            )
            guard let earliest = try cursor.next() else { continue }
            states.append(
                ReminderPlanningState(
                    reminder: reminder,
                    schedule: schedule,
                    cursor: cursor,
                    earliest: earliest
                ))
        }
        return states
    }

    private func allocateBaselines(
        states: [ReminderPlanningState],
        order: [Int],
        capacity: Int
    ) -> PlanningAllocation {
        var allocation = PlanningAllocation()
        for index in order {
            let group = states[index].earliest
            do {
                if try identifierCount(
                    for: allocation.selectedGroups + [group]
                ) <= capacity {
                    allocation.selectedGroups.append(group)
                    allocation.selectedGroupIDs.append(group.id)
                    allocation.outcomes[group.id] = .scheduled
                    allocation.baselineSelected.insert(group.id.reminderID)
                } else {
                    allocation.outcomes[group.id] = .unscheduledCapacity
                }
            } catch {
                allocation.outcomes[group.id] = .unscheduledError
            }
        }
        return allocation
    }

    private func selectRepeatingReplacements(
        states: [ReminderPlanningState],
        order: [Int],
        allocation: PlanningAllocation,
        input: PlannerInput
    ) -> RepeatingSelection {
        var selection = RepeatingSelection()
        for index in order {
            let state = states[index]
            let reminderID = state.reminder.id
            guard allocation.baselineSelected.contains(reminderID) else { continue }

            do {
                try dependencies.failureCheck(.repeatingReplacement, reminderID)
                let preview = try NextNotificationProvider().nextPhysicalNotifications(
                    for: reminderID,
                    schedule: state.schedule,
                    after: input.evaluationNow,
                    limit: 3,
                    environment: input.recurrenceEnvironment
                ).notifications
                guard
                    let candidates = RepeatingTriggerPlanner().plan(
                        RepeatingTriggerPlanningInput(
                            schedule: state.schedule,
                            evaluationNow: input.evaluationNow,
                            physicalNotifications: preview,
                            environment: input.recurrenceEnvironment
                        )
                    ), !candidates.isEmpty
                else {
                    continue
                }

                var prospective = selection.byReminder
                prospective[reminderID] = candidates
                if try identifierCount(
                    for: allocation.selectedGroups,
                    repeatingByReminder: prospective
                ) <= input.capacity {
                    selection.byReminder = prospective
                }
            } catch {
                // The accepted baseline remains safe. Without a future group identity,
                // this pass can only retire this reminder's later work.
                selection.continuationRetired.insert(reminderID)
            }
        }
        return selection
    }

    private func initialContinuationHeads(
        states: inout [ReminderPlanningState],
        allocation: PlanningAllocation,
        repeatingSelection: RepeatingSelection
    ) -> [RollingHead] {
        var heads: [RollingHead] = []
        for index in states.indices {
            let reminderID = states[index].reminder.id
            guard allocation.baselineSelected.contains(reminderID),
                repeatingSelection.byReminder[reminderID] == nil,
                !repeatingSelection.continuationRetired.contains(reminderID)
            else {
                continue
            }
            do {
                try dependencies.failureCheck(.initialContinuation, reminderID)
                if let next = try states[index].cursor.next() {
                    heads.append(RollingHead(stateIndex: index, group: next))
                }
            } catch {
                // No future AlertGroupID is available to classify. Retire only this
                // cursor and preserve its already accepted baseline.
                continue
            }
        }
        return heads
    }

    private func allocateContinuations(
        states: inout [ReminderPlanningState],
        initialHeads: [RollingHead],
        capacity: Int,
        repeatingByReminder: [UUID: [RepeatingTriggerCandidate]],
        allocation: inout PlanningAllocation
    ) {
        var heads = initialHeads
        while let headIndex = heads.indices.min(by: {
            groupPrecedes(heads[$0].group, heads[$1].group)
        }) {
            let head = heads.remove(at: headIndex)
            do {
                guard
                    try identifierCount(
                        for: allocation.selectedGroups + [head.group],
                        repeatingByReminder: repeatingByReminder
                    ) <= capacity
                else {
                    allocation.outcomes[head.group.id] = .unscheduledCapacity
                    continue
                }
                allocation.selectedGroups.append(head.group)
                allocation.selectedGroupIDs.append(head.group.id)
                allocation.outcomes[head.group.id] = .scheduled
            } catch {
                allocation.outcomes[head.group.id] = .unscheduledError
                continue
            }

            do {
                try dependencies.failureCheck(
                    .acceptedContinuationAdvance,
                    head.group.id.reminderID
                )
                if let next = try states[head.stateIndex].cursor.next() {
                    heads.append(RollingHead(stateIndex: head.stateIndex, group: next))
                }
            } catch {
                // Acceptance is already committed. A later cursor failure cannot
                // retroactively change that group's outcome or selected requests.
                continue
            }
        }
    }

    private func scheduledThrough(
        _ selectedGroups: [PlanningGroup],
        repeatingByReminder: [UUID: [RepeatingTriggerCandidate]]
    ) -> [UUID: Date] {
        var result: [UUID: Date] = [:]
        for group in selectedGroups where repeatingByReminder[group.id.reminderID] == nil {
            guard let lastAlert = group.alerts.map(\.alertInstant).max() else { continue }
            result[group.id.reminderID] = max(
                result[group.id.reminderID] ?? lastAlert,
                lastAlert
            )
        }
        return result
    }

    private func uniqueReminders(_ reminders: [ReminderSnapshot]) throws -> [ReminderSnapshot] {
        var byID: [UUID: ReminderSnapshot] = [:]
        for reminder in reminders {
            if let existing = byID[reminder.id], existing != reminder {
                throw LogicalNotificationPlannerError.duplicateReminderID(reminder.id)
            }
            byID[reminder.id] = reminder
        }
        return byID.values.sorted {
            $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased()
        }
    }
}

enum LogicalNotificationPlannerFailurePoint: Sendable, Equatable {
    case repeatingReplacement
    case initialContinuation
    case acceptedContinuationAdvance
}

struct LogicalNotificationPlannerDependencies: Sendable {
    let failureCheck: @Sendable (LogicalNotificationPlannerFailurePoint, UUID) throws -> Void

    init(
        failureCheck:
            @escaping @Sendable (
                LogicalNotificationPlannerFailurePoint,
                UUID
            ) throws -> Void
    ) {
        self.failureCheck = failureCheck
    }

    static let production = LogicalNotificationPlannerDependencies { _, _ in }
}

private struct ReminderClassification {
    let statuses: [UUID: ReminderStatus]
    let active: [(ReminderSnapshot, ScheduleDefinition)]
}

private struct PlanningAllocation {
    var selectedGroups: [PlanningGroup] = []
    var outcomes: [AlertGroupID: AlertGroupSchedulingOutcome] = [:]
    var selectedGroupIDs: [AlertGroupID] = []
    var baselineSelected: Set<UUID> = []
}

private struct RepeatingSelection {
    var byReminder: [UUID: [RepeatingTriggerCandidate]] = [:]
    var continuationRetired: Set<UUID> = []
}

private struct ReminderPlanningState {
    let reminder: ReminderSnapshot
    let schedule: ScheduleDefinition
    var cursor: FutureAlertGroupCursor
    let earliest: PlanningGroup
}

private struct RollingHead {
    let stateIndex: Int
    let group: PlanningGroup
}

private struct PlanningGroup {
    let id: AlertGroupID
    let alerts: [EffectiveAlert]

    var firstAlertInstant: Date {
        guard let first = alerts.map(\.alertInstant).min() else {
            preconditionFailure("Planning groups must contain at least one alert")
        }
        return first
    }
}

private func groupPrecedes(_ lhs: PlanningGroup, _ rhs: PlanningGroup) -> Bool {
    if lhs.firstAlertInstant != rhs.firstAlertInstant {
        return lhs.firstAlertInstant < rhs.firstAlertInstant
    }
    let lhsUUID = lhs.id.reminderID.uuidString.lowercased()
    let rhsUUID = rhs.id.reminderID.uuidString.lowercased()
    if lhsUUID != rhsUUID { return lhsUUID < rhsUUID }
    return lhs.id.baseOccurrenceInstant < rhs.id.baseOccurrenceInstant
}

private func identifierCount(
    for groups: [PlanningGroup],
    repeatingByReminder: [UUID: [RepeatingTriggerCandidate]] = [:]
) throws -> Int {
    let codec = NotificationIdentifierCodec()
    var identifiers: Set<String> = []
    for group in groups where repeatingByReminder[group.id.reminderID] == nil {
        for alert in group.alerts {
            identifiers.insert(
                try codec.oneShotIdentifier(
                    reminderID: group.id.reminderID,
                    alertInstant: alert.alertInstant
                ))
        }
    }
    for (reminderID, candidates) in repeatingByReminder {
        for candidate in candidates {
            identifiers.insert(
                try codec.repeatingIdentifier(
                    reminderID: reminderID,
                    components: candidate.components
                ))
        }
    }
    return identifiers.count
}

private struct OneShotAccumulator {
    let identifier: String
    let reminderID: UUID
    let alertInstant: Date
    var reasons: [EffectiveAlert]
    var contributorIDs: Set<AlertGroupID>
}

private struct ReasonIdentity: Hashable {
    let kind: Int
    let baseInstant: Date
    let alertInstant: Date
}

private func logicalRequests(
    selectedGroups: [PlanningGroup],
    repeatingByReminder: [UUID: [RepeatingTriggerCandidate]]
) throws -> [LogicalNotificationRequest] {
    let codec = NotificationIdentifierCodec()
    var oneShots: [String: OneShotAccumulator] = [:]

    for group in selectedGroups where repeatingByReminder[group.id.reminderID] == nil {
        for alert in group.alerts {
            let identifier = try codec.oneShotIdentifier(
                reminderID: group.id.reminderID,
                alertInstant: alert.alertInstant
            )
            if var existing = oneShots[identifier] {
                existing.reasons.append(alert)
                existing.contributorIDs.insert(group.id)
                oneShots[identifier] = existing
            } else {
                oneShots[identifier] = OneShotAccumulator(
                    identifier: identifier,
                    reminderID: group.id.reminderID,
                    alertInstant: alert.alertInstant,
                    reasons: [alert],
                    contributorIDs: [group.id]
                )
            }
        }
    }

    var requests = oneShots.values.map { accumulator in
        var seen: Set<ReasonIdentity> = []
        let reasons = accumulator.reasons.filter { reason in
            seen.insert(
                ReasonIdentity(
                    kind: reason.kind == .main ? 0 : 1,
                    baseInstant: reason.baseOccurrence.instant,
                    alertInstant: reason.alertInstant
                )
            ).inserted
        }.sorted {
            if $0.kind != $1.kind { return $0.kind == .main }
            return $0.baseOccurrence.instant < $1.baseOccurrence.instant
        }
        return LogicalNotificationRequest(
            identifier: accumulator.identifier,
            reminderID: accumulator.reminderID,
            payload: .oneShot(alertInstant: accumulator.alertInstant, reasons: reasons),
            contributingGroupIDs: accumulator.contributorIDs
        )
    }

    for (reminderID, candidates) in repeatingByReminder {
        let baselineIDs = Set(
            selectedGroups.lazy
                .filter { $0.id.reminderID == reminderID }
                .map(\.id))
        for candidate in candidates {
            requests.append(
                LogicalNotificationRequest(
                    identifier: try codec.repeatingIdentifier(
                        reminderID: reminderID,
                        components: candidate.components
                    ),
                    reminderID: reminderID,
                    payload: .repeating(
                        components: candidate.components,
                        contributors: candidate.contributors
                    ),
                    contributingGroupIDs: baselineIDs
                ))
        }
    }

    return requests.sorted {
        if $0.identifier != $1.identifier { return $0.identifier < $1.identifier }
        return $0.reminderID.uuidString.lowercased() < $1.reminderID.uuidString.lowercased()
    }
}

private struct FutureAlertGroupCursor {
    private var groups: AlertGroupCursor
    private let reminderID: UUID
    private let evaluationNow: Date
    private var seenIDs: Set<AlertGroupID> = []

    init(
        reminderID: UUID,
        schedule: ScheduleDefinition,
        evaluationNow: Date,
        environment: any RecurrenceEnvironment
    ) throws {
        guard
            let timeZone = environment.timeZone(
                identifier: schedule.source.timeZoneIdentifier
            )
        else {
            throw SourceWallClockResolutionError.unknownTimeZone
        }
        let calendar = environment.gregorianCalendar(in: timeZone)
        let range = try planningRange(
            schedule: schedule,
            evaluationNow: evaluationNow,
            calendar: calendar
        )
        let sequence: AnySequence<BaseOccurrence>
        if let range {
            sequence = try FoundationRecurrenceEngine().baseOccurrences(
                for: schedule,
                in: range,
                environment: environment
            )
        } else {
            sequence = AnySequence([])
        }
        groups = AlertGroupCursor(
            baseOccurrences: sequence.makeIterator(),
            schedule: schedule,
            calendar: calendar
        )
        self.reminderID = reminderID
        self.evaluationNow = evaluationNow
    }

    mutating func next() throws -> PlanningGroup? {
        while let group = try groups.next() {
            let id = AlertGroupID(
                reminderID: reminderID,
                baseOccurrenceInstant: group.baseOccurrence.instant
            )
            guard seenIDs.insert(id).inserted else { continue }
            let futureAlerts = uniqueAlerts(
                group.alerts.filter {
                    $0.alertInstant > evaluationNow
                })
            guard !futureAlerts.isEmpty else { continue }
            return PlanningGroup(id: id, alerts: futureAlerts)
        }
        return nil
    }
}

private func uniqueAlerts(_ alerts: [EffectiveAlert]) -> [EffectiveAlert] {
    var seen: Set<ReasonIdentity> = []
    return alerts.filter { alert in
        seen.insert(
            ReasonIdentity(
                kind: alert.kind == .main ? 0 : 1,
                baseInstant: alert.baseOccurrence.instant,
                alertInstant: alert.alertInstant
            )
        ).inserted
    }.sorted {
        if $0.alertInstant != $1.alertInstant { return $0.alertInstant < $1.alertInstant }
        if $0.kind != $1.kind { return $0.kind == .main }
        return $0.baseOccurrence.instant < $1.baseOccurrence.instant
    }
}

private func planningRange(
    schedule: ScheduleDefinition,
    evaluationNow: Date,
    calendar: Calendar
) throws -> Range<Date>? {
    guard
        let supportedLowerBound = calendar.date(
            from: DateComponents(year: 1, month: 1, day: 1, hour: 0, minute: 0, second: 0)
        ),
        let supportedUpperBound = calendar.date(
            from: DateComponents(year: 10_000, month: 1, day: 1, hour: 0, minute: 0, second: 0)
        )
    else {
        throw FoundationRecurrenceError.arithmeticOverflow
    }

    let anchor = try SourceWallClockResolver().resolve(schedule.source, calendar: calendar)
    var candidates: [Date] = []
    if schedule.early?.mainEnabled != false { candidates.append(evaluationNow) }
    if let early = schedule.early {
        candidates.append(
            try baseCandidate(
                after: evaluationNow,
                early: early,
                rule: schedule.rule,
                calendar: calendar
            ))
    }
    guard let candidate = candidates.min() else { return nil }

    let proposedLowerBound: Date
    switch schedule.rule {
    case .none:
        proposedLowerBound = min(anchor, candidate)
    case .hourly(let interval):
        proposedLowerBound = try addFixed(-Int64(interval) * 3_600, to: candidate)
    case .daily(let interval):
        proposedLowerBound = try addCalendar(
            .day, value: -interval, to: candidate, calendar: calendar)
    case .weekly(let interval, _, _):
        proposedLowerBound = try addCalendar(
            .weekOfYear,
            value: -interval,
            to: candidate,
            calendar: calendar
        )
    case .monthly(let interval, _):
        proposedLowerBound = try addCalendar(
            .month, value: -interval, to: candidate, calendar: calendar)
    case .yearly(let interval, _, _):
        proposedLowerBound = try addCalendar(
            .year, value: -interval, to: candidate, calendar: calendar)
    }
    let lowerBound = max(supportedLowerBound, proposedLowerBound)
    guard lowerBound < supportedUpperBound else { return nil }
    return lowerBound..<supportedUpperBound
}

private func baseCandidate(
    after evaluationNow: Date,
    early: EarlyReminder,
    rule: RepeatRule,
    calendar: Calendar
) throws -> Date {
    switch (early.unit, rule) {
    case (.days, .hourly):
        return try addFixed(Int64(early.value) * 86_400, to: evaluationNow)
    case (.weeks, .hourly):
        return try addFixed(Int64(early.value) * 604_800, to: evaluationNow)
    case (.days, _):
        return try addCalendar(.day, value: early.value, to: evaluationNow, calendar: calendar)
    case (.weeks, _):
        return try addCalendar(
            .weekOfYear, value: early.value, to: evaluationNow, calendar: calendar)
    case (.minutes, _):
        return try addFixed(Int64(early.value) * 60, to: evaluationNow)
    case (.hours, _):
        return try addFixed(Int64(early.value) * 3_600, to: evaluationNow)
    }
}

private func addFixed(_ seconds: Int64, to date: Date) throws -> Date {
    let result = date.addingTimeInterval(Double(seconds))
    guard result.timeIntervalSinceReferenceDate.isFinite else {
        throw FoundationRecurrenceError.arithmeticOverflow
    }
    return result
}

private func addCalendar(
    _ component: Calendar.Component,
    value: Int,
    to date: Date,
    calendar: Calendar
) throws -> Date {
    guard let result = calendar.date(byAdding: component, value: value, to: date) else {
        throw FoundationRecurrenceError.arithmeticOverflow
    }
    return result
}
