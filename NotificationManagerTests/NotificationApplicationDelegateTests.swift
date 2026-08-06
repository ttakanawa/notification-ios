import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import Testing
import UserNotifications
@testable import NotificationManager

@Suite("Notification application delegate")
struct NotificationApplicationDelegateTests {
    @MainActor
    @Test func staleEligibilitySuppressesPresentationBeforeAsyncReconcile() async {
        let index = ForegroundEligibilityIndexStore()
        let sequence = NotificationDelegateSequence()
        let reconciles = NotificationDelegateReconcileRecorder(sequence: sequence)
        let delegate = NotificationApplicationDelegate(
            eligibilityIndexStore: index,
            reconcileAfterNotification: { trigger in
                await reconciles.record(trigger)
            }
        )
        let request = notificationRequest(reminderID: Self.reminderID)
        let completion = NotificationPresentationCompletionRecorder(sequence: sequence)

        delegate.presentationOptions(for: request) { options in
            completion.record(options)
        }
        await reconciles.waitForCount(1)

        #expect(completion.options == [])
        #expect(await reconciles.events == [.notificationPresentationCompleted])
        #expect(completion.sequence == 1)
        #expect(await reconciles.firstSequence == 2)
    }

    @MainActor
    @Test func freshEligibleReminderPresentsBannerListAndSound() async {
        let index = ForegroundEligibilityIndexStore()
        index.publish(eligibleReminderIDs: [Self.reminderID])
        let delegate = NotificationApplicationDelegate(
            eligibilityIndexStore: index,
            reconcileAfterNotification: { _ in }
        )
        let completion = NotificationPresentationCompletionRecorder(
            sequence: NotificationDelegateSequence()
        )

        delegate.presentationOptions(
            for: notificationRequest(reminderID: Self.reminderID)
        ) { options in
            completion.record(options)
        }

        #expect(completion.options == [.banner, .list, .sound])
    }

    @MainActor
    @Test func unrelatedOrNoncanonicalForegroundPayloadIsSuppressed() async {
        let index = ForegroundEligibilityIndexStore()
        index.publish(eligibleReminderIDs: [Self.reminderID])
        let delegate = NotificationApplicationDelegate(
            eligibilityIndexStore: index,
            reconcileAfterNotification: { _ in }
        )
        let unrelated = notificationRequest(
            reminderID: Self.reminderID,
            identifier: "another-app.request"
        )
        let uppercase = notificationRequest(
            routingValue: Self.reminderID.uuidString,
            identifier: "notification-manager.local.test"
        )

        #expect(delegate.immediatePresentationOptions(for: unrelated) == [])
        #expect(delegate.immediatePresentationOptions(for: uppercase) == [])
    }

    @MainActor
    @Test func defaultTapUsesCurrentStoreAndRoutesCurrentDetailEvenWhenURLExists() async {
        let lookup = NotificationLookupRecorder(
            reminder: reminder(urlString: "https://current.example/path")
        )
        let routes = NotificationRouteRecorder()
        let delegate = responseDelegate(lookup: lookup, routes: routes)

        let outcome = await delegate.handleResponse(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            categoryIdentifier: Self.openLinkCategory,
            userInfo: routingInfo(payloadURL: "https://stale.example/secret")
        )

        #expect(outcome == .reminderDetail(Self.reminderID))
        #expect(routes.destinations == [.reminderDetail(Self.reminderID)])
        #expect(routes.openedURLs.isEmpty)
        #expect(await lookup.requestedIDs == [Self.reminderID])
    }

    @MainActor
    @Test func openLinkUsesOnlyTheCurrentCanonicalStoreURL() async {
        let currentURL = URL(string: "https://current.example/path")!
        let lookup = NotificationLookupRecorder(
            reminder: reminder(urlString: currentURL.absoluteString)
        )
        let routes = NotificationRouteRecorder()
        let delegate = responseDelegate(lookup: lookup, routes: routes)

        let outcome = await delegate.handleResponse(
            actionIdentifier: NotificationApplicationDelegate.openLinkActionIdentifier,
            categoryIdentifier: Self.openLinkCategory,
            userInfo: routingInfo(payloadURL: "https://stale.example/secret")
        )

        #expect(outcome == .openedURL(currentURL))
        #expect(routes.openedURLs == [currentURL])
        #expect(routes.destinations.isEmpty)
    }

