import SwiftUI

struct AppIconPickerView: View {
    @Bindable var model: AppIconSelectionModel

    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                stateMessage

                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(AppIconOption.allCases) { option in
                        optionButton(option)
                    }
                }

                if let error = model.actionError {
                    Label(
                        error.localizedResource,
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.app-icon.error")
                }
            }
            .padding()
        }
        .navigationTitle(
            LocalizedStringResource("settings.app-icon.title", table: "Settings")
        )
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
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Image(option.previewAssetName)
                        .resizable()
                        .scaledToFit()
                        .clipShape(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                        )
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(6)
                            .accessibilityHidden(true)
                    }
                }
                Text(option.localizedResource)
            }
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
