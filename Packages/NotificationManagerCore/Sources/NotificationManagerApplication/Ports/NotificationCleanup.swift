import Foundation

public protocol NotificationCleanup: Sendable {
    func removeNotifications(for reminderID: UUID) async
    func removeAllPendingAppNotifications() async
}
