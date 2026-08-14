import Testing
@testable import NotificationManager

struct LocalizationTableTests {
    @Test func routesKnownSemanticKey() {
        let fixtures: [(String, LocalizationTable)] = [
            ("common.retry", .common),
            ("reminder.form.create.title", .reminderForm),
            ("reminder.field.title", .reminderForm),
            ("reminder.early.none", .reminderForm),
            ("reminder.early-unit.minutes", .reminderForm),
            ("reminder.repeat.daily", .reminderForm),
            ("reminder.repeat-end.never", .reminderForm),
            ("reminder.custom.error.validation", .reminderForm),
            ("reminder.action.back", .reminder),
            ("reminder.action.save", .reminder),
            ("localization.repeat.one-time", .notificationText),
            ("settings.title", .settings),
            ("privacy.title", .settings),
            ("tags.management.title", .tags),
            ("data_unavailable.title", .recovery),
            ("notification_unavailable.title", .recovery),
            ("recovery.error.data-unavailable", .recovery)
        ]
        for (key, expected) in fixtures {
            #expect(LocalizationTable(semanticKey: key) == expected)
        }
    }

    @Test func rejectsUnknownOrIncompleteKey() {
        #expect(LocalizationTable(semanticKey: "unknown.title") == nil)
        #expect(LocalizationTable(semanticKey: "reminder") == nil)
    }
}
