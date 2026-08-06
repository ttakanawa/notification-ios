import SwiftUI

struct TagPickerView: View {
    @Bindable var model: TagManagementModel
    @Binding var selectedTagIDs: Set<UUID>

    @State private var newName = ""

    var body: some View {
        Section("tags.picker.title") {
            ForEach(model.tags, id: \.id) { tag in
                Toggle(isOn: selectionBinding(for: tag.id)) {
                    Label {
                        Text(verbatim: tag.name)
                    } icon: {
                        Image(systemName: "tag")
                    }
                }
                .accessibilityIdentifier("tags.picker.tag.\(tag.id.uuidString.lowercased())")
            }

            TextField("tags.field.name", text: $newName)
                .submitLabel(.done)
                .onSubmit(createAndSelect)
                .accessibilityIdentifier("tags.picker.new-name")

            Button("tags.action.create", action: createAndSelect)
                .disabled(model.isWorking || newName.isEmpty)
                .accessibilityIdentifier("tags.picker.create")

            if let error = model.actionError {
                Label(error.semanticKey, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("tags.picker.error")
            }
        }
        .task {
            await model.load()
            reconcileSelection()
        }
        .onChange(of: model.tags.map(\.id)) { _, _ in
            reconcileSelection()
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
                    selectedTagIDs = TagPickerSelection.selecting(tagID, in: selectedTagIDs)
                } else {
                    selectedTagIDs.remove(tagID)
                }
            }
        )
    }

    private func createAndSelect() {
        let value = newName
        Task {
            guard let tag = await model.create(name: value) else { return }
            selectedTagIDs = TagPickerSelection.selecting(tag.id, in: selectedTagIDs)
            newName = ""
        }
    }

    private func reconcileSelection() {
        selectedTagIDs = TagPickerSelection.reconciled(
            selectedIDs: selectedTagIDs,
            availableIDs: Set(model.tags.map(\.id))
        )
    }
}
