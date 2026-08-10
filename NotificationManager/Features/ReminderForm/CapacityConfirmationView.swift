import NotificationManagerApplication
import SwiftUI

struct CapacityConfirmationView: View {
    let warning: CapacityWarning
    let onConfirm: @MainActor () -> Void
    let onCancel: @MainActor () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Label("reminder.form.capacity-confirmation.title", systemImage: "tray.full")
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Text("reminder.form.capacity-confirmation.message \(warning.planningCapacity)")
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Button("reminder.form.capacity-confirmation.confirm") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("reminder-form.capacity-confirm")

                Button("reminder.action.cancel", role: .cancel) {
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
}
