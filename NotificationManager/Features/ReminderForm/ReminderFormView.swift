import NotificationManagerApplication
import SwiftUI

struct ReminderFormView: View {
    @Bindable var model: ReminderFormModel
    @Bindable var router: AppRouter
    @Bindable var confirmations: ReminderFormConfirmationCoordinator
    let tagModel: TagManagementModel?

    init(
        model: ReminderFormModel,
        router: AppRouter,
        confirmations: ReminderFormConfirmationCoordinator,
        tagModel: TagManagementModel? = nil
    ) {
        self.model = model
        self.router = router
        self.confirmations = confirmations
        self.tagModel = tagModel
    }

    var body: some View {
        reminderForm
            .navigationTitle(
                Text(
                    LocalizedStringResource(
                        model.canDelete ? "reminder.form.edit.title" : "reminder.form.create.title",
                        table: "ReminderForm"
                    ))
            )
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(model.canDelete)
            .toolbar {
                formToolbar
            }
            .announcesAccessibilityErrors(accessibilityErrors)
            .background {
                AccessibilityIdentifierContainer(identifier: "reminder-form.root")
            }
    }

    private var reminderForm: some View {
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
                    TagPickerView(
                        model: tagModel,
                        selectedTagIDs: $model.tagIDs,
                        reminderID: model.canDelete ? model.detachedDraft.id : nil,
                        isInteractionDisabled: isFormMutationInFlight,
                        onCommittedRemoval: { model.commitTagRemoval($0) }
                    )
                }
                if model.canDelete {
                    DeleteReminderSection(
                        model: model,
                        isPersistenceOperationInFlight: isFormMutationInFlight,
                        onRequestDelete: requestDelete
                    )
                }
            }
            .onChange(of: model.earlyReminderChoice) { _, choice in
                guard choice == .custom else { return }
                withAnimation {
                    proxy.scrollTo(Self.earlyReminderScrollID, anchor: .center)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var formToolbar: some ToolbarContent {
        if model.canDelete {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: attemptDismiss) {
                    Label {
                        Text(
                            LocalizedStringResource(
                                "reminder.action.back",
                                table: "Reminder"
                            ))
                    } icon: {
                        Image(systemName: "chevron.backward")
                    }
                }
                .disabled(isFormMutationInFlight)
                .accessibilityIdentifier("reminder-form.back")
            }
            if model.hasChanges {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        Image(systemName: "checkmark")
                    }
                    .disabled(isFormMutationInFlight || !model.canSave)
                    .accessibilityLabel(
                        Text(
                            LocalizedStringResource(
                                "reminder.action.save",
                                table: "Reminder"
                            ))
                    )
                    .accessibilityIdentifier("reminder-form.save")
                }
            }
        } else {
            ToolbarItem(placement: .confirmationAction) {
                Button(
                    LocalizedStringResource(
                        "reminder.action.save",
                        table: "Reminder"
                    ), action: save
                )
                .disabled(isFormMutationInFlight || !model.canSave)
                .accessibilityIdentifier("reminder-form.save")
            }
        }
    }

    private static let earlyReminderScrollID = "reminder-form.early-reminder.scroll-target"

    private var organizationSection: some View {
        OrganizationSection(
            model: model,
            tags: tagModel == nil ? model.availableTags : []
        )
    }

    private var isFormMutationInFlight: Bool {
        confirmations.isPersistenceOperationInFlight
            || model.saveState == .saving
            || tagModel?.isWorking == true
    }

    private func save() {
        guard !isFormMutationInFlight else { return }
        confirmations.save(model: model, router: router)
    }

    private func attemptDismiss() {
        guard !isFormMutationInFlight else { return }
        if model.hasChanges {
            confirmations.requestDiscard(model: model, router: router)
        } else {
            model.discardChanges()
            router.dismissReminder(model.detachedDraft.id)
        }
    }

    private func requestDelete() {
        guard !isFormMutationInFlight else { return }
        confirmations.requestDelete(model: model, router: router)
    }

    private var accessibilityErrors: [AccessibilityErrorIdentity] {
        var result = [
            model.titleFieldIssue?.accessibilityIdentity,
            model.notesFieldIssue?.accessibilityIdentity,
            model.urlFieldIssue?.accessibilityIdentity,
            model.timeZoneFieldIssue?.accessibilityIdentity,
            model.repeatEndDateFieldIssue?.accessibilityIdentity
        ].compactMap { $0 }

        if case .failed(let error) = model.customRepeatState {
            result.append(error.accessibilityIdentity)
        }
        if case .failed(let error) = model.saveState {
            result.append(error == .save ? .reminderSaveFailed : .reminderDeleteFailed)
        }
        return result
    }
}

extension ReminderFormFieldIssue {
    fileprivate var accessibilityIdentity: AccessibilityErrorIdentity {
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

extension CustomRepeatResolutionError {
    fileprivate var accessibilityIdentity: AccessibilityErrorIdentity {
        switch self {
        case .assistanceUnavailable: .reminderCustomAssistanceUnavailable
        case .unsupportedLanguageOrLocale: .reminderCustomUnsupportedLanguageLocale
        case .safetyGuard: .reminderCustomSafety
        case .generation: .reminderCustomGeneration
        case .validation: .reminderCustomValidation
        }
    }
}
