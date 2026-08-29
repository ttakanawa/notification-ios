import UIKit

@MainActor
final class UIApplicationAppIconService: AppIconServicing {
    private let application: UIApplication

    init(application: UIApplication = .shared) {
        self.application = application
    }

    var supportsAlternateIcons: Bool {
        application.supportsAlternateIcons
    }

    var alternateIconName: String? {
        application.alternateIconName
    }

    func setAlternateIconName(_ name: String?) async throws {
        try await application.setAlternateIconName(name)
    }
}
