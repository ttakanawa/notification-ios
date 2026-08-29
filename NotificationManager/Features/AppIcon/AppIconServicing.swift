@MainActor
protocol AppIconServicing: AnyObject {
    var supportsAlternateIcons: Bool { get }
    var alternateIconName: String? { get }

    func setAlternateIconName(_ name: String?) async throws
}
