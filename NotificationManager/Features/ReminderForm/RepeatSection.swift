import Foundation
import NotificationManagerDomain
import SwiftUI

struct RepeatSection: View {
    @Bindable var model: ReminderFormModel

    var body: some View {
        Section {
            if let summary = model.currentLocalizedRepeatSummary {
                LabeledContent {
                    Text(verbatim: summary)
                } label: {
                    Text(
                        LocalizedStringResource(
                            "reminder.form.repeat.current-value",
                            table: "ReminderForm"
                        ))
                }
                .background {
                    AccessibilityIdentifierContainer(
                        identifier: "reminder-form.custom.current-summary"
                    )
                }

                if let disclosure = model.canonicalEnglishDisclosure {
                    DisclosureGroup {
                        Text(verbatim: disclosure)
                            .textSelection(.enabled)
                    } label: {
                        Text(
                            LocalizedStringResource(
                                "reminder.form.custom.canonical-disclosure",
                                table: "ReminderForm"
                            ))
                    }
                }
            }

            Picker(selection: repeatPresetBinding) {
                ForEach(RepeatChoice.allCases) { choice in
                    Text(choice.localizedResource).tag(choice)
                        .disabled(choice.requiresSourceDate && model.sourceDate == nil)
                }
            } label: {
                Text(
                    LocalizedStringResource(
                        "reminder.field.repeat",
                        table: "ReminderForm"
                    ))
            }
            .disabled(!model.scheduleFieldsAreEditable)
            .accessibilityIdentifier("reminder-form.repeat-picker")

            if model.currentRepeatWasCustom && !model.isReplacingCustomRepeat {
                Button {
                    model.beginCustomReplacement()
                } label: {
                    Text(
                        LocalizedStringResource(
                            "reminder.form.custom.replace",
                            table: "ReminderForm"
                        ))
                }
                .disabled(!model.scheduleFieldsAreEditable)
                .accessibilityIdentifier("reminder-form.custom.replace")
            }

            if model.isReplacingCustomRepeat {
                CustomRepeatField(model: model)
            }

            if model.repeatRule != .none {
                Picker(selection: repeatEndBinding) {
                    Text(
                        LocalizedStringResource(
                            "reminder.repeat-end.never",
                            table: "ReminderForm"
                        )
                    ).tag(false)
                    Text(
                        LocalizedStringResource(
                            "reminder.repeat-end.on-date",
                            table: "ReminderForm"
                        )
                    ).tag(true)
                } label: {
                    Text(
                        LocalizedStringResource(
                            "reminder.field.repeat-end",
                            table: "ReminderForm"
                        ))
                }
                .disabled(!model.scheduleFieldsAreEditable)
                .accessibilityIdentifier("reminder-form.repeat-end-picker")

                if model.repeatEndsOnDate {
                    ScheduleDatePickerRow(
                        title: LocalizedStringResource(
                            "reminder.field.repeat-end-date",
                            table: "ReminderForm"
                        ),
                        selection: model.repeatEndDatePickerValue,
                        fallbackSelection: model.sourceDatePickerValue
                            ?? model.missingPickerDefaultValue,
                        displayedComponents: .date,
                        timeZone: model.pickerTimeZone,
                        accessibilityIdentifier: "reminder-form.repeat-end-date",
                        accessibilityValue: repeatEndDateAccessibilityValue,
                        onSelect: model.updateRepeatEndDate
                    )
                    .disabled(!model.scheduleFieldsAreEditable)

                    if let issue = model.repeatEndDateFieldIssue {
                        Label(
                            issue.localizedResource,
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("reminder-form.repeat-end-date-error")
                    }
                }
            }

            if model.showsPastEarlyWarning {
                Label(
                    LocalizedStringResource(
                        "reminder.form.early-already-passed",
                        table: "ReminderForm"
                    ),
                    systemImage: "exclamationmark.triangle"
                )
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("reminder-form.early-past-warning")
            }
        } header: {
            Text(
                LocalizedStringResource(
                    "reminder.form.section.repeat",
                    table: "ReminderForm"
                )
            )
            .background {
                AccessibilityIdentifierContainer(
                    identifier: "reminder-form.section.repeat"
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var repeatPresetBinding: Binding<RepeatChoice> {
        Binding(
            get: {
                RepeatChoice(
                    rule: model.repeatRule,
                    custom: model.currentRepeatWasCustom
                        || model.isReplacingCustomRepeat
                )
            },
            set: { choice in
                if let preset = choice.preset {
                    model.applyRepeatPreset(preset)
                } else {
                    model.beginCustomReplacement()
                }
            }
        )
    }

    private var repeatEndBinding: Binding<Bool> {
        Binding(
            get: { model.repeatEndsOnDate },
            set: { enabled in
                model.setRepeatEndsOnDate(enabled)
            }
        )
    }

    private var repeatEndDateAccessibilityValue: String? {
        guard case .onDate(let value) = model.repeatEnd else { return nil }
        return String(format: "%04d-%02d-%02d", value.year, value.month, value.day)
    }

}

struct PhysicalNotificationPreviewView: View {
    @Environment(\.locale) private var locale
    let notification: PhysicalNotification
    let sourceTimeZoneIdentifier: String?

    private let sourceFormatter = SourceDateTimePresentationFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(notification.alertInstant, format: .dateTime)
            } icon: {
                Image(systemName: notification.primaryReason.kind == .main ? "bell" : "bell.badge")
            }
            .font(.subheadline.weight(.semibold))

            ForEach(Array(notification.reasons.enumerated()), id: \.offset) { index, reason in
                LabeledContent {
                    VStack(alignment: .trailing, spacing: 2) {
                        let reasonResource: LocalizedStringResource =
                            switch reason.kind {
                            case .main:
                                LocalizedStringResource(
                                    "reminder.reason.main",
                                    table: "Reminder"
                                )
                            case .early:
                                LocalizedStringResource(
                                    "reminder.reason.early",
                                    table: "Reminder"
                                )
                            }
                        Label(reasonResource, systemImage: "bell")
                        Text(
                            verbatim: sourceFormatter.instant(
                                reason.baseOccurrence.instant,
                                timeZoneIdentifier: effectiveSourceTimeZoneIdentifier,
                                locale: locale
                            )
                        )
                    }
                } label: {
                    if index == 0 {
                        Text(
                            LocalizedStringResource(
                                "reminder.next.primary-reason",
                                table: "Reminder"
                            ))
                    } else {
                        Text(
                            LocalizedStringResource(
                                "reminder.next.secondary-reason",
                                table: "Reminder"
                            ))
                    }
                }
                .font(.caption)
                .accessibilityIdentifier(
                    index == 0
                        ? "reminder-form.preview.primary-reason"
                        : "reminder-form.preview.secondary-reason"
                )
            }

            if let sourceTimeZone {
                LabeledContent {
                    Text(
                        verbatim: sourceFormatter.instant(
                            notification.alertInstant,
                            timeZoneIdentifier: sourceTimeZone.identifier,
                            locale: locale
                        )
                    )
                } label: {
                    Text(
                        LocalizedStringResource(
                            "reminder.next.source-time",
                            table: "Reminder"
                        ))
                }
                Text(verbatim: sourceTimeZoneIdentifier ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            LabeledContent {
                Text(notification.alertInstant, format: .dateTime)
            } label: {
                Text(
                    LocalizedStringResource(
                        "reminder.next.device-time",
                        table: "Reminder"
                    ))
            }

        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reminder-form.preview-notification")
    }

    private var sourceTimeZone: TimeZone? {
        sourceTimeZoneIdentifier.flatMap(TimeZone.init(identifier:))
    }

    private var effectiveSourceTimeZoneIdentifier: String {
        sourceTimeZoneIdentifier ?? TimeZone.current.identifier
    }
}

private enum RepeatChoice: String, CaseIterable, Identifiable {
    case doesNotRepeat
    case hourly
    case daily
    case weekdays
    case weekends
    case weekly
    case biweekly
    case monthly
    case every3Months
    case every6Months
    case yearly
    case custom

    var id: String { rawValue }

    init(rule: RepeatRule, custom: Bool) {
        if custom {
            self = .custom
            return
        }
        self =
            switch rule {
            case .none: .doesNotRepeat
            case .hourly(interval: 1): .hourly
            case .daily(interval: 1): .daily
            case .weekly(
                interval: 1,
                weekdaySetKind: .weekday,
                weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday]
            ): .weekdays
            case .weekly(
                interval: 1,
                weekdaySetKind: .weekend,
                weekdays: [.saturday, .sunday]
            ): .weekends
            case .weekly(interval: 1, weekdaySetKind: .explicit, let weekdays)
            where weekdays.count == 1:
                .weekly
            case .weekly(interval: 2, weekdaySetKind: .explicit, let weekdays)
            where weekdays.count == 1:
                .biweekly
            case .monthly(interval: 1, selector: .anchorDay): .monthly
            case .monthly(interval: 3, selector: .anchorDay): .every3Months
            case .monthly(interval: 6, selector: .anchorDay): .every6Months
            case .yearly(interval: 1, month: nil, selector: .anchorMonthDay): .yearly
            default: .custom
            }
    }

    var preset: NotificationManagerDomain.RepeatPreset? {
        switch self {
        case .doesNotRepeat: .doesNotRepeat
        case .hourly: .hourly
        case .daily: .daily
        case .weekdays: .weekdays
        case .weekends: .weekends
        case .weekly: .weekly
        case .biweekly: .biweekly
        case .monthly: .monthly
        case .every3Months: .every3Months
        case .every6Months: .every6Months
        case .yearly: .yearly
        case .custom: nil
        }
    }

    var localizedResource: LocalizedStringResource {
        switch self {
        case .doesNotRepeat:
            LocalizedStringResource("reminder.repeat.none", table: "ReminderForm")
        case .hourly:
            LocalizedStringResource("reminder.repeat.hourly", table: "ReminderForm")
        case .daily:
            LocalizedStringResource("reminder.repeat.daily", table: "ReminderForm")
        case .weekdays:
            LocalizedStringResource("reminder.repeat.weekdays", table: "ReminderForm")
        case .weekends:
            LocalizedStringResource("reminder.repeat.weekends", table: "ReminderForm")
        case .weekly:
            LocalizedStringResource("reminder.repeat.weekly", table: "ReminderForm")
        case .biweekly:
            LocalizedStringResource("reminder.repeat.biweekly", table: "ReminderForm")
        case .monthly:
            LocalizedStringResource("reminder.repeat.monthly", table: "ReminderForm")
        case .every3Months:
            LocalizedStringResource("reminder.repeat.every-3-months", table: "ReminderForm")
        case .every6Months:
            LocalizedStringResource("reminder.repeat.every-6-months", table: "ReminderForm")
        case .yearly:
            LocalizedStringResource("reminder.repeat.yearly", table: "ReminderForm")
        case .custom:
            LocalizedStringResource("reminder.repeat.custom", table: "ReminderForm")
        }
    }

    var requiresSourceDate: Bool {
        self == .weekly || self == .biweekly
    }
}
