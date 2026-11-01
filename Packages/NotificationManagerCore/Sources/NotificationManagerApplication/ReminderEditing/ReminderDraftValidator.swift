import Foundation
import NotificationManagerDomain

public struct ReminderDraftValidator: Sendable {
    private let aggregateValidator: ReminderAggregateValidator

    public init() {
        aggregateValidator = ReminderAggregateValidator()
    }

    public func validate(
        _ draft: ReminderDraft,
        replacementScheduleData: Data?
    ) throws -> ValidatedReminderAggregate {
        switch draft.scheduleChange {
        case .preserveOriginal:
            return try aggregateValidator.validate(draft)
        case .replace:
            guard let replacementScheduleData else {
                throw ReminderValidationIssue.replacementScheduleDataRequired
            }
            return try aggregateValidator.validate(
                draft,
                replacementScheduleData: replacementScheduleData
            )
        }
    }

    public func validateMetadataOnly(
        _ draft: ReminderDraft
    ) throws -> ValidatedReminderAggregate {
        guard case .preserveOriginal = draft.scheduleChange,
            draft.originalScheduleData != nil
        else {
            throw ReminderValidationIssue.missingScheduleData
        }
        let neutralScheduleDraft = ReminderDraft(
            id: draft.id,
            title: draft.title,
            notes: draft.notes,
            urlString: draft.urlString,
            enabled: draft.enabled,
            source: draft.source,
            rule: draft.rule,
            end: draft.end,
            early: draft.early,
            durationSeconds: draft.durationSeconds,
            scheduleChange: .preserveOriginal,
            originalScheduleData: Data(),
            tagIDs: draft.tagIDs,
            createdAt: draft.createdAt,
            updatedAt: draft.updatedAt
        )
        return try aggregateValidator.validate(neutralScheduleDraft)
    }
}
