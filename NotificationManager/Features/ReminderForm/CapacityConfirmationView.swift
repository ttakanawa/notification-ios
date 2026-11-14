import NotificationManagerApplication
import SwiftUI

struct CapacityConfirmationView: View {
    let warning: CapacityWarning
    let isPersistenceOperationInFlight: Bool
    let onConfirm: @MainActor () -> Void
    let onCancel: @MainActor () -> Void

    @Environment(\.locale) private var locale

    init(
        warning: CapacityWarning,
        isPersistenceOperationInFlight: Bool = false,
        onConfirm: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        self.warning = warning
        self.isPersistenceOperationInFlight = isPersistenceOperationInFlight
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .center, spacing: 20) {
                    Image(systemName: "tray.full.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                        .padding(16)
                        .background(.orange.opacity(0.12), in: .circle)
                        .accessibilityHidden(true)

                    Text(
                        LocalizedStringResource(
                            "reminder.form.capacity-confirmation.title",
                            table: "ReminderForm"
                        )
                    )
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                    Text(verbatim: capacityMessage)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                }
                .frame(maxWidth: .infinity)
                .padding(24)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                confirmationActions
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(.bar)
            }
            .background {
                AccessibilityIdentifierContainer(
                    identifier: "reminder-form.capacity-confirmation"
                )
            }
        }
    }

    private var confirmationActions: some View {
        VStack(spacing: 8) {
            Button {
                onConfirm()
            } label: {
                Text(
                    LocalizedStringResource(
                        "reminder.form.capacity-confirmation.confirm",
                        table: "ReminderForm"
                    )
                )
                .frame(maxWidth: .infinity, minHeight: 24)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isPersistenceOperationInFlight)
            .accessibilityIdentifier("reminder-form.capacity-confirm")

            Button(role: .cancel) {
                onCancel()
            } label: {
                Text(
                    LocalizedStringResource(
                        "reminder.action.cancel",
                        table: "Reminder"
                    )
                )
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(isPersistenceOperationInFlight)
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
