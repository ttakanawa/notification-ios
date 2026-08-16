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
                TextField(
                    LocalizedStringResource(
                        "tags.field.name",
                        table: "Tags"
                    ), text: $newName, prompt: nil
                )
                .submitLabel(.done)
                .onSubmit(createTag)
                .accessibilityIdentifier("tags.management.new-name")

                Button(
                    LocalizedStringResource(
                        "tags.action.create",
                        table: "Tags"
                    ), action: createTag
                )
                .disabled(model.isWorking || newName.isEmpty)
                .accessibilityIdentifier("tags.management.create")
            }

            Section {
                Text(verbatim: tagCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("tags.management.count")

                if model.tags.isEmpty {
                    Text(
                        LocalizedStringResource(
                            "tags.management.empty",
                            table: "Tags"
                        )
                    )
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
                            Label(
                                LocalizedStringResource(
                                    "tags.action.rename",
                                    table: "Tags"
                                ),
                                systemImage: "pencil"
                            )
                            .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier(
                            "tags.management.rename.\(tag.id.uuidString.lowercased())"
                        )

                        Button(role: .destructive) {
                            deleteTagID = tag.id
                        } label: {
                            Label(
                                LocalizedStringResource(
                                    "tags.action.delete",
                                    table: "Tags"
                                ),
                                systemImage: "trash"
                            )
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
                    Label(
                        error.localizedResource,
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("tags.management.error")
                }
            }
        }
        .navigationTitle(
            LocalizedStringResource(
                "tags.management.title",
                table: "Tags"
            )
        )
        .task { await model.load() }
        .alert(
            LocalizedStringResource(
                "tags.action.rename",
                table: "Tags"
            ), isPresented: renamePresented
        ) {
            TextField(
                LocalizedStringResource(
                    "tags.field.name",
                    table: "Tags"
                ), text: $renameName, prompt: nil)
            Button {
                guard let renameTagID else { return }
                let value = renameName
                Task {
                    if await model.rename(tagID: renameTagID, name: value) != nil {
                        self.renameTagID = nil
                    }
                }
            } label: {
                Text(
                    LocalizedStringResource(
                        "tags.action.rename",
                        table: "Tags"
                    )
                )
                .accessibilityIdentifier("tags.management.rename-confirm")
            }
            Button(
                LocalizedStringResource(
                    "reminder.action.cancel",
                    table: "Reminder"
                ), role: .cancel
            ) {
                renameTagID = nil
            }
        }
        .alert(
            LocalizedStringResource(
                "tags.delete-confirmation.title",
                table: "Tags"
            ), isPresented: deletePresented
        ) {
            Button(role: .destructive) {
                guard let deleteTagID else { return }
                Task {
                    if await model.delete(tagID: deleteTagID) {
                        self.deleteTagID = nil
                    }
                }
            } label: {
                Text(
                    LocalizedStringResource(
                        "tags.action.delete",
                        table: "Tags"
                    )
                )
                .accessibilityIdentifier("tags.management.delete-confirm")
            }
            Button(
                LocalizedStringResource(
                    "reminder.action.cancel",
                    table: "Reminder"
                ), role: .cancel
            ) {
                deleteTagID = nil
            }
        } message: {
            Text(
                LocalizedStringResource(
                    "tags.delete-confirmation.message",
                    table: "Tags"
                ))
        }
        .announcesAccessibilityErrors(
            model.actionError.map { [$0.accessibilityIdentity] } ?? []
        )
        .background {
            AccessibilityIdentifierContainer(identifier: "tags.management.root")
        }
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
            table: "Tags",
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
    var localizedResource: LocalizedStringResource {
        switch self {
        case .emptyName:
            LocalizedStringResource(
                "tags.error.empty-name",
                table: "Tags"
            )
        case .nameTooLarge:
            LocalizedStringResource(
                "tags.error.name-too-large",
                table: "Tags"
            )
        case .normalizedNameTooLarge:
            LocalizedStringResource(
                "tags.error.normalized-name-too-large",
                table: "Tags"
            )
        case .duplicateName:
            LocalizedStringResource(
                "tags.error.duplicate-name",
                table: "Tags"
            )
        case .notFound:
            LocalizedStringResource(
                "tags.error.not-found",
                table: "Tags"
            )
        case .storeUnavailable:
            LocalizedStringResource(
                "tags.error.store-unavailable",
                table: "Tags"
            )
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
