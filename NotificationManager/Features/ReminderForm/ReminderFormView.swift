import NotificationManagerApplication
import SwiftUI

struct ReminderFormView: View {
    @Bindable var model: ReminderFormModel
    @Bindable var router: AppRouter
    let tagModel: TagManagementModel?

    init(
        model: ReminderFormModel,
        router: AppRouter,
        tagModel: TagManagementModel? = nil
    ) {
        self.model = model
        self.router = router
        self.tagModel = tagModel
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                BasicInformationSection(model: model)
                if model.scheduleFieldsAreEditable {
                    DateTimeSection(model: model)
                    RepeatSection(model: model)
                    EarlyReminderSection(model: model)
                        .id(Self.earlyReminderScrollID)
                    organizationSection
                } else {
                    organizationSection
                    DateTimeSection(model: model)
                    RepeatSection(model: model)
                    EarlyReminderSection(model: model)
                        .id(Self.earlyReminderScrollID)
                }
                if let tagModel {
                    TagPickerView(model: tagModel, selectedTagIDs: $model.tagIDs)
                }
            }
            .onChange(of: model.earlyReminderChoice) { _, choice in
                guard choice == .custom else { return }
                withAnimation {
                    proxy.scrollTo(Self.earlyReminderScrollID, anchor: .center)
                }
            }
        }
        .navigationTitle(model.canDelete ? "reminder.form.edit.title" : "reminder.form.create.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("reminder.action.save") {
                    let reminderID = model.detachedDraft.id
                    Task {
                        await router.performReminderSave(reminderID) {
                            await model.save()
                        }
                    }
                }
                .disabled(!model.canSave)
                .accessibilityIdentifier("reminder-form.save")
            }
        }
        .sheet(isPresented: capacityConfirmationPresented) {
            if case let .requiresCapacityConfirmation(warning) = model.saveState {
                CapacityConfirmationView(
                    warning: warning,
                    onConfirm: {
                        let reminderID = model.detachedDraft.id
                        Task {
                            await router.performReminderSave(reminderID) {
                                await model.confirmCapacitySave()
                            }
                        }
                    },
                    onCancel: model.dismissPendingConfirmation
                )
                .presentationDetents([.medium])
            }
        }
        .alert(
            "reminder.form.expired-confirmation.title",
            isPresented: expiredConfirmationPresented
        ) {
            Button(role: .destructive) {
                let reminderID = model.detachedDraft.id
                guard model.consumeExpiredScheduleConfirmation() else { return }
                Task {
                    await router.performReminderSave(reminderID) {
                        await model.performConfirmedExpiredScheduleSave()
                    }
                }
            } label: {
                Text("reminder.form.expired-confirmation.confirm")
                    .accessibilityIdentifier("reminder-form.expired-confirm")
            }
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
            Button(role: .destructive, action: confirmDelete) {
                Text("reminder.form.delete-confirmation.confirm")
                    .accessibilityIdentifier("reminder-form.delete-confirm")
            }
            Button(role: .cancel, action: model.cancelDeleteConfirmation) {
                Text("reminder.action.cancel")
                    .accessibilityIdentifier("reminder-form.delete-cancel")
            }
        } message: {
            Text("reminder.form.delete-confirmation.message")
        }
        .announcesAccessibilityErrors(accessibilityErrors)
        .background {
            AccessibilityIdentifierContainer(identifier: "reminder-form.root")
        }
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

    private static let earlyReminderScrollID = "reminder-form.early-reminder.scroll-target"

    private var organizationSection: some View {
        OrganizationSection(
            model: model,
            tags: tagModel == nil ? model.availableTags : []
        )
    }

    private func confirmDelete() {
        let reminderID = model.detachedDraft.id
        guard model.consumeDeleteConfirmation() else { return }
        Task {
            await router.performReminderDeletion(reminderID) {
                await model.performConfirmedDelete()
            }
        }
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

    private var accessibilityErrors: [AccessibilityErrorIdentity] {
        var result = [
            model.titleFieldIssue?.accessibilityIdentity,
            model.notesFieldIssue?.accessibilityIdentity,
            model.urlFieldIssue?.accessibilityIdentity,
            model.sourceDateTextIsValid ? nil : .reminderDateInvalid,
            model.sourceTimeTextIsValid ? nil : .reminderTimeInvalid,
            model.timeZoneFieldIssue?.accessibilityIdentity,
            model.repeatEndDateFieldIssue?.accessibilityIdentity,
            model.earlyReminderValueTextIsValid ? nil : .reminderEarlyValueInvalid
        ].compactMap { $0 }

        if case let .failed(error) = model.customRepeatState {
            result.append(error.accessibilityIdentity)
        }
        if case let .failed(error) = model.saveState {
            result.append(error == .save ? .reminderSaveFailed : .reminderDeleteFailed)
        }
        return result
    }
}

private extension ReminderFormFieldIssue {
    var accessibilityIdentity: AccessibilityErrorIdentity {
        switch self {
        case .titleRequired: .reminderTitleRequired
        case .titleTooLarge: .reminderTitleTooLarge
        case .notesTooLarge: .reminderNotesTooLarge
        case .urlInvalid: .reminderURLInvalid
        case .urlTooLarge: .reminderURLTooLarge
        case .timeZoneRequired: .reminderTimeZoneRequired
        case .timeZoneInvalid: .reminderTimeZoneInvalid
        case .repeatEndInvalid: .reminderRepeatEndInvalid
        case .repeatEndBeforeStart: .reminderRepeatEndBeforeStart
        }
    }
}

private extension CustomRepeatResolutionError {
    var accessibilityIdentity: AccessibilityErrorIdentity {
        switch self {
        case .assistanceUnavailable: .reminderCustomAssistanceUnavailable
        case .safetyGuard: .reminderCustomSafety
        case .generation: .reminderCustomGeneration
        case .validation: .reminderCustomValidation
        }
    }
}
