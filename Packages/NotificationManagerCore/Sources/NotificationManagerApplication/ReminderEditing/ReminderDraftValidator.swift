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
}
