import NotificationManagerApplication
import SwiftUI

struct CustomRepeatField: View {
    @Bindable var model: ReminderFormModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("reminder.form.custom.placeholder", text: customTextBinding, axis: .vertical)
                .lineLimit(2...5)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("reminder-form.custom.input")

            Button("reminder.form.custom.preview") {
                Task { await model.submitCustomRepeat() }
            }
            .disabled(model.customRepeatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("reminder-form.custom.preview-button")

            switch model.customRepeatState {
            case .idle:
                EmptyView()
            case let .failed(error):
                Label(error.semanticKey, systemImage: "exclamationmark.triangle")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reminder-form.custom.error")
            case let .awaitingSuggestion(suggestion):
                VStack(alignment: .leading, spacing: 6) {
                    Text("reminder.form.custom.did-you-mean")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await model.selectCustomRepeatSuggestion() }
                    } label: {
                        Text(verbatim: suggestion)
                    }
                    .accessibilityIdentifier("reminder-form.custom.suggestion")
                }
            case let .awaitingConfirmation(preview):
                previewView(preview)
                Button("reminder.form.custom.apply") {
                    Task { await model.confirmCustomRepeat() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("reminder-form.custom.apply")
            case let .confirmed(preview):
                Label("reminder.form.custom.applied", systemImage: "checkmark.circle")
                Text(verbatim: preview.canonicalEnglish)
                    .font(.caption)
            }
        }
    }

    private var customTextBinding: Binding<String> {
        Binding(
            get: { model.customRepeatText },
            set: model.updateCustomRepeatText
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

private extension CustomRepeatResolutionError {
    var semanticKey: LocalizedStringKey {
        switch self {
        case .assistanceUnavailable: "reminder.custom.error.assistance-unavailable"
        case .safetyGuard: "reminder.custom.error.safety"
        case .generation: "reminder.custom.error.generation"
        case .validation: "reminder.custom.error.validation"
        }
    }
}
