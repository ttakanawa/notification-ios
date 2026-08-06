import SwiftUI

struct ReminderFormView: View {
    @Bindable var model: ReminderFormModel
    @Bindable var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            BasicInformationSection(model: model)
            DateTimeSection(model: model)
            RepeatSection(model: model)
            EarlyReminderSection(model: model)
            OrganizationSection(model: model, tags: model.availableTags)
        }
        .navigationTitle(model.canDelete ? "reminder.form.edit.title" : "reminder.form.create.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("reminder.action.save") {
                    Task { await model.save() }
                }
                .disabled(!model.canSave)
                .accessibilityIdentifier("reminder-form.save")
            }
        }
        .sheet(isPresented: capacityConfirmationPresented) {
            if case let .requiresCapacityConfirmation(warning) = model.saveState {
                CapacityConfirmationView(
                    warning: warning,
                    onConfirm: { Task { await model.confirmCapacitySave() } },
                    onCancel: model.dismissPendingConfirmation
                )
                .presentationDetents([.medium])
            }
        }
        .alert(
            "reminder.form.expired-confirmation.title",
            isPresented: expiredConfirmationPresented
        ) {
            Button("reminder.form.expired-confirmation.confirm", role: .destructive) {
                Task { await model.confirmExpiredSave() }
            }
            .accessibilityIdentifier("reminder-form.expired-confirm")
            Button("reminder.action.cancel", role: .cancel) {
                model.dismissPendingConfirmation()
            }
        } message: {
            Text("reminder.form.expired-confirmation.message")
        }
        .alert(
            "reminder.form.delete-confirmation.title",
            isPresented: deleteConfirmationPresented
        ) {
            Button("reminder.form.delete-confirmation.confirm", role: .destructive) {
                let reminderID = model.detachedDraft.id
                guard model.consumeDeleteConfirmation() else { return }
                Task {
                    await router.performReminderDeletion(reminderID) {
                        await model.performConfirmedDelete()
                    }
                }
            }
            .accessibilityIdentifier("reminder-form.delete-confirm")
            Button("reminder.action.cancel", role: .cancel) {
                model.cancelDeleteConfirmation()
            }
            .accessibilityIdentifier("reminder-form.delete-cancel")
        } message: {
            Text("reminder.form.delete-confirmation.message")
        }
        .onChange(of: model.saveState) { _, state in
            if case .saved = state { dismiss() }
        }
        .accessibilityIdentifier("reminder-form.root")
    }

    private var capacityConfirmationPresented: Binding<Bool> {
        Binding(
            get: {
                if case .requiresCapacityConfirmation = model.saveState { true } else { false }
            },
            set: { presented in
                if !presented, case .requiresCapacityConfirmation = model.saveState {
                    model.dismissPendingConfirmation()
                }
            }
        )
    }

    private var expiredConfirmationPresented: Binding<Bool> {
        Binding(
            get: {
                if case .requiresExpiredScheduleConfirmation = model.saveState { true } else { false }
            },
            set: { presented in
                if !presented, case .requiresExpiredScheduleConfirmation = model.saveState {
                    model.dismissPendingConfirmation()
                }
            }
        )
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { model.isDeleteConfirmationPresented },
            set: { presented in
                if !presented { model.cancelDeleteConfirmation() }
            }
        )
    }
}
