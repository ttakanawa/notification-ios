import SwiftUI

struct AppIconPickerView: View {
    @Bindable var model: AppIconSelectionModel

    var body: some View {
        List {
            Section {
                stateMessage
                ForEach(AppIconOption.allCases) { option in
                    optionButton(option)
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
                    .accessibilityIdentifier("settings.app-icon.error")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(
            LocalizedStringResource("settings.app-icon.title", table: "Settings")
        )
        .navigationBarTitleDisplayMode(.inline)
        .task { model.load() }
        .announcesAccessibilityErrors(accessibilityErrors)
        .background {
            AccessibilityIdentifierContainer(
                identifier: "settings.app-icon.root",
                value: model.selectedOption?.rawValue
            )
        }
    }

    @ViewBuilder
    private var stateMessage: some View {
        switch model.availability {
        case .loading:
            ProgressView()
        case .available:
            EmptyView()
        case .unsupported:
            Text(
                LocalizedStringResource(
                    "settings.app-icon.unsupported",
                    table: "Settings"
                )
            )
            .accessibilityIdentifier("settings.app-icon.unsupported")
        case .configurationError:
            Text(
                LocalizedStringResource(
                    "settings.app-icon.configuration-error",
                    table: "Settings"
                )
            )
            .foregroundStyle(.red)
            .accessibilityIdentifier("settings.app-icon.configuration-error")
        }
    }

    private func optionButton(_ option: AppIconOption) -> some View {
        let isSelected = model.selectedOption == option
        return Button {
            Task { await model.select(option) }
        } label: {
            HStack(spacing: 16) {
                Image(option.previewAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .accessibilityHidden(true)
                Text(option.localizedResource)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.availability != .available || model.isChanging)
        .accessibilityIdentifier("settings.app-icon.option.\(option.rawValue)")
        .accessibilityValue(
            isSelected
                ? Text(
                    LocalizedStringResource(
                        "settings.app-icon.selected",
                        table: "Settings"
                    ))
                : Text("")
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityErrors: [AccessibilityErrorIdentity] {
        model.actionError.map { [$0.accessibilityIdentity] } ?? []
    }
}

extension AppIconOption {
    var localizedResource: LocalizedStringResource {
        switch self {
        case .primary:
            LocalizedStringResource(
                "settings.app-icon.option.primary",
                table: "Settings"
            )
        case .ocean:
            LocalizedStringResource(
                "settings.app-icon.option.ocean",
                table: "Settings"
            )
        case .sunset:
            LocalizedStringResource(
                "settings.app-icon.option.sunset",
                table: "Settings"
            )
        }
    }
}

extension AppIconSelectionActionErrorIdentity {
    var localizedResource: LocalizedStringResource {
        LocalizedStringResource(
            "settings.error.app-icon-change-failed",
            table: "Settings"
        )
    }

    var accessibilityIdentity: AccessibilityErrorIdentity {
        .settingsAppIconChangeFailed
    }
}
