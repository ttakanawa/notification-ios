import NotificationManagerDomain
import UserNotifications

public struct NotificationAuthorizationSnapshot: Sendable, Equatable {
    public let state: DeviceAuthorizationSchedulingState
    public let diagnostic: NotificationAuthorizationDiagnostic?
    public let rawValue: Int

    public init(
        state: DeviceAuthorizationSchedulingState,
        diagnostic: NotificationAuthorizationDiagnostic?,
        rawValue: Int? = nil
    ) {
        self.state = state
        self.diagnostic = diagnostic
        self.rawValue = rawValue ?? diagnostic?.rawValue ?? state.canonicalRawValue
    }

    public var allowsScheduling: Bool { state == .allowed }

    var rawStatus: NotificationAuthorizationRawStatus {
        switch rawValue {
        case 0: .notDetermined
        case 1: .denied
        case 2: .authorized
        case 3: .provisional
        case 4: .ephemeral
        default: .unknown(rawValue: rawValue)
        }
    }
}

public enum NotificationAuthorizationDiagnostic: Sendable, Equatable {
    case unknownStatus(rawValue: Int)

    fileprivate var rawValue: Int {
        switch self {
        case let .unknownStatus(rawValue): rawValue
        }
    }
}

enum NotificationAuthorizationRawStatus: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown(rawValue: Int)
}

public protocol NotificationAuthorizationProviding: Sendable {
    func currentAuthorization() async -> NotificationAuthorizationSnapshot
}

protocol NotificationAuthorizationRequesting: Sendable {
    func requestAuthorization() async throws -> Bool
}

public final class NotificationAuthorizationService:
    NotificationAuthorizationProviding,
    NotificationAuthorizationRequesting,
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

    func requestAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    public static func map(rawValue: Int) -> NotificationAuthorizationSnapshot {
        switch rawValue {
        // UNAuthorizationStatus raw values are stable Objective-C API constants.
        // Use the value for ephemeral directly because that case is unavailable on macOS,
        // while this mapping remains host-testable and is consumed by the iOS adapter.
        case 2, 3, 4:
            NotificationAuthorizationSnapshot(
                state: .allowed,
                diagnostic: nil,
                rawValue: rawValue
            )
        case 0:
            NotificationAuthorizationSnapshot(
                state: .notDetermined,
                diagnostic: nil,
                rawValue: rawValue
            )
        case 1:
            NotificationAuthorizationSnapshot(
                state: .denied,
                diagnostic: nil,
                rawValue: rawValue
            )
        default:
            NotificationAuthorizationSnapshot(
                state: .unknown,
                diagnostic: .unknownStatus(rawValue: rawValue),
                rawValue: rawValue
            )
        }
    }
}

private extension DeviceAuthorizationSchedulingState {
    var canonicalRawValue: Int {
        switch self {
        case .notDetermined: 0
        case .denied: 1
        case .allowed: 2
        case .unknown: -1
        }
    }
}
