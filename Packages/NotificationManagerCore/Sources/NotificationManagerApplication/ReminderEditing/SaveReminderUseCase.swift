import Foundation
import NotificationManagerDomain

public enum CapacityConsent: Sendable, Equatable {
    case notProvided
    case acknowledged
}

public enum ExpiredScheduleConsent: Sendable, Equatable {
    case notProvided
    case acknowledged
}

public struct CapacityWarning: Sendable, Equatable {
    public let reminderID: UUID
    public let earliestGroupID: AlertGroupID
    public let planningCapacity: Int

    public init(reminderID: UUID, earliestGroupID: AlertGroupID, planningCapacity: Int) {
        self.reminderID = reminderID
        self.earliestGroupID = earliestGroupID
        self.planningCapacity = planningCapacity
    }
}

public struct ExpiredScheduleWarning: Sendable, Equatable {
    public let reminderID: UUID
    public let evaluationNow: Date

    public init(reminderID: UUID, evaluationNow: Date) {
        self.reminderID = reminderID
        self.evaluationNow = evaluationNow
    }
}

public enum SaveReminderOutcome: Sendable, Equatable {
    case saved(UUID)
    case requiresCapacityConfirmation(CapacityWarning)
    case requiresExpiredScheduleConfirmation(ExpiredScheduleWarning)
}

public enum SaveReminderError: Error, Sendable, Equatable {
    case existingReminderNotFound(UUID)
}

public struct SaveReminderUseCase: Sendable {
    private let repository: any ReminderRepository
    private let scheduleCodec: any SchedulePayloadCoding
    private let preferenceStore: any DeviceNotificationPreferenceStore
    private let authorizationState: @Sendable () async -> DeviceAuthorizationSchedulingState
    private let reconcileRequester: any ReconcileRequesting
    private let now: @Sendable () -> Date
    private let recurrenceEnvironment: any RecurrenceEnvironment
    private let draftValidator = ReminderDraftValidator()

    private static let planningCapacity = 60

    public init(
        repository: any ReminderRepository,
        scheduleCodec: any SchedulePayloadCoding,
        preferenceStore: any DeviceNotificationPreferenceStore,
        authorizationState: @escaping @Sendable () async -> DeviceAuthorizationSchedulingState,
        reconcileRequester: any ReconcileRequesting,
        now: @escaping @Sendable () -> Date = { Date() },
        recurrenceEnvironment: any RecurrenceEnvironment = FoundationRecurrenceEnvironment()
    ) {
        self.repository = repository
        self.scheduleCodec = scheduleCodec
        self.preferenceStore = preferenceStore
        self.authorizationState = authorizationState
        self.reconcileRequester = reconcileRequester
        self.now = now
        self.recurrenceEnvironment = recurrenceEnvironment
    }

    public func execute(
        draft: ReminderDraft,
        capacityConsent: CapacityConsent = .notProvided,
        expiredScheduleConsent: ExpiredScheduleConsent = .notProvided
    ) async throws -> SaveReminderOutcome {
        let replacementSchedule = replacementSchedule(in: draft)
        let replacementPayload = try replacementSchedule.map(scheduleCodec.encodeCurrent)

        let validated = try validatePreflight(
            draft,
            replacementScheduleData: replacementPayload?.data
        )
        let saveEvaluationNow: Date?
        if let replacementSchedule {
            let evaluationNow = now()
            saveEvaluationNow = evaluationNow
            if try !hasFutureNotification(
                reminderID: draft.id,
                schedule: replacementSchedule,
                evaluationNow: evaluationNow
            ), expiredScheduleConsent == .notProvided {
                return .requiresExpiredScheduleConfirmation(
                    ExpiredScheduleWarning(
                        reminderID: draft.id,
                        evaluationNow: evaluationNow
                    ))
            }
        } else {
            saveEvaluationNow = nil
        }

        let deviceNotificationsEnabled = await preferenceStore.isEnabled()
        if deviceNotificationsEnabled {
            let authorization = await authorizationState()
            if authorization == .allowed {
                let snapshot = try await repository.fetchCompleteSnapshot()
                let hypothetical = try hypotheticalSnapshot(
                    durable: snapshot,
                    draft: draft,
                    aggregate: validated,
                    replacementSchedule: replacementSchedule,
                    replacementPayload: replacementPayload
                )
                let evaluationNow = saveEvaluationNow ?? now()
                let plan = try LogicalNotificationPlanner().plan(
                    PlannerInput(
                        snapshot: hypothetical,
                        evaluationNow: evaluationNow,
                        deviceNotificationsEnabled: true,
                        authorizationAllowsScheduling: true,
                        capacity: Self.planningCapacity,
                        recurrenceEnvironment: recurrenceEnvironment
                    ))
                if let warning = capacityWarning(
                    for: draft.id,
                    in: plan
                ), capacityConsent == .notProvided {
                    return .requiresCapacityConfirmation(warning)
                }
            }
        }

        let commitNow = now()
        if let replacementSchedule,
            try !hasFutureNotification(
                reminderID: draft.id,
                schedule: replacementSchedule,
                evaluationNow: commitNow
            ),
            expiredScheduleConsent == .notProvided
        {
            return .requiresExpiredScheduleConfirmation(
                ExpiredScheduleWarning(
                    reminderID: draft.id,
                    evaluationNow: commitNow
                ))
        }

        var committingDraft = draft
        committingDraft.updatedAt = Self.integralSecond(commitNow)
        let committingAggregate = try validatePreflight(
            committingDraft,
            replacementScheduleData: replacementPayload?.data
        )
        let saved = try await repository.save(
            EncodedReminderMutation(
                committingAggregate,
                command: mutationCommand(
                    for: committingDraft,
                    validatedScheduleData: committingAggregate.scheduleData
                )
            ))
        await reconcileRequester.requestReconcile(.reminderSaved(saved.id))
        return .saved(saved.id)
    }

