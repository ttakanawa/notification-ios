import AppIntents
import NotificationManagerWidgetSupport

struct PunctualWidgetAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [PunctualWidgetIntentsPackage.self]
    }
}
