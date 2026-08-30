import NotificationManagerApplication
import SwiftUI

struct CustomRepeatField: View {
    @Environment(\.scenePhase) private var scenePhase
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

            Label {
                Text(model.customRepeatAppleIntelligenceStatus.localizedResource)
                    .accessibilityIdentifier(
                        "reminder-form.custom.apple-intelligence-status"
                    )
            } icon: {
                if model.isInterpretingWithAppleIntelligence {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityIdentifier("reminder-form.custom.apple-intelligence-progress")
                } else {
                    Image(systemName: "apple.intelligence")
                        .accessibilityIdentifier(
                            "reminder-form.custom.apple-intelligence-icon"
                        )
                }
            }
            .font(.caption)
            .foregroundStyle(appleIntelligenceStatusColor)
            .fixedSize(horizontal: false, vertical: true)

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
                    || model.isInterpretingWithAppleIntelligence
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
                    .disabled(model.isInterpretingWithAppleIntelligence)
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
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.refreshCustomRepeatAppleIntelligenceStatus()
        }
    }

    private var appleIntelligenceStatusColor: Color {
        model.customRepeatAppleIntelligenceStatus == .available
            ? .accentColor
            : .secondary
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
        }
        .accessibilityIdentifier("reminder-form.custom.preview-result")
    }
}

extension CustomRepeatAppleIntelligenceStatus {
    var localizedResource: LocalizedStringResource {
        switch self {
        case .checking:
            LocalizedStringResource(
                "reminder.form.custom.apple-intelligence.checking",
                table: "ReminderForm"
            )
        case .available:
            LocalizedStringResource(
                "reminder.form.custom.apple-intelligence.available",
                table: "ReminderForm"
            )
        case .unavailable(.platformUnsupported):
            LocalizedStringResource(
                "reminder.form.custom.apple-intelligence.platform-unsupported",
                table: "ReminderForm"
            )
        case .unavailable(.deviceNotEligible):
            LocalizedStringResource(
                "reminder.form.custom.apple-intelligence.device-not-eligible",
                table: "ReminderForm"
            )
        case .unavailable(.appleIntelligenceNotEnabled):
            LocalizedStringResource(
                "reminder.form.custom.apple-intelligence.not-enabled",
                table: "ReminderForm"
            )
        case .unavailable(.modelNotReady):
            LocalizedStringResource(
                "reminder.form.custom.apple-intelligence.model-not-ready",
                table: "ReminderForm"
            )
        }
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
