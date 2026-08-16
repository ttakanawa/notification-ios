import NotificationManagerDomain
import SwiftUI

struct EarlyReminderSection: View {
    @Bindable var model: ReminderFormModel

    var body: some View {
        Section {
            Picker(
                LocalizedStringResource(
                    "reminder.field.early-reminder",
                    table: "ReminderForm"
                ), selection: earlyChoiceBinding
            ) {
                ForEach(EarlyReminderChoice.allCases) { choice in
                    Text(choice.localizedResource)
                        .accessibilityIdentifier(choice.accessibilityIdentifier)
                        .tag(choice)
                }
            }
            .disabled(!model.scheduleFieldsAreEditable)
            .accessibilityIdentifier("reminder-form.early-choice")

            if let early = model.earlyReminder {
                if model.earlyReminderChoice == .custom {
                    Picker(
                        LocalizedStringResource(
                            "reminder.field.early-value",
                            table: "ReminderForm"
                        ),
                        selection: earlyAmountBinding
                    ) {
                        ForEach(model.earlyReminderAmountChoices, id: \.self) { amount in
                            Text(amount, format: .number).tag(amount)
                        }
                    }
                    .pickerStyle(.wheel)
                    .disabled(!model.scheduleFieldsAreEditable)
                    .accessibilityIdentifier("reminder-form.early-value")

                    Picker(
                        LocalizedStringResource(
                            "reminder.field.early-unit",
                            table: "ReminderForm"
                        ), selection: earlyUnitBinding
                    ) {
                        ForEach(EarlyReminderUnitChoice.allCases) { choice in
                            Text(choice.localizedResource)
                                .accessibilityIdentifier(choice.accessibilityIdentifier)
                                .tag(choice)
                        }
                    }
                    .disabled(!model.scheduleFieldsAreEditable)
                    .accessibilityIdentifier("reminder-form.early-unit")
                }

                Toggle(
                    LocalizedStringResource(
                        "reminder.field.main-notification",
                        table: "ReminderForm"
                    ), isOn: mainEnabledBinding(early)
                )
                .disabled(!model.scheduleFieldsAreEditable)
                .accessibilityIdentifier("reminder-form.main-enabled")
            }
        } header: {
            Text(
                LocalizedStringResource(
                    "reminder.form.section.early-reminder",
                    table: "ReminderForm"
                )
            )
            .background {
                AccessibilityIdentifierContainer(
                    identifier: "reminder-form.section.early-reminder"
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var earlyChoiceBinding: Binding<EarlyReminderChoice> {
        Binding(
            get: { model.earlyReminderChoice },
            set: { choice in
                model.applyEarlyReminderChoice(choice)
            }
        )
    }

    private var earlyAmountBinding: Binding<Int> {
        Binding(
            get: { model.earlyReminder?.value ?? 5 },
            set: { amount in
                model.updateEarlyReminderAmount(amount)
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

extension EarlyReminderChoice {
    fileprivate var accessibilityIdentifier: String {
        switch self {
        case .none: "reminder.early.none"
        case .thirtySeconds: "reminder.early.thirty-seconds-before"
        case .oneMinute: "reminder.early.one-minute-before"
        case .fiveMinutes: "reminder.early.five-minutes-before"
        case .custom: "reminder.early.custom"
        }
    }
}

extension EarlyReminderChoice {
    var localizedResource: LocalizedStringResource {
        switch self {
        case .none:
            LocalizedStringResource("reminder.early.none", table: "ReminderForm")
        case .thirtySeconds:
            LocalizedStringResource(
                "reminder.early.thirty-seconds-before",
                table: "ReminderForm"
            )
        case .oneMinute:
            LocalizedStringResource(
                "reminder.early.one-minute-before",
                table: "ReminderForm"
            )
        case .fiveMinutes:
            LocalizedStringResource(
                "reminder.early.five-minutes-before",
                table: "ReminderForm"
            )
        case .custom:
            LocalizedStringResource("reminder.early.custom", table: "ReminderForm")
        }
    }
}

enum EarlyReminderUnitChoice: String, CaseIterable, Identifiable {
    case seconds
    case minutes
    case hours
    case days
    case weeks

    var id: String { rawValue }

    init(_ value: EarlyReminderUnit) {
        self =
            switch value {
            case .seconds: .seconds
            case .minutes: .minutes
            case .hours: .hours
            case .days: .days
            case .weeks: .weeks
            }
    }

    var value: EarlyReminderUnit {
        switch self {
        case .seconds: .seconds
        case .minutes: .minutes
        case .hours: .hours
        case .days: .days
        case .weeks: .weeks
        }
    }

    var localizedResource: LocalizedStringResource {
        switch self {
        case .seconds:
            LocalizedStringResource("reminder.early-unit.seconds", table: "ReminderForm")
        case .minutes:
            LocalizedStringResource("reminder.early-unit.minutes", table: "ReminderForm")
        case .hours:
            LocalizedStringResource("reminder.early-unit.hours", table: "ReminderForm")
        case .days:
            LocalizedStringResource("reminder.early-unit.days", table: "ReminderForm")
        case .weeks:
            LocalizedStringResource("reminder.early-unit.weeks", table: "ReminderForm")
        }
    }

    fileprivate var accessibilityIdentifier: String {
        switch self {
        case .seconds: "reminder.early-unit.seconds"
        case .minutes: "reminder.early-unit.minutes"
        case .hours: "reminder.early-unit.hours"
        case .days: "reminder.early-unit.days"
        case .weeks: "reminder.early-unit.weeks"
        }
    }
}
