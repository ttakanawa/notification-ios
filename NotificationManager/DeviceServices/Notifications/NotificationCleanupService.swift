import Foundation
import NotificationManagerApplication
import NotificationManagerDomain

public struct NotificationCleanupService: NotificationCleanup {
    private let notificationCenter: any NotificationCenterClient
    private let identifierCodec: NotificationIdentifierCodec

    public init(notificationCenter: any NotificationCenterClient) {
        self.notificationCenter = notificationCenter
        identifierCodec = NotificationIdentifierCodec()
    }

    public func removeNotifications(for reminderID: UUID) async {
        let pending = (try? await notificationCenter.pendingNotificationInventory()) ?? []
        let pendingIdentifiers = pending
            .filter { matches($0, reminderID: reminderID) }
            .map(\.identifier)
        if !pendingIdentifiers.isEmpty {
            await notificationCenter.removePendingNotificationRequests(
                withIdentifiers: pendingIdentifiers
            )
        }

        let delivered = await notificationCenter.deliveredNotificationInventory()
        let deliveredIdentifiers = delivered
            .filter { matches($0, reminderID: reminderID) }
            .map(\.identifier)
        if !deliveredIdentifiers.isEmpty {
            await notificationCenter.removeDeliveredNotifications(
                withIdentifiers: deliveredIdentifiers
            )
        }
    }

    public func removeAllPendingAppNotifications() async {
        let pending = (try? await notificationCenter.pendingNotificationInventory()) ?? []
        let identifiers = pending
            .filter { $0.identifier.hasPrefix(NotificationIdentifierCodec.root) }
            .map(\.identifier)
        guard !identifiers.isEmpty else { return }
        await notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func matches(_ item: NotificationInventoryItem, reminderID: UUID) -> Bool {
        switch identifierCodec.classify(item.identifier) {
        case let .currentOneShot(identifierReminderID, _),
             let .currentRepeating(identifierReminderID, _):
            if identifierReminderID == reminderID { return true }
        case .appOwnedStale, .unrelated:
            break
        }

        guard let rawValue = item.reminderRoutingValue,
              let routedReminderID = UUID(uuidString: rawValue)
        else {
            return false
        }
        return routedReminderID == reminderID
    }
}
