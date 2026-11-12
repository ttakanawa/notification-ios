import Foundation
import NotificationManagerDomain
import SwiftUI

struct DateTimeSection: View {
    @Bindable var model: ReminderFormModel
    @State private var isTimeZonePickerPresented = false
    @Environment(\.locale) private var locale

    var body: some View {
        Section {
            if case .readOnly(let reason) = model.scheduleAccess {
                Label(reason.localizedResource, systemImage: "lock")
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        AccessibilityIdentifierContainer(
                            identifier: "reminder-form.schedule-read-only"
                        )
                    }
            }

            if case .readOnly = model.scheduleAccess {
                unavailableValue(
                    title: LocalizedStringResource(
                        "reminder.field.date",
                        table: "ReminderForm"
                    ),
                    accessibilityIdentifier: "reminder-form.date"
                )
                unavailableValue(
                    title: LocalizedStringResource(
                        "reminder.field.time",
                        table: "ReminderForm"
                    ),
                    accessibilityIdentifier: "reminder-form.time"
                )
            } else {
                ScheduleDatePickerRow(
                    title: LocalizedStringResource(
                        "reminder.field.date",
                        table: "ReminderForm"
                    ),
                    selection: model.sourceDatePickerValue,
                    fallbackSelection: model.missingPickerDefaultValue,
                    displayedComponents: .date,
                    timeZone: model.pickerTimeZone,
                    accessibilityIdentifier: "reminder-form.date",
                    accessibilityValue: model.sourceDate.map {
                        String(format: "%04d-%02d-%02d", $0.year, $0.month, $0.day)
                    },
                    onSelect: model.updateSourceDate(from:)
                )
                ScheduleDatePickerRow(
                    title: LocalizedStringResource(
                        "reminder.field.time",
                        table: "ReminderForm"
                    ),
                    selection: model.sourceTimePickerValue,
                    fallbackSelection: model.missingPickerDefaultValue,
                    displayedComponents: .hourAndMinute,
                    timeZone: model.pickerTimeZone,
                    accessibilityIdentifier: "reminder-form.time",
                    accessibilityValue: model.sourceTime.map {
                        String(format: "%02d:%02d", $0.hour, $0.minute)
                    },
                    onSelect: model.updateSourceTime(from:)
                )
            }

            if model.scheduleFieldsAreEditable {
                Toggle(
                    isOn: Binding(
                        get: { model.liveActivityEnabled },
                        set: { model.setLiveActivityEnabled($0) }
                    )
                ) {
                    AppRowLabel(
                        title: LocalizedStringResource(
                            "reminder.field.live-activity-enabled",
                            table: "ReminderForm"
                        ),
                        systemImage: "livephoto",
                        color: .indigo
                    )
                }
                .accessibilityIdentifier("reminder-form.live-activity-enabled")

                if model.liveActivityEnabled {
                    liveActivityControls
                }
            }

            if case .readOnly = model.scheduleAccess {
                unavailableValue(
                    title: LocalizedStringResource(
                        "reminder.field.time-zone",
                        table: "ReminderForm"
                    ),
                    accessibilityIdentifier: "reminder-form.time-zone"
                )
            } else {
                LabeledContent {
                    Button {
                        isTimeZonePickerPresented = true
                    } label: {
                        if let identifier = model.timeZoneIdentifier {
                            Text(verbatim: identifier)
                                .font(.subheadline)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text(
                                LocalizedStringResource(
                                    "reminder.form.value.select",
                                    table: "ReminderForm"
                                ))
                        }
                    }
                } label: {
                    AppRowLabel(
                        title: LocalizedStringResource(
                            "reminder.field.time-zone",
                            table: "ReminderForm"
                        ),
                        systemImage: "globe",
                        color: .cyan
                    )
                }
                .accessibilityIdentifier("reminder-form.time-zone")
                .sheet(isPresented: $isTimeZonePickerPresented) {
                    TimeZonePickerView(
                        selectedIdentifier: model.timeZoneIdentifier,
                        onSelect: { identifier in
                            model.timeZoneIdentifier = identifier
                        }
                    )
                }
            }

            if let issue = model.timeZoneFieldIssue {
                Label(issue.localizedResource, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reminder-form.time-zone-error")
            }

            if case .repair(let issues) = model.scheduleAccess, !issues.isEmpty {
                Label(
                    LocalizedStringResource(
                        "reminder.form.schedule-repair-required",
                        table: "ReminderForm"
                    ), systemImage: "wrench.and.screwdriver"
                )
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("reminder-form.schedule-repair")
            }
        } header: {
            Text(
                LocalizedStringResource(
                    "reminder.form.section.date-time",
                    table: "ReminderForm"
                )
            )
            .background {
                AccessibilityIdentifierContainer(
                    identifier: "reminder-form.section.date-time"
                )
            }
        } footer: {
            if model.scheduleFieldsAreEditable && model.liveActivityEnabled {
                Text(
                    LocalizedStringResource(
                        "reminder.form.live-activity-help",
                        table: "ReminderForm"
                    )
                )
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var liveActivityControls: some View {
        Group {
            LiveActivityDurationPickerRow(
                title: LocalizedStringResource(
                    "reminder.field.live-activity-before", table: "ReminderForm"),
                minutes: model.liveActivityBeforeMinutes, valueText: liveActivityBeforeText,
                accessibilityIdentifier: "reminder-form.live-activity-before-minutes",
                onSelect: model.updateLiveActivityBeforeMinutes)

            LiveActivityDurationPickerRow(
                title: LocalizedStringResource(
                    "reminder.field.live-activity-after", table: "ReminderForm"),
                minutes: model.liveActivityAfterMinutes, valueText: liveActivityAfterText,
                accessibilityIdentifier: "reminder-form.live-activity-after-minutes",
                onSelect: model.updateLiveActivityAfterMinutes)

            if let issue = model.liveActivityWindowFieldIssue {
                Label(issue.localizedResource, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reminder-form.live-activity-error")
            }

        }
    }

    private var liveActivityBeforeText: String {
        let format = LocalizedTextProvider.live.value(
            for: "reminder.form.live-activity.minutes-before", locale: locale)
        return String(
            format: format, locale: locale, arguments: [Int64(model.liveActivityBeforeMinutes)])
    }

    private var liveActivityAfterText: String {
        let format = LocalizedTextProvider.live.value(
            for: "reminder.form.live-activity.minutes-after", locale: locale)
        return String(
            format: format, locale: locale, arguments: [Int64(model.liveActivityAfterMinutes)])
    }

    private func unavailableValue(
        title: LocalizedStringResource,
        accessibilityIdentifier: String
    ) -> some View {
        LabeledContent {
            Text(
                LocalizedStringResource(
                    "reminder.form.value.unavailable",
                    table: "ReminderForm"
                )
            )
            .foregroundStyle(.secondary)
        } label: {
            Text(title)
        }
        .background {
            AccessibilityIdentifierContainer(identifier: accessibilityIdentifier)
        }
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
