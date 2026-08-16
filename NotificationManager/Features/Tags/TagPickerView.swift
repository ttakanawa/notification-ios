import SwiftUI

struct TagPickerView: View {
    @Bindable var model: TagManagementModel
    @Binding var selectedTagIDs: Set<UUID>

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
                Toggle(isOn: selectionBinding(for: tag.id)) {
                    Label {
                        Text(verbatim: tag.name)
                    } icon: {
                        Image(systemName: "tag")
                    }
                }
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

    private func selectionBinding(for tagID: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedTagIDs.contains(tagID) },
            set: { selected in
                if selected {
                    let wasSelected = selectedTagIDs.contains(tagID)
                    selectedTagIDs = TagPickerSelection.selecting(tagID, in: selectedTagIDs)
                    if !wasSelected {
                        newName = ""
                    }
                } else {
                    selectedTagIDs.remove(tagID)
                }
            }
        )
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
