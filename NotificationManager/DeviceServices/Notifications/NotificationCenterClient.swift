import Foundation
import UserNotifications

public struct NotificationInventoryItem: Sendable, Equatable {
    public let identifier: String
    public let reminderRoutingValue: String?

    public init(identifier: String, reminderRoutingValue: String? = nil) {
        self.identifier = identifier
        self.reminderRoutingValue = reminderRoutingValue
    }
}

public protocol NotificationCenterClient: Sendable {
    func pendingNotificationInventory() async throws -> [NotificationInventoryItem]
    func deliveredNotificationInventory() async -> [NotificationInventoryItem]
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async
}

public final class SystemNotificationCenterClient:
    NotificationCenterClient,
    @unchecked Sendable
{
    private static let reminderIDKey = "notification-manager.reminder-id"
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func pendingNotificationInventory() async throws -> [NotificationInventoryItem] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(Self.inventoryItem))
            }
        }
    }

    public func deliveredNotificationInventory() async -> [NotificationInventoryItem] {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                continuation.resume(
                    returning: notifications.map {
                        Self.inventoryItem($0.request)
                    })
            }
        }
    }

    public func add(_ request: UNNotificationRequest) async throws {
        let _: Void = try await withCheckedThrowingContinuation { continuation in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    public func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private static func inventoryItem(
        _ request: UNNotificationRequest
    ) -> NotificationInventoryItem {
        NotificationInventoryItem(
            identifier: request.identifier,
            reminderRoutingValue: request.content.userInfo[reminderIDKey] as? String
        )
    }
}
