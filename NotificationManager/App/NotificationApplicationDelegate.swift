import Foundation
import NotificationManagerDomain
#if canImport(UIKit)
import UIKit
#endif
import UserNotifications

enum NotificationResponseDestination: Sendable, Equatable {
    case reminderEdit(UUID)
    case notificationUnavailable
}

enum NotificationResponseOutcome: Sendable, Equatable {
    case reminderEdit(UUID)
    case openedURL(URL)
    case notificationUnavailable
    case ignored
}

@MainActor
final class NotificationApplicationDelegate: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let reminderIDKey = "notification-manager.reminder-id"
    nonisolated static let openLinkCategoryIdentifier = "notification-manager.open-link"
    nonisolated static let openLinkActionIdentifier = "notification-manager.open-link-action"
    nonisolated static let pendingResponseLimit = 16

    typealias InstallHandler = @MainActor (
        NotificationApplicationDelegate,
        Set<UNNotificationCategory>
    ) -> Void
    typealias ReminderLookup = @Sendable (UUID) async throws -> ReminderSnapshot?
    typealias ResponseRouter = @MainActor @Sendable (
        NotificationResponseDestination
    ) -> Void
    typealias URLOpener = @MainActor @Sendable (URL) -> Void

    nonisolated private let eligibilityIndexStore: ForegroundEligibilityIndexStore
    nonisolated private let responseIngress: NotificationResponseIngress
    private let installHandler: InstallHandler
    private var reminderLookup: ReminderLookup
    private var routeResponse: ResponseRouter
    private var openURL: URLOpener
    private var reconcileAfterNotification: @Sendable (AppLifecycleTrigger) async -> Void
    private var isInstalled = false
    private var responseQueue: [QueuedNotificationResponse] = []
    private var responseDrainTask: Task<Void, Never>?

    var eligibilityIndex: ForegroundEligibilityIndexStore {
        eligibilityIndexStore
    }

    override convenience init() {
        self.init(
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            installHandler: { delegate, categories in
                let center = UNUserNotificationCenter.current()
                center.delegate = delegate
                center.setNotificationCategories(categories)
            },
            reminderLookup: { _ in nil },
            routeResponse: { _ in },
            openURL: { _ in },
            reconcileAfterNotification: { _ in },
            responseHandlingInitiallyBound: false
        )
    }

    init(
        eligibilityIndexStore: ForegroundEligibilityIndexStore,
        installHandler: @escaping InstallHandler = { delegate, categories in
            let center = UNUserNotificationCenter.current()
            center.delegate = delegate
            center.setNotificationCategories(categories)
        },
        reminderLookup: @escaping ReminderLookup = { _ in nil },
        routeResponse: @escaping ResponseRouter = { _ in },
        openURL: @escaping URLOpener = { _ in },
        reconcileAfterNotification: @escaping @Sendable (
            AppLifecycleTrigger
        ) async -> Void = { _ in },
        responseHandlingInitiallyBound: Bool = true
    ) {
        self.eligibilityIndexStore = eligibilityIndexStore
        self.installHandler = installHandler
        self.reminderLookup = reminderLookup
        self.routeResponse = routeResponse
        self.openURL = openURL
        self.reconcileAfterNotification = reconcileAfterNotification
        responseIngress = NotificationResponseIngress(
            isBound: responseHandlingInitiallyBound,
            pendingLimit: Self.pendingResponseLimit
        )
        super.init()
    }

    func install() {
        guard !isInstalled else { return }
        isInstalled = true
        let action = UNNotificationAction(
            identifier: Self.openLinkActionIdentifier,
            title: String(
                localized: "reminder.action.open-link",
                table: "Reminder"
            ),
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.openLinkCategoryIdentifier,
            actions: [action],
            intentIdentifiers: [],
            options: []
        )
        installHandler(self, [category])
    }

    func bind(
        reminderLookup: @escaping ReminderLookup,
        routeResponse: @escaping ResponseRouter,
        openURL: @escaping URLOpener,
        reconcileAfterNotification: @escaping @Sendable (
            AppLifecycleTrigger
        ) async -> Void
    ) {
        let binding = responseIngress.bind()
        guard case let .bound(shouldScheduleDrain) = binding else { return }
        self.reminderLookup = reminderLookup
        self.routeResponse = routeResponse
        self.openURL = openURL
        self.reconcileAfterNotification = reconcileAfterNotification
        if shouldScheduleDrain {
            scheduleResponseIngressDrain()
        }
    }

    nonisolated func immediatePresentationOptions(
        for request: UNNotificationRequest
    ) -> UNNotificationPresentationOptions {
        guard request.identifier.hasPrefix(NotificationIdentifierCodec.root),
              let reminderID = Self.reminderID(from: request.content.userInfo),
              eligibilityIndexStore.isEligible(reminderID)
        else {
            return []
        }
        return [.banner, .list, .sound]
    }

    nonisolated func presentationOptions(
        for request: UNNotificationRequest,
        completion: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        completion(immediatePresentationOptions(for: request))
        Task { @MainActor [weak self] in
            guard let self else { return }
            await reconcileAfterNotification(.notificationPresentationCompleted)
        }
    }

    func handleResponse(
        actionIdentifier: String,
        categoryIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) async -> NotificationResponseOutcome {
        await handleResponse(Self.responseValue(
            actionIdentifier: actionIdentifier,
            categoryIdentifier: categoryIdentifier,
            userInfo: userInfo
        ))
    }

    nonisolated func receiveResponse(
        actionIdentifier: String,
        categoryIdentifier: String,
        userInfo: [AnyHashable: Any],
        completion: @escaping @Sendable () -> Void
    ) {
        let enqueueResult = responseIngress.enqueue(
            response: Self.responseValue(
                actionIdentifier: actionIdentifier,
                categoryIdentifier: categoryIdentifier,
                userInfo: userInfo
            ),
            completion: completion
        )
        if enqueueResult.shouldCompleteImmediately {
            completion()
        }
        if enqueueResult.shouldScheduleDrain {
            scheduleResponseIngressDrain()
        }
    }

    private func handleResponse(
        _ response: PendingNotificationResponse,
        completion: (@Sendable () -> Void)? = nil
    ) async -> NotificationResponseOutcome {
        let outcome: NotificationResponseOutcome
        switch response.action {
        case .ignored:
            outcome = .ignored
        case .defaultTap, .openLink:
            outcome = await currentResponseOutcome(
                action: response.action,
                reminderID: response.reminderID
            )
            apply(outcome)
        }
        completion?()
        await reconcileAfterNotification(.notificationResponseCompleted)
        return outcome
    }

    private func startResponseDrainIfNeeded() {
        guard responseDrainTask == nil,
              !responseQueue.isEmpty
        else {
            return
        }
        responseDrainTask = Task { @MainActor [weak self] in
            await self?.drainResponseQueue()
        }
    }

    private func drainResponseQueue() async {
        while !responseQueue.isEmpty {
            let queued = responseQueue.removeFirst()
            _ = await handleResponse(
                queued.response,
                completion: queued.completion
            )
        }
        responseDrainTask = nil
    }

    nonisolated private func scheduleResponseIngressDrain() {
        Task { @MainActor [self] in
            transferScheduledIngressResponses()
        }
    }

    private func transferScheduledIngressResponses() {
        while let responses = responseIngress.takeNextScheduledBatch() {
            responseQueue.append(contentsOf: responses)
        }
        startResponseDrainIfNeeded()
    }

    nonisolated private static func responseValue(
        actionIdentifier: String,
        categoryIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) -> PendingNotificationResponse {
        let action: ResponseAction
        switch actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            action = .defaultTap
        case UNNotificationDismissActionIdentifier:
            action = .ignored
        case Self.openLinkActionIdentifier
            where categoryIdentifier == Self.openLinkCategoryIdentifier:
            action = .openLink
        default:
            action = .ignored
        }
        return PendingNotificationResponse(
            action: action,
            reminderID: reminderID(from: userInfo)
        )
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (
            UNNotificationPresentationOptions
        ) -> Void
    ) {
        presentationOptions(for: notification.request, completion: completionHandler)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        receiveResponse(
            actionIdentifier: response.actionIdentifier,
            categoryIdentifier: response.notification.request.content.categoryIdentifier,
            userInfo: response.notification.request.content.userInfo,
            completion: completionHandler
        )
    }

    private func currentResponseOutcome(
        action: ResponseAction,
        reminderID: UUID?
    ) async -> NotificationResponseOutcome {
        guard let reminderID,
              let reminder = try? await reminderLookup(reminderID),
              reminder.id == reminderID
        else {
            return .notificationUnavailable
        }

        if action == .openLink,
           let value = reminder.urlString,
           let canonical = try? CanonicalHTTPURL(value),
           let url = URL(string: canonical.string)
        {
            return .openedURL(url)
        }
        return .reminderEdit(reminderID)
    }

    private func apply(_ outcome: NotificationResponseOutcome) {
        switch outcome {
        case let .reminderEdit(reminderID):
            routeResponse(.reminderEdit(reminderID))
        case let .openedURL(url):
            openURL(url)
        case .notificationUnavailable:
            routeResponse(.notificationUnavailable)
        case .ignored:
            break
        }
    }

    nonisolated private static func reminderID(
        from userInfo: [AnyHashable: Any]
    ) -> UUID? {
        guard let rawValue = userInfo[reminderIDKey] as? String,
              rawValue == rawValue.lowercased(),
              let identifier = UUID(uuidString: rawValue),
              identifier.uuidString.lowercased() == rawValue
        else {
            return nil
        }
        return identifier
    }
}

