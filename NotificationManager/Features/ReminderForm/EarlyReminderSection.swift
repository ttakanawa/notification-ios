import NotificationManagerDomain
import SwiftUI

struct EarlyReminderSection: View {
    @Bindable var model: ReminderFormModel

    var body: some View {
        Section("reminder.form.section.early-reminder") {
            Picker("reminder.field.early-reminder", selection: earlyChoiceBinding) {
                ForEach(EarlyReminderChoice.allCases) { choice in
                    Text(choice.semanticKey).tag(choice)
                }
            }
                .disabled(!model.scheduleFieldsAreEditable)
                .accessibilityIdentifier("reminder-form.early-choice")

            if let early = model.earlyReminder {
                if model.earlyReminderChoice == .custom {
                    TextField("reminder.field.early-value", text: earlyValueBinding)
                        .keyboardType(.numberPad)
                        .disabled(!model.scheduleFieldsAreEditable)
                        .accessibilityIdentifier("reminder-form.early-value")

                    if !model.earlyReminderValueTextIsValid {
                        Label(
                            "reminder.form.error.invalid-early-value",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("reminder-form.early-value-error")
                    }

                    Picker("reminder.field.early-unit", selection: earlyUnitBinding) {
                        ForEach(EarlyReminderUnitChoice.allCases) { choice in
                            Text(choice.semanticKey).tag(choice)
                        }
                    }
                    .disabled(!model.scheduleFieldsAreEditable)
                    .accessibilityIdentifier("reminder-form.early-unit")
                }

                Toggle("reminder.field.main-notification", isOn: mainEnabledBinding(early))
                    .disabled(!model.scheduleFieldsAreEditable)
                    .accessibilityIdentifier("reminder-form.main-enabled")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reminder-form.section.early-reminder")
    }

    private var earlyChoiceBinding: Binding<EarlyReminderChoice> {
        Binding(
            get: { model.earlyReminderChoice },
            set: { choice in
                model.applyEarlyReminderChoice(choice)
            }
        )
    }

    private var earlyValueBinding: Binding<String> {
        Binding(
            get: { model.earlyReminderValueText },
            set: { input in
                model.updateEarlyReminderValueText(input)
            }
        )
    }

    private var earlyUnitBinding: Binding<EarlyReminderUnitChoice> {
        Binding(
            get: { EarlyReminderUnitChoice(model.earlyReminder?.unit ?? .minutes) },
            set: { choice in
                model.updateEarlyReminderUnit(choice.value)
            }
        )
    }

    private func mainEnabledBinding(_ early: EarlyReminder) -> Binding<Bool> {
        Binding(
            get: { model.earlyReminder?.mainEnabled ?? early.mainEnabled },
            set: { enabled in
                model.updateMainNotificationEnabled(enabled)
            }
        )
    }
}

private extension EarlyReminderChoice {
    var semanticKey: LocalizedStringKey {
        switch self {
        case .none: "reminder.early.none"
        case .oneMinute: "reminder.early.one-minute-before"
        case .fiveMinutes: "reminder.early.five-minutes-before"
        case .custom: "reminder.early.custom"
        }
    }
}

private enum EarlyReminderUnitChoice: String, CaseIterable, Identifiable {
    case minutes
    case hours
    case days
    case weeks

    var id: String { rawValue }

    init(_ value: EarlyReminderUnit) {
        self = switch value {
        case .minutes: .minutes
        case .hours: .hours
        case .days: .days
        case .weeks: .weeks
        }
    }

    var value: EarlyReminderUnit {
        switch self {
        case .minutes: .minutes
        case .hours: .hours
        case .days: .days
        case .weeks: .weeks
        }
    }

    var semanticKey: LocalizedStringKey {
        switch self {
        case .minutes: "reminder.early-unit.minutes"
        case .hours: "reminder.early-unit.hours"
        case .days: "reminder.early-unit.days"
        case .weeks: "reminder.early-unit.weeks"
        }
    }
}
