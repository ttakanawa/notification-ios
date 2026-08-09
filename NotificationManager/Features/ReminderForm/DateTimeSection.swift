import NotificationManagerDomain
import SwiftUI

struct DateTimeSection: View {
    @Bindable var model: ReminderFormModel

    var body: some View {
        Section("reminder.form.section.date-time") {
            if case let .readOnly(reason) = model.scheduleAccess {
                Label(reason.semanticKey, systemImage: "lock")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reminder-form.schedule-read-only")
            }

            TextField("reminder.field.date-placeholder", text: dateBinding)
                .textContentType(.dateTime)
                .keyboardType(.numbersAndPunctuation)
                .disabled(!model.scheduleFieldsAreEditable)
                .accessibilityLabel("reminder.field.date")
                .accessibilityIdentifier("reminder-form.date")

            if !model.sourceDateTextIsValid {
                Label("reminder.form.error.invalid-date", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reminder-form.date-error")
            }

            TextField("reminder.field.time-placeholder", text: timeBinding)
                .textContentType(.dateTime)
                .keyboardType(.numbersAndPunctuation)
                .disabled(!model.scheduleFieldsAreEditable)
                .accessibilityLabel("reminder.field.time")
                .accessibilityIdentifier("reminder-form.time")

            if !model.sourceTimeTextIsValid {
                Label("reminder.form.error.invalid-time", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reminder-form.time-error")
            }

            TextField("reminder.field.time-zone-placeholder", text: timeZoneBinding)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(!model.scheduleFieldsAreEditable)
                .accessibilityLabel("reminder.field.time-zone")
                .accessibilityIdentifier("reminder-form.time-zone")

            if let issue = model.timeZoneFieldIssue {
                Label(issue.semanticKey, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reminder-form.time-zone-error")
            }

            if case let .repair(issues) = model.scheduleAccess, !issues.isEmpty {
                Label("reminder.form.schedule-repair-required", systemImage: "wrench.and.screwdriver")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reminder-form.schedule-repair")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reminder-form.section.date-time")
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

private extension ReminderFormReadOnlyReason {
    var semanticKey: LocalizedStringKey {
        switch self {
        case .updateRequired: "reminder.form.schedule-update-required"
        case .invalidSchedule: "reminder.form.schedule-corrupt"
        }
    }
}
