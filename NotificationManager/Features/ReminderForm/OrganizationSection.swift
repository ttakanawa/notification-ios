import SwiftUI

struct OrganizationSection: View {
    @Bindable var model: ReminderFormModel
    let tags: [ReminderTagPresentation]

    var body: some View {
        Section("reminder.form.section.organization") {
            Toggle("reminder.field.enabled", isOn: $model.enabled)
                .accessibilityIdentifier("reminder-form.enabled")

            if !tags.isEmpty {
                ForEach(tags) { tag in
                    Toggle(
                        isOn: tagBinding(tag.id)
                    ) {
                        Label {
                            Text(verbatim: tag.name)
                        } icon: {
                            Image(systemName: "tag")
                        }
                    }
                    .accessibilityIdentifier("reminder-form.tag.\(tag.id.uuidString.lowercased())")
                }
            }

            if model.canDelete {
                Button("reminder.action.delete", role: .destructive) {
                    model.requestDeleteConfirmation()
                }
                .disabled(model.saveState == .saving)
                .accessibilityIdentifier("reminder-form.delete")
            }

            if model.saveState == .failed(.save) {
                Label("reminder.form.save-failed", systemImage: "exclamationmark.triangle")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reminder-form.save-error")
            } else if model.saveState == .failed(.delete) {
                Label("reminder.form.delete-failed", systemImage: "exclamationmark.triangle")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reminder-form.delete-error")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reminder-form.section.organization")
    }

    private func tagBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { model.tagIDs.contains(id) },
            set: { selected in
                var ids = model.tagIDs
                if selected {
                    ids.insert(id)
                } else {
                    ids.remove(id)
                }
                model.tagIDs = ids
            }
        )
    }
}
