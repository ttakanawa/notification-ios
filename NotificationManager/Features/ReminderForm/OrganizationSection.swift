import SwiftUI

struct OrganizationSection: View {
    @Bindable var model: ReminderFormModel
    let tags: [ReminderTagPresentation]

    var body: some View {
        Section {
            Toggle(isOn: $model.enabled) {
                Text(
                    LocalizedStringResource(
                        "reminder.field.enabled",
                        table: "ReminderForm"
                    ))
            }
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

            if model.saveState == .failed(.save) {
                Label(
                    LocalizedStringResource(
                        "reminder.form.save-failed",
                        table: "ReminderForm"
                    ),
                    systemImage: "exclamationmark.triangle"
                )
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("reminder-form.save-error")
            } else if model.saveState == .failed(.delete) {
                Label(
                    LocalizedStringResource(
                        "reminder.form.delete-failed",
                        table: "ReminderForm"
                    ),
                    systemImage: "exclamationmark.triangle"
                )
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("reminder-form.delete-error")
            }
        } header: {
            Text(
                LocalizedStringResource(
                    "reminder.form.section.organization",
                    table: "ReminderForm"
                )
            )
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
