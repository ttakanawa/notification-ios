enum LocalizationTable: String, CaseIterable, Sendable {
    case common = "Common"
    case reminderForm = "ReminderForm"
    case reminder = "Reminder"
    case notificationText = "NotificationText"
    case settings = "Settings"
    case tags = "Tags"
    case recovery = "Recovery"

    init?(semanticKey: String) {
        let reminderFormPrefixes = [
            "reminder.form.",
            "reminder.field.",
            "reminder.early.",
            "reminder.early-unit.",
            "reminder.repeat.",
            "reminder.repeat-end.",
            "reminder.custom."
        ]
        if semanticKey.hasPrefix("common.") {
            self = .common
        } else if reminderFormPrefixes.contains(where: semanticKey.hasPrefix) {
            self = .reminderForm
        } else if semanticKey.hasPrefix("reminder.") {
            self = .reminder
        } else if semanticKey.hasPrefix("localization.") {
            self = .notificationText
        } else if semanticKey.hasPrefix("settings.")
            || semanticKey.hasPrefix("privacy.")
        {
            self = .settings
        } else if semanticKey.hasPrefix("tags.") {
            self = .tags
        } else if semanticKey.hasPrefix("data_unavailable.")
            || semanticKey.hasPrefix("notification_unavailable.")
            || semanticKey.hasPrefix("recovery.")
        {
            self = .recovery
        } else {
            return nil
        }
    }
}
