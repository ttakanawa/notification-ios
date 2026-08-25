import NotificationManagerDomain
import SwiftUI

struct TagPickerView: View {
    @Bindable var model: TagManagementModel
    @Binding var selectedTagIDs: Set<UUID>
    let reminderID: UUID?
    let isInteractionDisabled: Bool
    let onCommittedRemoval: (UUID) -> Void

    @Environment(\.locale) private var locale
    @State private var newName = ""

    private var suggestions: TagPickerSuggestionState {
        TagPickerSuggestionState(tags: model.tags, query: newName)
    }

    var body: some View {
        Section(
            LocalizedStringResource(
                "tags.picker.title",
                table: "Tags"
            )
        ) {
            TextField(
                LocalizedStringResource(
                    "tags.field.name",
                    table: "Tags"
                ), text: $newName, prompt: nil
            )
            .submitLabel(.done)
            .onSubmit(submitSuggestion)
            .accessibilityIdentifier("tags.picker.new-name")

            ForEach(suggestions.matches, id: \.id) { tag in
                let isSelected = selectedTagIDs.contains(tag.id)
                Button {
                    if isSelected {
                        remove(tagID: tag.id)
                    } else {
                        select(tagID: tag.id)
                    }
                } label: {
                    HStack {
                        Label {
                            Text(verbatim: tag.name)
                        } icon: {
                            Image(systemName: "tag")
                        }
                        .foregroundStyle(.primary)

                        Spacer()

                        Image(
                            systemName: isSelected
                                ? "minus.circle.fill"
                                : "plus.circle"
                        )
                        .foregroundStyle(isSelected ? Color.red : Color.accentColor)
                        .imageScale(.large)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.isWorking || isInteractionDisabled)
                .accessibilityLabel(
                    Text(verbatim: actionText(for: tag, isSelected: isSelected))
                )
                .accessibilityIdentifier("tags.picker.tag.\(tag.id.uuidString.lowercased())")
            }

            if let creationName = suggestions.creationName {
                Button {
                    createAndSelect(name: creationName)
                } label: {
                    Label(
                        createSuggestionText(name: creationName),
                        systemImage: "plus.circle"
                    )
                }
                .disabled(model.isWorking)
                .accessibilityIdentifier("tags.picker.create-suggestion")
            }

            if let error = model.actionError {
                Label(
                    error.localizedResource,
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("tags.picker.error")
            }
        }
        .task {
            let outcome = await model.load()
            reconcileSelection(after: outcome)
        }
        .announcesAccessibilityErrors(
            model.actionError.map { [$0.accessibilityIdentity] } ?? []
        )
    }

    private func select(tagID: UUID) {
        let wasSelected = selectedTagIDs.contains(tagID)
        selectedTagIDs = TagPickerSelection.selecting(tagID, in: selectedTagIDs)
        if !wasSelected {
            newName = ""
        }
    }

    private func remove(tagID: UUID) {
        Task {
            guard
                await model.removeAssociation(
                    tagID: tagID,
                    from: reminderID
                ) != nil
            else { return }
            onCommittedRemoval(tagID)
        }
    }

    private func submitSuggestion() {
        if let creationName = suggestions.creationName {
            createAndSelect(name: creationName)
        } else if let exact = suggestions.exactMatch {
            selectedTagIDs = TagPickerSelection.selecting(exact.id, in: selectedTagIDs)
            newName = ""
        }
    }

    private func createAndSelect(name: String) {
        let submission = TagPickerCreateSubmission(
            name: name,
            rawQuery: newName
        )
        Task {
            guard let tag = await model.create(name: submission.name) else { return }
            let completion = submission.completion(
                createdTagID: tag.id,
                currentQuery: newName,
                selectedTagIDs: selectedTagIDs
            )
            selectedTagIDs = completion.selectedTagIDs
            newName = completion.query
        }
    }

    private func createSuggestionText(name: String) -> String {
        let format = String(
            localized: "tags.picker.create-suggestion",
            table: "Tags",
            locale: locale
        )
        return String(
            format: format,
            locale: locale,
            arguments: [name]
        )
    }

    private func actionText(
        for tag: TagSnapshot,
        isSelected: Bool
    ) -> String {
        let format = String(
            localized: isSelected
                ? "tags.picker.remove-accessibility"
                : "tags.picker.add-accessibility",
            table: "Tags",
            locale: locale
        )
        return String(
            format: format,
            locale: locale,
            arguments: [tag.name]
        )
    }

    private func reconcileSelection(after outcome: TagManagementLoadOutcome) {
        selectedTagIDs = TagPickerSelection.reconciled(
            selectedIDs: selectedTagIDs,
            availableIDs: Set(model.tags.map(\.id)),
            after: outcome
        )
    }
}

struct TagPickerCreateSubmission {
    struct Completion {
        let selectedTagIDs: Set<UUID>
        let query: String
    }

    let name: String
    let rawQuery: String

    func completion(
        createdTagID: UUID,
        currentQuery: String,
        selectedTagIDs: Set<UUID>
    ) -> Completion {
        Completion(
            selectedTagIDs: TagPickerSelection.selecting(
                createdTagID,
                in: selectedTagIDs
            ),
            query: currentQuery == rawQuery ? "" : currentQuery
        )
    }
}
