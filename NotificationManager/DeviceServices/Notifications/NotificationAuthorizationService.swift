import NotificationManagerDomain
import UserNotifications

public struct NotificationAuthorizationSnapshot: Sendable, Equatable {
    public let state: DeviceAuthorizationSchedulingState
    public let diagnostic: NotificationAuthorizationDiagnostic?

    public init(
        state: DeviceAuthorizationSchedulingState,
        diagnostic: NotificationAuthorizationDiagnostic?
    ) {
        self.state = state
        self.diagnostic = diagnostic
    }

    public var allowsScheduling: Bool { state == .allowed }
}

public enum NotificationAuthorizationDiagnostic: Sendable, Equatable {
    case unknownStatus(rawValue: Int)
}

public protocol NotificationAuthorizationProviding: Sendable {
    func currentAuthorization() async -> NotificationAuthorizationSnapshot
}

public final class NotificationAuthorizationService:
    NotificationAuthorizationProviding,
    @unchecked Sendable
{
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func currentAuthorization() async -> NotificationAuthorizationSnapshot {
        let rawValue = await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus.rawValue)
            }
        }
        return Self.map(rawValue: rawValue)
    }

    public static func map(rawValue: Int) -> NotificationAuthorizationSnapshot {
        switch rawValue {
        // UNAuthorizationStatus raw values are stable Objective-C API constants.
        // Use the value for ephemeral directly because that case is unavailable on macOS,
        // while this mapping remains host-testable and is consumed by the iOS adapter.
        case 2, 3, 4:
            NotificationAuthorizationSnapshot(state: .allowed, diagnostic: nil)
        case 0:
            NotificationAuthorizationSnapshot(state: .notDetermined, diagnostic: nil)
        case 1:
            NotificationAuthorizationSnapshot(state: .denied, diagnostic: nil)
        default:
            NotificationAuthorizationSnapshot(
                state: .unknown,
                diagnostic: .unknownStatus(rawValue: rawValue)
            )
        }
    }
}
