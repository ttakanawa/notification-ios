enum AccessibilityErrorIdentity: String, Sendable, Hashable {
    case reminderTitleRequired = "reminder.form.error.title-required"
    case reminderTitleTooLarge = "reminder.form.error.title-too-large"
    case reminderNotesTooLarge = "reminder.form.error.notes-too-large"
    case reminderURLInvalid = "reminder.form.error.url-invalid"
    case reminderURLTooLarge = "reminder.form.error.url-too-large"
    case reminderDateInvalid = "reminder.form.error.invalid-date"
    case reminderTimeInvalid = "reminder.form.error.invalid-time"
    case reminderTimeZoneRequired = "reminder.form.error.time-zone-required"
    case reminderTimeZoneInvalid = "reminder.form.error.time-zone-invalid"
    case reminderRepeatEndInvalid = "reminder.form.error.invalid-repeat-end-date"
    case reminderRepeatEndBeforeStart = "reminder.form.error.repeat-end-before-start"
    case reminderEarlyValueInvalid = "reminder.form.error.invalid-early-value"
    case reminderCustomAssistanceUnavailable = "reminder.custom.error.assistance-unavailable"
    case reminderCustomSafety = "reminder.custom.error.safety"
    case reminderCustomGeneration = "reminder.custom.error.generation"
    case reminderCustomValidation = "reminder.custom.error.validation"
    case reminderSaveFailed = "reminder.form.save-failed"
    case reminderDeleteFailed = "reminder.form.delete-failed"
    case reminderEnabledChangeFailed = "reminder.action.enabled-change-failed"
    case settingsAuthorizationRequest = "settings.error.authorization-request"
    case settingsPendingCleanup = "settings.error.pending-cleanup"
    case tagEmptyName = "tags.error.empty-name"
    case tagNameTooLarge = "tags.error.name-too-large"
    case tagNormalizedNameTooLarge = "tags.error.normalized-name-too-large"
    case tagDuplicateName = "tags.error.duplicate-name"
    case tagNotFound = "tags.error.not-found"
    case tagStoreUnavailable = "tags.error.store-unavailable"
    case dataUnavailable = "recovery.error.data-unavailable"

    var localizationTable: LocalizationTable {
        guard let table = LocalizationTable(semanticKey: rawValue) else {
            preconditionFailure("Unowned accessibility localization key: \(rawValue)")
        }
        return table
    }
}

struct AccessibilityErrorAnnouncementResolver: Sendable {
    func newIdentity(
        previous: [AccessibilityErrorIdentity],
        current: [AccessibilityErrorIdentity]
    ) -> AccessibilityErrorIdentity? {
        let previousIdentities = Set(previous)
        return current.first { !previousIdentities.contains($0) }
    }
}
