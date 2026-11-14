import SwiftUI

struct DeleteReminderSection: View {
    @Bindable var model: ReminderFormModel
    let isPersistenceOperationInFlight: Bool
    let onRequestDelete: @MainActor () -> Void

    var body: some View {
        Section {
            Button(role: .destructive) {
                guard !isPersistenceOperationInFlight else { return }
                onRequestDelete()
            } label: {
                Label(
                    LocalizedStringResource(
                        "reminder.action.delete",
                        table: "Reminder"
                    ),
                    systemImage: "trash"
                )
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .foregroundStyle(.red)
            .disabled(isPersistenceOperationInFlight || model.saveState == .saving)
            .accessibilityIdentifier("reminder-form.delete")
        }
        .background {
            AccessibilityIdentifierContainer(identifier: "reminder-form.section.delete")
        }
    }
}