#if canImport(UIKit)
extension NotificationApplicationDelegate: UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [
            UIApplication.LaunchOptionsKey: Any
        ]? = nil
    ) -> Bool {
        install()
        return true
    }
}
#endif

private enum ResponseAction: Sendable, Equatable {
    case defaultTap
    case openLink
    case ignored
}

private struct PendingNotificationResponse: Sendable {
    let action: ResponseAction
    let reminderID: UUID?
}

private struct QueuedNotificationResponse: Sendable {
    let response: PendingNotificationResponse
    let completion: (@Sendable () -> Void)?
}

private final class NotificationResponseIngress: @unchecked Sendable {
    enum BindingResult: Sendable {
        case alreadyBound
        case bound(shouldScheduleDrain: Bool)
    }

    struct EnqueueResult: Sendable {
        let shouldCompleteImmediately: Bool
        let shouldScheduleDrain: Bool
    }

    private let lock = NSLock()
    private let pendingLimit: Int
    private var isBound: Bool
    private var queuedResponses: [QueuedNotificationResponse] = []
    private var drainIsScheduled = false

    init(isBound: Bool, pendingLimit: Int) {
        self.isBound = isBound
        self.pendingLimit = pendingLimit
    }

    func bind() -> BindingResult {
        lock.withLock {
            guard !isBound else { return .alreadyBound }
            isBound = true
            guard !queuedResponses.isEmpty, !drainIsScheduled else {
                return .bound(shouldScheduleDrain: false)
            }
            drainIsScheduled = true
            return .bound(shouldScheduleDrain: true)
        }
    }

    func enqueue(
        response: PendingNotificationResponse,
        completion: @escaping @Sendable () -> Void
    ) -> EnqueueResult {
        lock.withLock {
            guard isBound else {
                if queuedResponses.count == pendingLimit {
                    queuedResponses.removeFirst()
                }
                queuedResponses.append(QueuedNotificationResponse(
                    response: response,
                    completion: nil
                ))
                return EnqueueResult(
                    shouldCompleteImmediately: true,
                    shouldScheduleDrain: false
                )
            }

            queuedResponses.append(QueuedNotificationResponse(
                response: response,
                completion: completion
            ))
            let shouldScheduleDrain = !drainIsScheduled
            drainIsScheduled = true
            return EnqueueResult(
                shouldCompleteImmediately: false,
                shouldScheduleDrain: shouldScheduleDrain
            )
        }
    }

    func takeNextScheduledBatch() -> [QueuedNotificationResponse]? {
        lock.withLock {
            guard !queuedResponses.isEmpty else {
                drainIsScheduled = false
                return nil
            }
            let responses = queuedResponses
            queuedResponses.removeAll(keepingCapacity: true)
            return responses
        }
    }
}
