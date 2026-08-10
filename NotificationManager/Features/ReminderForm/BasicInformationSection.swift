import SwiftUI

struct BasicInformationSection: View {
    @Bindable var model: ReminderFormModel

    var body: some View {
        Section {
            TextField("reminder.field.title", text: $model.title)
                .textInputAutocapitalization(.sentences)
                .accessibilityIdentifier("reminder-form.title")

            if let issue = model.titleFieldIssue {
                fieldError(issue, identifier: "reminder-form.title-error")
            }

            TextField(
                "reminder.field.notes",
                text: optionalTextBinding(\.notes),
                axis: .vertical
            )
            .lineLimit(3...8)
            .accessibilityIdentifier("reminder-form.notes")

            if let issue = model.notesFieldIssue {
                fieldError(issue, identifier: "reminder-form.notes-error")
            }

            TextField(
                "reminder.field.url",
                text: optionalTextBinding(\.urlString)
            )
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .accessibilityIdentifier("reminder-form.url")

            if let issue = model.urlFieldIssue {
                fieldError(issue, identifier: "reminder-form.url-error")
            }
        } header: {
            Text("reminder.form.section.basic-information")
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
        Label(issue.semanticKey, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifier)
    }
}

extension ReminderFormFieldIssue {
    var semanticKey: LocalizedStringKey {
        switch self {
        case .titleRequired: "reminder.form.error.title-required"
        case .titleTooLarge: "reminder.form.error.title-too-large"
        case .notesTooLarge: "reminder.form.error.notes-too-large"
        case .urlInvalid: "reminder.form.error.url-invalid"
        case .urlTooLarge: "reminder.form.error.url-too-large"
        case .timeZoneRequired: "reminder.form.error.time-zone-required"
        case .timeZoneInvalid: "reminder.form.error.time-zone-invalid"
        case .repeatEndInvalid: "reminder.form.error.invalid-repeat-end-date"
        case .repeatEndBeforeStart: "reminder.form.error.repeat-end-before-start"
        }
    }
}
