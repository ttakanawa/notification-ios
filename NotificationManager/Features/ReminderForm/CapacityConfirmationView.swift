import NotificationManagerApplication
import SwiftUI

struct CapacityConfirmationView: View {
    let warning: CapacityWarning
    let onConfirm: @MainActor () -> Void
    let onCancel: @MainActor () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Label(LocalizedStringResource(
                    "reminder.form.capacity-confirmation.title",
                    table: "ReminderForm"
                ), systemImage: "tray.full")
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Text(verbatim: capacityMessage)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Button(LocalizedStringResource(
                    "reminder.form.capacity-confirmation.confirm",
                    table: "ReminderForm"
                )) {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("reminder-form.capacity-confirm")

                Button(LocalizedStringResource(
                    "reminder.action.cancel",
                    table: "Reminder"
                ), role: .cancel) {
                    onCancel()
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .background {
                AccessibilityIdentifierContainer(
                    identifier: "reminder-form.capacity-confirmation"
                )
            }
        }
    }

    private var capacityMessage: String {
        let format = LocalizedTextProvider.live.value(
            for: "reminder.form.capacity-confirmation.message",
            locale: locale
        )
        return String(
            format: format,
            locale: locale,
            arguments: [Int64(warning.planningCapacity)]
        )
    }
}
