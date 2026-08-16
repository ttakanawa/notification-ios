import Foundation
import NotificationManagerApplication

public actor UserDefaultsNotificationPreferenceStore: DeviceNotificationPreferenceStore {
    public static let defaultKey = "notificationsOnThisDevice"

    private let userDefaults: UserDefaults
    private let key: String

    public init(
        suiteName: String? = nil,
        key: String = UserDefaultsNotificationPreferenceStore.defaultKey
    ) {
        if let suiteName {
            guard let userDefaults = UserDefaults(suiteName: suiteName) else {
                preconditionFailure("Unable to open the requested UserDefaults suite")
            }
            self.userDefaults = userDefaults
        } else {
            userDefaults = .standard
        }
        self.key = key
    }

    public func isEnabled() -> Bool {
        userDefaults.bool(forKey: key)
    }

    public func setEnabled(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: key)
    }
}
