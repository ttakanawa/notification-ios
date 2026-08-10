import SwiftUI

struct OrganizationSection: View {
    @Bindable var model: ReminderFormModel
    let tags: [ReminderTagPresentation]

    var body: some View {
        Section {
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
                Button(role: .destructive) {
                    model.requestDeleteConfirmation()
                } label: {
                    Text("reminder.action.delete")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
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
        } header: {
            Text("reminder.form.section.organization")
                .background {
                    AccessibilityIdentifierContainer(
                        identifier: "reminder-form.section.organization"
                    )
                }
        }
        .accessibilityElement(children: .contain)
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