    private func replacementSchedule(in draft: ReminderDraft) -> ScheduleDefinition? {
        guard case .replace(let schedule) = draft.scheduleChange else { return nil }
        return schedule
    }

    private func validatePreflight(
        _ draft: ReminderDraft,
        replacementScheduleData: Data?
    ) throws -> ValidatedReminderAggregate {
        guard case .preserveOriginal = draft.scheduleChange else {
            return try draftValidator.validate(
                draft,
                replacementScheduleData: replacementScheduleData
            )
        }
        return try draftValidator.validateMetadataOnly(draft)
    }

    private func mutationCommand(
        for draft: ReminderDraft,
        validatedScheduleData: Data
    ) -> ReminderMutationCommand {
        switch (draft.originalScheduleData, draft.scheduleChange) {
        case (nil, .replace):
            return .create(scheduleData: validatedScheduleData)
        case (.some, .preserveOriginal):
            return .updateMetadataPreservingCurrentSchedule
        case (.some, .replace):
            return .replaceSchedule(scheduleData: validatedScheduleData)
        case (nil, .preserveOriginal):
            preconditionFailure("Validated new reminders always provide a replacement schedule")
        }
    }

    private func hasFutureNotification(
        reminderID: UUID,
        schedule: ScheduleDefinition,
        evaluationNow: Date
    ) throws -> Bool {
        try !NextNotificationProvider().nextPhysicalNotifications(
            for: reminderID,
            schedule: schedule,
            after: evaluationNow,
            limit: 1,
            environment: recurrenceEnvironment
        ).notifications.isEmpty
    }

    private func hypotheticalSnapshot(
        durable: CompleteReminderSnapshot,
        draft: ReminderDraft,
        aggregate: ValidatedReminderAggregate,
        replacementSchedule: ScheduleDefinition?,
        replacementPayload: EncodedSchedulePayload?
    ) throws -> CompleteReminderSnapshot {
        let schedule: ScheduleReadState
        if let replacementSchedule {
            guard let replacementPayload else {
                preconditionFailure("Replacement schedules always have an encoded payload")
            }
            schedule = .valid(
                replacementSchedule,
                sourceVersion: replacementPayload.version,
                originalData: replacementPayload.data
            )
        } else {
            guard let durableReminder = durable.reminders.first(where: { $0.id == draft.id }) else {
                throw SaveReminderError.existingReminderNotFound(draft.id)
            }
            schedule = durableReminder.schedule
        }

        let candidate = ReminderSnapshot(
            id: aggregate.id,
            title: aggregate.title,
            notes: aggregate.notes,
            urlString: aggregate.urlString,
            enabled: aggregate.enabled,
            schedule: schedule,
            tagIDs: aggregate.tagIDs,
            createdAt: aggregate.createdAt,
            updatedAt: aggregate.updatedAt
        )
        var reminders = durable.reminders.filter { $0.id != draft.id }
        reminders.append(candidate)
        return CompleteReminderSnapshot(reminders: reminders, tags: durable.tags)
    }

    private func capacityWarning(
        for reminderID: UUID,
        in plan: LogicalPlan
    ) -> CapacityWarning? {
        let candidateGroups = plan.outcomes.keys
            .filter { $0.reminderID == reminderID }
            .sorted { $0.baseOccurrenceInstant < $1.baseOccurrenceInstant }
        guard let earliest = candidateGroups.first,
            plan.outcomes[earliest] == .unscheduledCapacity
        else {
            return nil
        }
        return CapacityWarning(
            reminderID: reminderID,
            earliestGroupID: earliest,
            planningCapacity: Self.planningCapacity
        )
    }

    private static func integralSecond(_ date: Date) -> Date {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite else { return date }
        return Date(timeIntervalSince1970: seconds.rounded(.down))
    }
}
