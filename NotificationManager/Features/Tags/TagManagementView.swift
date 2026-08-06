import SwiftUI

struct TagManagementView: View {
    @Bindable var model: TagManagementModel

    @Environment(\.locale) private var locale
    @State private var newName = ""
    @State private var renameTagID: UUID?
    @State private var renameName = ""
    @State private var deleteTagID: UUID?

    var body: some View {
        List {
            Section {
                TextField("tags.field.name", text: $newName)
                    .submitLabel(.done)
                    .onSubmit(createTag)
                    .accessibilityIdentifier("tags.management.new-name")

                Button("tags.action.create", action: createTag)
                    .disabled(model.isWorking || newName.isEmpty)
                    .accessibilityIdentifier("tags.management.create")
            }

            Section {
                Text(verbatim: tagCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("tags.management.count")

                if model.tags.isEmpty {
                    Text("tags.management.empty")
                        .foregroundStyle(.secondary)
                }

                ForEach(model.tags, id: \.id) { tag in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(verbatim: tag.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            renameTagID = tag.id
                            renameName = tag.name
                        } label: {
                            Label("tags.action.rename", systemImage: "pencil")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier(
                            "tags.management.rename.\(tag.id.uuidString.lowercased())"
                        )

                        Button(role: .destructive) {
                            deleteTagID = tag.id
                        } label: {
                            Label("tags.action.delete", systemImage: "trash")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier(
                            "tags.management.delete.\(tag.id.uuidString.lowercased())"
                        )
                    }
                }
            }

            if let error = model.actionError {
                Section {
                    Label(error.semanticKey, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("tags.management.error")
                }
            }
        }
        .navigationTitle("tags.management.title")
        .task { await model.load() }
        .alert("tags.action.rename", isPresented: renamePresented) {
            TextField("tags.field.name", text: $renameName)
            Button("tags.action.rename") {
                guard let renameTagID else { return }
                let value = renameName
                Task {
                    if await model.rename(tagID: renameTagID, name: value) != nil {
                        self.renameTagID = nil
                    }
                }
            }
            .accessibilityIdentifier("tags.management.rename-confirm")
            Button("reminder.action.cancel", role: .cancel) {
                renameTagID = nil
            }
        }
        .alert("tags.delete-confirmation.title", isPresented: deletePresented) {
            Button("tags.action.delete", role: .destructive) {
                guard let deleteTagID else { return }
                Task {
                    if await model.delete(tagID: deleteTagID) {
                        self.deleteTagID = nil
                    }
                }
            }
            .accessibilityIdentifier("tags.management.delete-confirm")
            Button("reminder.action.cancel", role: .cancel) {
                deleteTagID = nil
            }
        } message: {
            Text("tags.delete-confirmation.message")
        }
        .announcesAccessibilityErrors(
            model.actionError.map { [$0.accessibilityIdentity] } ?? []
        )
        .accessibilityIdentifier("tags.management.root")
    }

    private var renamePresented: Binding<Bool> {
        Binding(
            get: { renameTagID != nil },
            set: { if !$0 { renameTagID = nil } }
        )
    }

    private var deletePresented: Binding<Bool> {
        Binding(
            get: { deleteTagID != nil },
            set: { if !$0 { deleteTagID = nil } }
        )
    }

    private var tagCountText: String {
        let format = String(
            localized: "tags.management.count",
            table: "Localizable",
            bundle: .main,
            locale: locale
        )
        return String.localizedStringWithFormat(format, Int64(model.tags.count))
    }

    private func createTag() {
        let value = newName
        Task {
            if await model.create(name: value) != nil {
                newName = ""
            }
        }
    }
}

extension TagActionErrorIdentity {
    var semanticKey: LocalizedStringKey {
        switch self {
        case .emptyName: "tags.error.empty-name"
        case .nameTooLarge: "tags.error.name-too-large"
        case .normalizedNameTooLarge: "tags.error.normalized-name-too-large"
        case .duplicateName: "tags.error.duplicate-name"
        case .notFound: "tags.error.not-found"
        case .storeUnavailable: "tags.error.store-unavailable"
        }
    }

    var accessibilityIdentity: AccessibilityErrorIdentity {
        switch self {
        case .emptyName: .tagEmptyName
        case .nameTooLarge: .tagNameTooLarge
        case .normalizedNameTooLarge: .tagNormalizedNameTooLarge
        case .duplicateName: .tagDuplicateName
        case .notFound: .tagNotFound
        case .storeUnavailable: .tagStoreUnavailable
        }
    }
}
