import NotificationManagerDomain
import SwiftUI

struct DateTimeSection: View {
    @Bindable var model: ReminderFormModel

    var body: some View {
        Section {
            if case let .readOnly(reason) = model.scheduleAccess {
                Label(reason.localizedResource, systemImage: "lock")
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        AccessibilityIdentifierContainer(
                            identifier: "reminder-form.schedule-read-only"
                        )
                    }
            }

            TextField(LocalizedStringResource(
                "reminder.field.date-placeholder",
                table: "ReminderForm"
            ), text: dateBinding, prompt: nil)
                .textContentType(.dateTime)
                .keyboardType(.numbersAndPunctuation)
                .disabled(!model.scheduleFieldsAreEditable)
                .accessibilityLabel(Text(LocalizedStringResource(
                    "reminder.field.date",
                    table: "ReminderForm"
                )))
                .accessibilityIdentifier("reminder-form.date")

            if !model.sourceDateTextIsValid {
                Label(LocalizedStringResource(
                    "reminder.form.error.invalid-date",
                    table: "ReminderForm"
                ), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reminder-form.date-error")
            }

            TextField(LocalizedStringResource(
                "reminder.field.time-placeholder",
                table: "ReminderForm"
            ), text: timeBinding, prompt: nil)
                .textContentType(.dateTime)
                .keyboardType(.numbersAndPunctuation)
                .disabled(!model.scheduleFieldsAreEditable)
                .accessibilityLabel(Text(LocalizedStringResource(
                    "reminder.field.time",
                    table: "ReminderForm"
                )))
                .accessibilityIdentifier("reminder-form.time")

            if !model.sourceTimeTextIsValid {
                Label(LocalizedStringResource(
                    "reminder.form.error.invalid-time",
                    table: "ReminderForm"
                ), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reminder-form.time-error")
            }

            TextField(LocalizedStringResource(
                "reminder.field.time-zone-placeholder",
                table: "ReminderForm"
            ), text: timeZoneBinding, prompt: nil)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(!model.scheduleFieldsAreEditable)
                .accessibilityLabel(Text(LocalizedStringResource(
                    "reminder.field.time-zone",
                    table: "ReminderForm"
                )))
                .accessibilityIdentifier("reminder-form.time-zone")

            if let issue = model.timeZoneFieldIssue {
                Label(issue.localizedResource, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reminder-form.time-zone-error")
            }

            if case let .repair(issues) = model.scheduleAccess, !issues.isEmpty {
                Label(LocalizedStringResource(
                    "reminder.form.schedule-repair-required",
                    table: "ReminderForm"
                ), systemImage: "wrench.and.screwdriver")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reminder-form.schedule-repair")
            }
        } header: {
            Text(LocalizedStringResource(
                "reminder.form.section.date-time",
                table: "ReminderForm"
            ))
                .background {
                    AccessibilityIdentifierContainer(
                        identifier: "reminder-form.section.date-time"
                    )
                }
        }
        .accessibilityElement(children: .contain)
    }

    private var dateBinding: Binding<String> {
        Binding(
            get: { model.sourceDateText },
            set: { input in
                model.updateSourceDateText(input)
            }
        )
    }

    private var timeBinding: Binding<String> {
        Binding(
            get: { model.sourceTimeText },
            set: { input in
                model.updateSourceTimeText(input)
            }
        )
    }

    private var timeZoneBinding: Binding<String> {
        Binding(
            get: { model.timeZoneIdentifier ?? "" },
            set: { model.timeZoneIdentifier = $0.isEmpty ? nil : $0 }
        )
    }

}

extension ReminderFormReadOnlyReason {
    var localizedResource: LocalizedStringResource {
        switch self {
        case .updateRequired:
            LocalizedStringResource(
                "reminder.form.schedule-update-required",
                table: "ReminderForm"
            )
        case .invalidSchedule:
            LocalizedStringResource(
                "reminder.form.schedule-corrupt",
                table: "ReminderForm"
            )
        }
    }
}
