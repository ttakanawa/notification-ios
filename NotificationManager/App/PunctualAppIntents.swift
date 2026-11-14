import AppIntents
import NotificationManagerWidgetSupport

struct PunctualAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [PunctualWidgetIntentsPackage.self]
    }
}