    @MainActor
    @Test func openLinkWithoutACurrentValidURLFallsBackToCurrentDetail() async {
        for urlString in [nil, "not a current URL"] as [String?] {
            let lookup = NotificationLookupRecorder(
                reminder: reminder(urlString: urlString)
            )
            let routes = NotificationRouteRecorder()
            let delegate = responseDelegate(lookup: lookup, routes: routes)

            let outcome = await delegate.handleResponse(
                actionIdentifier: NotificationApplicationDelegate.openLinkActionIdentifier,
                categoryIdentifier: Self.openLinkCategory,
                userInfo: routingInfo(payloadURL: "https://stale.example/secret")
            )

            #expect(outcome == .reminderDetail(Self.reminderID))
            #expect(routes.destinations == [.reminderDetail(Self.reminderID)])
            #expect(routes.openedURLs.isEmpty)
        }
    }

    @MainActor
    @Test func missingOrNoncanonicalReminderRoutesOnlyToNeutralUnavailable() async {
        let lookup = NotificationLookupRecorder(reminder: nil)
        let routes = NotificationRouteRecorder()
        let delegate = responseDelegate(lookup: lookup, routes: routes)

        let missing = await delegate.handleResponse(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            categoryIdentifier: "",
            userInfo: routingInfo(payloadURL: "https://stale.example/secret")
        )
        let uppercase = await delegate.handleResponse(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            categoryIdentifier: "",
            userInfo: [
                NotificationApplicationDelegate.reminderIDKey:
                    Self.reminderID.uuidString
            ]
        )

        #expect(missing == .notificationUnavailable)
        #expect(uppercase == .notificationUnavailable)
        #expect(routes.destinations == [
            .notificationUnavailable,
            .notificationUnavailable
        ])
        #expect(routes.openedURLs.isEmpty)
    }

    @MainActor
    @Test func dismissUnknownAndWrongCategoryExposeNothingButStillReconcile() async {
        let lookup = NotificationLookupRecorder(
            reminder: reminder(urlString: "https://current.example")
        )
        let routes = NotificationRouteRecorder()
        let reconciles = NotificationResponseReconcileRecorder()
        let delegate = responseDelegate(
            lookup: lookup,
            routes: routes,
            reconcile: { await reconciles.record($0) }
        )

        let outcomes = await [
            (UNNotificationDismissActionIdentifier, Self.openLinkCategory),
            ("future-action", Self.openLinkCategory),
            (NotificationApplicationDelegate.openLinkActionIdentifier, "wrong-category")
        ].asyncMap { action, category in
            await delegate.handleResponse(
                actionIdentifier: action,
                categoryIdentifier: category,
                userInfo: routingInfo(payloadURL: "https://stale.example/secret")
            )
        }

        #expect(outcomes == [.ignored, .ignored, .ignored])
        #expect(routes.destinations.isEmpty)
        #expect(routes.openedURLs.isEmpty)
        #expect(await lookup.requestedIDs.isEmpty)
        #expect(await reconciles.triggers == [
            .notificationResponseCompleted,
            .notificationResponseCompleted,
            .notificationResponseCompleted
        ])
    }

    @MainActor
    @Test func coldLaunchResponseCompletesImmediatelyAndReplaysAfterStoreBinding() async {
        let lookup = NotificationLookupRecorder(
            reminder: reminder(urlString: nil)
        )
        let routes = NotificationRouteRecorder()
        let completion = NotificationResponseCompletionRecorder()
        let delegate = NotificationApplicationDelegate(
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            responseHandlingInitiallyBound: false
        )

        delegate.receiveResponse(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            categoryIdentifier: "",
            userInfo: routingInfo(payloadURL: "https://stale.example/secret"),
            completion: { completion.record() }
        )

        #expect(completion.count == 1)
        #expect(await lookup.requestedIDs.isEmpty)
        #expect(routes.destinations.isEmpty)

        delegate.bind(
            reminderLookup: { await lookup.reminder(id: $0) },
            routeResponse: { routes.route($0) },
            openURL: { routes.open($0) },
            reconcileAfterNotification: { _ in }
        )
        await routes.waitForDestinationCount(1)

        delegate.bind(
            reminderLookup: { await lookup.reminder(id: $0) },
            routeResponse: { routes.route($0) },
            openURL: { routes.open($0) },
            reconcileAfterNotification: { _ in }
        )
        await Task.yield()

        #expect(routes.destinations == [.reminderDetail(Self.reminderID)])
        #expect(await lookup.requestedIDs == [Self.reminderID])
        #expect(routes.openedURLs.isEmpty)
    }

    @MainActor
    @Test func coldLaunchResponseQueueIsBoundedAndReplaysInFIFOOrder() async {
        let lookup = NotificationLookupRecorder(reminder: nil)
        let routes = NotificationRouteRecorder()
        let completion = NotificationResponseCompletionRecorder()
        let delegate = NotificationApplicationDelegate(
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            responseHandlingInitiallyBound: false
        )
        let identifiers = (0...NotificationApplicationDelegate.pendingResponseLimit).map {
            UUID(uuidString: String(
                format: "00000000-0000-0000-0000-%012x",
                $0
            ))!
        }

        for identifier in identifiers {
            delegate.receiveResponse(
                actionIdentifier: UNNotificationDefaultActionIdentifier,
                categoryIdentifier: "",
                userInfo: [
                    NotificationApplicationDelegate.reminderIDKey:
                        identifier.uuidString.lowercased()
                ],
                completion: { completion.record() }
            )
        }
        #expect(completion.count == identifiers.count)

        delegate.bind(
            reminderLookup: { await lookup.reminder(id: $0) },
            routeResponse: { routes.route($0) },
            openURL: { routes.open($0) },
            reconcileAfterNotification: { _ in }
        )
        await lookup.waitForRequestCount(
            NotificationApplicationDelegate.pendingResponseLimit
        )

        #expect(await lookup.requestedIDs == Array(identifiers.dropFirst()))
    }

    @MainActor
    @Test func queuedMissingAndIgnoredResponsesReplayTheirNormalPrivacySafeOutcomes() async {
        let lookup = NotificationLookupRecorder(reminder: nil)
        let routes = NotificationRouteRecorder()
        let reconciles = NotificationResponseReconcileRecorder()
        let completion = NotificationResponseCompletionRecorder()
        let delegate = NotificationApplicationDelegate(
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            responseHandlingInitiallyBound: false
        )

        for action in [
            UNNotificationDefaultActionIdentifier,
            UNNotificationDismissActionIdentifier,
            "unknown-action"
        ] {
            delegate.receiveResponse(
                actionIdentifier: action,
                categoryIdentifier: "",
                userInfo: ["url": "https://stale.example/private"],
                completion: { completion.record() }
            )
        }
        delegate.bind(
            reminderLookup: { await lookup.reminder(id: $0) },
            routeResponse: { routes.route($0) },
            openURL: { routes.open($0) },
            reconcileAfterNotification: { await reconciles.record($0) }
        )
        await reconciles.waitForCount(3)

        #expect(completion.count == 3)
        #expect(routes.destinations == [.notificationUnavailable])
        #expect(routes.openedURLs.isEmpty)
        #expect(await lookup.requestedIDs.isEmpty)
        #expect(await reconciles.triggers == [
            .notificationResponseCompleted,
            .notificationResponseCompleted,
            .notificationResponseCompleted
        ])
    }

    @MainActor
    @Test func neutralAndSettingsRoutesClearSelectionAcrossAdaptiveTransitions() {
        let actions = ReminderActionCoordinator(handlers: ReminderActionHandlers(
            setEnabled: { command in .saved(command.reminderID) },
            delete: { _ in }
        ))
        let router = AppRouter(actions: actions)

        router.showReminder(Self.reminderID)
        router.showNotificationUnavailable()
        #expect(router.selectedReminderID == nil)
        #expect(router.compactPath.last == .notificationUnavailable)

        router.synchronizeLayout(.regular)
        #expect(router.regularDestination == .notificationUnavailable)
        #expect(router.selectedReminderID == nil)

        router.showReminder(Self.reminderID)
        router.showSettings()
        #expect(router.regularDestination == .settings)
        #expect(router.selectedReminderID == nil)

        router.synchronizeLayout(.compact)
        #expect(router.compactPath == [.settings])
        #expect(router.selectedReminderID == nil)
    }

    @MainActor
    @Test func refreshKeepsAnExistingUnsavedFormInstance() {
        let router = AppRouter(actions: routerActions())
        let editing = formModel(title: "Unsaved draft")
        let imported = formModel(title: "Imported title")
        router.register(form: editing)

        router.registerFormIfAbsent(imported)

        #expect(router.formModel(for: Self.reminderID) === editing)
        #expect(router.formModel(for: Self.reminderID)?.title == "Unsaved draft")
    }

    @MainActor
    @Test func successfulSaveRemovesOldFormBeforeRefreshingItsReplacement() async {
        let relay = RouterSaveRefreshRelay()
        let router = AppRouter(
            actions: routerActions(),
            reminderSaved: { reminderID in
                relay.refresh(reminderID)
            }
        )
        relay.router = router
        relay.replacement = formModel(title: "Saved current value")
        router.register(form: formModel(title: "Old draft"))

        let saved = await router.performReminderSave(Self.reminderID) { true }

        #expect(saved)
        #expect(relay.observedOldFormWasRemoved)
        #expect(router.formModel(for: Self.reminderID) === relay.replacement)
    }

    private static let reminderID = UUID(
        uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    )!

    private static let openLinkCategory =
        NotificationApplicationDelegate.openLinkCategoryIdentifier

    private func notificationRequest(
        reminderID: UUID,
        identifier: String = "notification-manager.local.test"
    ) -> UNNotificationRequest {
        notificationRequest(
            routingValue: reminderID.uuidString.lowercased(),
            identifier: identifier
        )
    }

    private func notificationRequest(
        routingValue: String,
        identifier: String
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.userInfo = [
            NotificationApplicationDelegate.reminderIDKey:
                routingValue
        ]
        return UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
    }

    @MainActor
    private func responseDelegate(
        lookup: NotificationLookupRecorder,
        routes: NotificationRouteRecorder,
        reconcile: @escaping @Sendable (AppLifecycleTrigger) async -> Void = { _ in }
    ) -> NotificationApplicationDelegate {
        NotificationApplicationDelegate(
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            reminderLookup: { await lookup.reminder(id: $0) },
            routeResponse: { routes.route($0) },
            openURL: { routes.open($0) },
            reconcileAfterNotification: reconcile
        )
    }

    private func routingInfo(payloadURL: String) -> [AnyHashable: Any] {
        [
            NotificationApplicationDelegate.reminderIDKey:
                Self.reminderID.uuidString.lowercased(),
            "url": payloadURL,
            "title": "stale private title",
            "notes": "stale private notes"
        ]
    }

    private func reminder(urlString: String?) -> ReminderSnapshot {
        ReminderSnapshot(
            id: Self.reminderID,
            title: "Current title",
            notes: "Current notes",
            urlString: urlString,
            enabled: true,
            schedule: .corrupt(originalData: Data([0xff])),
            tagIDs: [],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
    }

    @MainActor
    private func routerActions() -> ReminderActionCoordinator {
        ReminderActionCoordinator(handlers: ReminderActionHandlers(
            setEnabled: { command in .saved(command.reminderID) },
            delete: { _ in }
        ))
    }

    @MainActor
    private func formModel(title: String) -> ReminderFormModel {
        let model = ReminderFormModel(
            newReminderID: Self.reminderID,
            now: Date(timeIntervalSince1970: 1),
            actions: ReminderFormActions(
                save: { draft, _, _ in .saved(draft.id) },
                delete: { _ in }
            )
        )
        model.title = title
        return model
    }
}

