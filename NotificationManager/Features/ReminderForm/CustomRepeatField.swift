import NotificationManagerApplication
import SwiftUI

struct CustomRepeatField: View {
    @Bindable var model: ReminderFormModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(text: customTextBinding, axis: .vertical) {
                Text(
                    LocalizedStringResource(
                        "reminder.form.custom.placeholder",
                        table: "ReminderForm"
                    ))
            }
            .lineLimit(2...5)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier("reminder-form.custom.input")

            Button(
                LocalizedStringResource(
                    "reminder.form.custom.preview",
                    table: "ReminderForm"
                )
            ) {
                Task { await model.submitCustomRepeat() }
            }
            .disabled(
                model.customRepeatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            .accessibilityIdentifier("reminder-form.custom.preview-button")

            switch model.customRepeatState {
            case .idle:
                EmptyView()
            case .failed(let error):
                Label(error.localizedResource, systemImage: "exclamationmark.triangle")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reminder-form.custom.error")
            case .awaitingSuggestions(let suggestions):
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        LocalizedStringResource(
                            "reminder.form.custom.did-you-mean",
                            table: "ReminderForm"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                        Button {
                            Task { await model.selectCustomRepeatSuggestion(suggestion) }
                        } label: {
                            Text(verbatim: suggestion)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("reminder-form.custom.suggestion-\(index)")
                    }
                    Button(
                        LocalizedStringResource(
                            "reminder.form.custom.interpret-with-apple-intelligence",
                            table: "ReminderForm"
                        )
                    ) {
                        Task { await model.interpretCustomRepeatWithAppleIntelligence() }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("reminder-form.custom.assisted")
                }
            case .awaitingConfirmation(let preview):
                previewView(preview)
                Button(
                    LocalizedStringResource(
                        "reminder.form.custom.apply",
                        table: "ReminderForm"
                    )
                ) {
                    Task { await model.confirmCustomRepeat() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("reminder-form.custom.apply")
            case .confirmed(let preview):
                Label(
                    LocalizedStringResource(
                        "reminder.form.custom.applied",
                        table: "ReminderForm"
                    ), systemImage: "checkmark.circle")
                Text(verbatim: preview.canonicalEnglish)
                    .font(.caption)
            }
        }
    }

    private var customTextBinding: Binding<String> {
        Binding(
            get: { model.customRepeatText },
            set: { input in
                model.updateCustomRepeatText(input)
            }
        )
    }

    private func previewView(_ preview: CustomRepeatPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: preview.canonicalEnglish)
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("reminder-form.custom.canonical-preview")
            ForEach(
                Array(preview.nextNotifications.notifications.prefix(3).enumerated()),
                id: \.offset
            ) { _, notification in
                PhysicalNotificationPreviewView(
                    notification: notification,
                    sourceTimeZoneIdentifier: model.timeZoneIdentifier
                )
            }
        }
        .accessibilityIdentifier("reminder-form.custom.preview-result")
    }
}

extension CustomRepeatResolutionError {
    var localizedResource: LocalizedStringResource {
        switch self {
        case .assistanceUnavailable:
            LocalizedStringResource(
                "reminder.custom.error.assistance-unavailable",
                table: "ReminderForm"
            )
        case .unsupportedLanguageOrLocale:
            LocalizedStringResource(
                "reminder.custom.error.unsupported-language-or-locale",
                table: "ReminderForm"
            )
        case .safetyGuard:
            LocalizedStringResource("reminder.custom.error.safety", table: "ReminderForm")
        case .generation:
            LocalizedStringResource("reminder.custom.error.generation", table: "ReminderForm")
        case .validation:
            LocalizedStringResource("reminder.custom.error.validation", table: "ReminderForm")
        }
    }
}
