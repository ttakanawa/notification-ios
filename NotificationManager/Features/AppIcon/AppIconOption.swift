import Foundation

enum AppIconOption: String, CaseIterable, Identifiable, Sendable {
    case primary
    case ocean
    case sunset

    var id: Self { self }

    var alternateIconName: String? {
        switch self {
        case .primary: nil
        case .ocean: "AppIcon-Ocean"
        case .sunset: "AppIcon-Sunset"
        }
    }

    var previewAssetName: String {
        switch self {
        case .primary: "AppIconPreview-Default"
        case .ocean: "AppIconPreview-Ocean"
        case .sunset: "AppIconPreview-Sunset"
        }
    }

    static func matching(alternateIconName: String?) -> Self? {
        allCases.first { $0.alternateIconName == alternateIconName }
    }
}