@MainActor
private final class RouterSaveRefreshRelay {
    weak var router: AppRouter?
    var replacement: ReminderFormModel?
    private(set) var observedOldFormWasRemoved = false

    func refresh(_ reminderID: UUID) {
        observedOldFormWasRemoved = router?.formModel(for: reminderID) == nil
        if let replacement {
            router?.registerFormIfAbsent(replacement)
        }
    }
}

private actor NotificationLookupRecorder {
    private let storedReminder: ReminderSnapshot?
    private(set) var requestedIDs: [UUID] = []

    init(reminder: ReminderSnapshot?) {
        storedReminder = reminder
    }

    func reminder(id: UUID) -> ReminderSnapshot? {
        requestedIDs.append(id)
        return storedReminder?.id == id ? storedReminder : nil
    }

    func waitForRequestCount(_ count: Int) async {
        while requestedIDs.count < count {
            await Task.yield()
        }
    }
}

@MainActor
private final class NotificationRouteRecorder {
    private(set) var destinations: [NotificationResponseDestination] = []
    private(set) var openedURLs: [URL] = []

    func route(_ destination: NotificationResponseDestination) {
        destinations.append(destination)
    }

    func open(_ url: URL) {
        openedURLs.append(url)
    }

    func waitForDestinationCount(_ count: Int) async {
        while destinations.count < count {
            await Task.yield()
        }
    }
}

