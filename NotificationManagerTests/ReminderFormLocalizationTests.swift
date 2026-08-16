import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import Testing

@testable import NotificationManager

struct ReminderFormLocalizationTests {
    @Test func fieldIssuesUseReminderFormResources() {
        let fixtures: [(ReminderFormFieldIssue, String)] = [
            (.titleRequired, "reminder.form.error.title-required"),
            (.titleTooLarge, "reminder.form.error.title-too-large"),
            (.notesTooLarge, "reminder.form.error.notes-too-large"),
            (.urlInvalid, "reminder.form.error.url-invalid"),
            (.urlTooLarge, "reminder.form.error.url-too-large"),
            (.timeZoneRequired, "reminder.form.error.time-zone-required"),
            (.timeZoneInvalid, "reminder.form.error.time-zone-invalid"),
            (.repeatEndInvalid, "reminder.form.error.invalid-repeat-end-date"),
            (.repeatEndBeforeStart, "reminder.form.error.repeat-end-before-start")
        ]

        for (issue, key) in fixtures {
            expectReminderFormResource(issue.localizedResource, key: key)
        }
    }

    @Test func readOnlyReasonsUseReminderFormResources() {
        let fixtures: [(ReminderFormReadOnlyReason, String)] = [
            (.updateRequired, "reminder.form.schedule-update-required"),
            (.invalidSchedule, "reminder.form.schedule-corrupt")
        ]

        for (reason, key) in fixtures {
            expectReminderFormResource(reason.localizedResource, key: key)
        }
    }

    @Test func earlyReminderChoicesUseReminderFormResources() {
        let fixtures: [(EarlyReminderChoice, String)] = [
            (.none, "reminder.early.none"),
            (.oneMinute, "reminder.early.one-minute-before"),
            (.fiveMinutes, "reminder.early.five-minutes-before"),
            (.custom, "reminder.early.custom")
        ]

        for (choice, key) in fixtures {
            expectReminderFormResource(choice.localizedResource, key: key)
        }
    }

    @Test func customRepeatErrorsUseReminderFormResources() {
        let fixtures: [(CustomRepeatResolutionError, String)] = [
            (
                .assistanceUnavailable(.platformUnsupported),
                "reminder.custom.error.assistance-unavailable"
            ),
            (.safetyGuard, "reminder.custom.error.safety"),
            (.generation, "reminder.custom.error.generation"),
            (.validation(.unsupported), "reminder.custom.error.validation")
        ]

        for (error, key) in fixtures {
            expectReminderFormResource(error.localizedResource, key: key)
        }
    }

    private func expectReminderFormResource(
        _ resource: LocalizedStringResource,
        key: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(resource.key == .init(stringLiteral: key), sourceLocation: sourceLocation)
        #expect(resource.table == "ReminderForm", sourceLocation: sourceLocation)
    }
}
