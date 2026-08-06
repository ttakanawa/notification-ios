public protocol DeviceNotificationPreferenceStore: Sendable {
    func isEnabled() async -> Bool
    func setEnabled(_ enabled: Bool) async
}