private actor NotificationResponseReconcileRecorder {
    private(set) var triggers: [AppLifecycleTrigger] = []

    func record(_ trigger: AppLifecycleTrigger) {
        triggers.append(trigger)
    }

    func waitForCount(_ count: Int) async {
        while triggers.count < count {
            await Task.yield()
        }
    }
}

private extension Array {
    func asyncMap<T: Sendable>(
        _ transform: (Element) async -> T
    ) async -> [T] {
        var result: [T] = []
        for element in self {
            result.append(await transform(element))
        }
        return result
    }
}

private final class NotificationPresentationCompletionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let sequenceCounter: NotificationDelegateSequence
    private var storedOptions: UNNotificationPresentationOptions = []
    private var storedSequence = 0

    init(sequence: NotificationDelegateSequence) {
        sequenceCounter = sequence
    }

    var options: UNNotificationPresentationOptions {
        lock.withLock { storedOptions }
    }

    var sequence: Int {
        lock.withLock { storedSequence }
    }

    func record(_ options: UNNotificationPresentationOptions) {
        lock.withLock {
            storedOptions = options
            storedSequence = sequenceCounter.next()
        }
    }
}

private final class NotificationResponseCompletionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0

    var count: Int { lock.withLock { storedCount } }

    func record() {
        lock.withLock { storedCount += 1 }
    }
}

private actor NotificationDelegateReconcileRecorder {
    private let sequenceCounter: NotificationDelegateSequence
    private(set) var events: [AppLifecycleTrigger] = []
    private(set) var firstSequence = 0

    init(sequence: NotificationDelegateSequence) {
        sequenceCounter = sequence
    }

    func record(_ event: AppLifecycleTrigger) {
        if events.isEmpty {
            firstSequence = sequenceCounter.next()
        }
        events.append(event)
    }

    func waitForCount(_ count: Int) async {
        while events.count < count {
            await Task.yield()
        }
    }
}

private final class NotificationDelegateSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}
