import Foundation
import NotificationManagerDomain
import SwiftUI

struct RepeatSection: View {
    @Bindable var model: ReminderFormModel

    var body: some View {
        Section("reminder.form.section.repeat") {
            if let summary = model.currentLocalizedRepeatSummary {
                LabeledContent("reminder.form.repeat.current-value") {
                    Text(verbatim: summary)
                }
                .accessibilityIdentifier("reminder-form.custom.current-summary")

                if let disclosure = model.canonicalEnglishDisclosure {
                    DisclosureGroup("reminder.form.custom.canonical-disclosure") {
                        Text(verbatim: disclosure)
                            .textSelection(.enabled)
                    }
                }
            }

            Picker("reminder.field.repeat", selection: repeatPresetBinding) {
                ForEach(RepeatChoice.allCases) { choice in
                    Text(choice.semanticKey).tag(choice)
                        .disabled(choice.requiresSourceDate && model.sourceDate == nil)
                }
            }
            .disabled(!model.scheduleFieldsAreEditable)
            .accessibilityIdentifier("reminder-form.repeat-picker")

            if model.currentRepeatWasCustom && !model.isReplacingCustomRepeat {
                Button("reminder.form.custom.replace") {
                    model.beginCustomReplacement()
                }
                .disabled(!model.scheduleFieldsAreEditable)
                .accessibilityIdentifier("reminder-form.custom.replace")
            }

            if model.isReplacingCustomRepeat {
                CustomRepeatField(model: model)
            }

            if model.repeatRule != .none {
                Picker("reminder.field.repeat-end", selection: repeatEndBinding) {
                    Text("reminder.repeat-end.never").tag(false)
                    Text("reminder.repeat-end.on-date").tag(true)
                }
                .disabled(!model.scheduleFieldsAreEditable)
                .accessibilityIdentifier("reminder-form.repeat-end-picker")

                if model.repeatEndsOnDate {
                    TextField("reminder.field.date-placeholder", text: repeatEndDateBinding)
                        .keyboardType(.numbersAndPunctuation)
                        .disabled(!model.scheduleFieldsAreEditable)
                        .accessibilityLabel("reminder.field.repeat-end-date")
                        .accessibilityIdentifier("reminder-form.repeat-end-date")

                    if let issue = model.repeatEndDateFieldIssue {
                        Label(
                            issue.semanticKey,
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("reminder-form.repeat-end-date-error")
                    }
                }
            }

            if !model.previewNotifications.isEmpty && !model.isReplacingCustomRepeat {
                VStack(alignment: .leading, spacing: 8) {
                    Text("reminder.form.next-notifications")
                        .font(.headline)
                    ForEach(Array(model.previewNotifications.prefix(3).enumerated()), id: \.offset) {
                        _, notification in
                        PhysicalNotificationPreviewView(
                            notification: notification,
                            sourceTimeZoneIdentifier: model.timeZoneIdentifier
                        )
                    }
                }
                .accessibilityIdentifier("reminder-form.preview")
            }

            if model.showsPastEarlyWarning {
                Label(
                    "reminder.form.early-already-passed",
                    systemImage: "exclamationmark.triangle"
                )
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("reminder-form.early-past-warning")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reminder-form.section.repeat")
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

    private var repeatEndDateBinding: Binding<String> {
        Binding(
            get: { model.repeatEndDateText },
            set: { input in
                model.updateRepeatEndDateText(input)
            }
        )
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
                        Label(reason.kind.semanticKey, systemImage: "bell")
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
                        Text("reminder.next.primary-reason")
                    } else {
                        Text("reminder.next.secondary-reason")
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
                LabeledContent("reminder.next.source-time") {
                    Text(
                        verbatim: sourceFormatter.instant(
                            notification.alertInstant,
                            timeZoneIdentifier: sourceTimeZone.identifier,
                            locale: locale
                        )
                    )
                }
                Text(verbatim: sourceTimeZoneIdentifier ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("reminder.next.device-time") {
                Text(notification.alertInstant, format: .dateTime)
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
        self = switch rule {
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
        case let .weekly(interval: 1, weekdaySetKind: .explicit, weekdays)
            where weekdays.count == 1:
            .weekly
        case let .weekly(interval: 2, weekdaySetKind: .explicit, weekdays)
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

    var semanticKey: LocalizedStringKey {
        switch self {
        case .doesNotRepeat: "reminder.repeat.none"
        case .hourly: "reminder.repeat.hourly"
        case .daily: "reminder.repeat.daily"
        case .weekdays: "reminder.repeat.weekdays"
        case .weekends: "reminder.repeat.weekends"
        case .weekly: "reminder.repeat.weekly"
        case .biweekly: "reminder.repeat.biweekly"
        case .monthly: "reminder.repeat.monthly"
        case .every3Months: "reminder.repeat.every-3-months"
        case .every6Months: "reminder.repeat.every-6-months"
        case .yearly: "reminder.repeat.yearly"
        case .custom: "reminder.repeat.custom"
        }
    }

    var requiresSourceDate: Bool {
        self == .weekly || self == .biweekly
    }
}
