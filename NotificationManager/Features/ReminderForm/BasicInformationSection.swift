import SwiftUI

struct BasicInformationSection: View {
    @Bindable var model: ReminderFormModel

    var body: some View {
        Section {
            TextField(text: $model.title) {
                Text(
                    LocalizedStringResource(
                        "reminder.field.title",
                        table: "ReminderForm"
                    ))
            }
            .textInputAutocapitalization(.sentences)
            .accessibilityIdentifier("reminder-form.title")

            if let issue = model.titleFieldIssue {
                fieldError(issue, identifier: "reminder-form.title-error")
            }

            TextField(text: optionalTextBinding(\.notes), axis: .vertical) {
                Text(
                    LocalizedStringResource(
                        "reminder.field.notes",
                        table: "ReminderForm"
                    ))
            }
            .lineLimit(3...8)
            .accessibilityIdentifier("reminder-form.notes")

            if let issue = model.notesFieldIssue {
                fieldError(issue, identifier: "reminder-form.notes-error")
            }

            TextField(text: optionalTextBinding(\.urlString)) {
                Text(
                    LocalizedStringResource(
                        "reminder.field.url",
                        table: "ReminderForm"
                    ))
            }
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .accessibilityIdentifier("reminder-form.url")

            if let issue = model.urlFieldIssue {
                fieldError(issue, identifier: "reminder-form.url-error")
            }
        } header: {
            Text(
                LocalizedStringResource(
                    "reminder.form.section.basic-information",
                    table: "ReminderForm"
                )
            )
            .background {
                AccessibilityIdentifierContainer(
                    identifier: "reminder-form.section.basic-information"
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func optionalTextBinding(
        _ keyPath: ReferenceWritableKeyPath<ReminderFormModel, String?>
    ) -> Binding<String> {
        Binding(
            get: { model[keyPath: keyPath] ?? "" },
            set: { model[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func fieldError(
        _ issue: ReminderFormFieldIssue,
        identifier: String
    ) -> some View {
        Label(issue.localizedResource, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifier)
    }
}

extension ReminderFormFieldIssue {
    var localizedResource: LocalizedStringResource {
        switch self {
        case .titleRequired:
            LocalizedStringResource("reminder.form.error.title-required", table: "ReminderForm")
        case .titleTooLarge:
            LocalizedStringResource("reminder.form.error.title-too-large", table: "ReminderForm")
        case .notesTooLarge:
            LocalizedStringResource("reminder.form.error.notes-too-large", table: "ReminderForm")
        case .urlInvalid:
            LocalizedStringResource("reminder.form.error.url-invalid", table: "ReminderForm")
        case .urlTooLarge:
            LocalizedStringResource("reminder.form.error.url-too-large", table: "ReminderForm")
        case .timeZoneRequired:
            LocalizedStringResource(
                "reminder.form.error.time-zone-required",
                table: "ReminderForm"
            )
        case .timeZoneInvalid:
            LocalizedStringResource("reminder.form.error.time-zone-invalid", table: "ReminderForm")
        case .repeatEndInvalid:
            LocalizedStringResource(
                "reminder.form.error.invalid-repeat-end-date",
                table: "ReminderForm"
            )
        case .repeatEndBeforeStart:
            LocalizedStringResource(
                "reminder.form.error.repeat-end-before-start",
                table: "ReminderForm"
            )
        case .rangeEndInvalid:
            LocalizedStringResource(
                "reminder.form.error.range-end-invalid",
                table: "ReminderForm"
            )
        case .rangeEndBeforeStart:
            LocalizedStringResource(
                "reminder.form.error.range-end-before-start",
                table: "ReminderForm"
            )
        }
    }
}
