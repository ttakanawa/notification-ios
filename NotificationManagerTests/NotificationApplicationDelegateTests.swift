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
        let completion = PresentationCompletionRecorder(sequence: sequence)

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
        let completion = PresentationCompletionRecorder(
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
    @Test func backgroundDuringWillPresentDoesNotRestartForegroundReconcile() async {
        let reconciles = LifecycleReconcileReasonRecorder()
        let lifecycle = AppLifecycleCoordinator(
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            requestReconcile: { await reconciles.record($0) },
            requestForegroundReconcile: { _ in await reconciles.record(.foreground) },
            enterBackground: { _ in await Task.yield() }
        )
        await lifecycle.handle(.foreground)
        await reconciles.reset()
        let delegate = NotificationApplicationDelegate(
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            reconcileAfterNotification: { await lifecycle.handle($0) }
        )

        delegate.presentationOptions(
            for: notificationRequest(reminderID: Self.reminderID)
        ) { _ in }
        await lifecycle.handle(.background)
        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(await reconciles.reasons.isEmpty)
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
    @Test func defaultTapUsesCurrentStoreAndRoutesCurrentEditEvenWhenURLExists() async {
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

        #expect(outcome == .reminderEdit(Self.reminderID))
        #expect(routes.destinations == [.reminderEdit(Self.reminderID)])
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
    @Test func openLinkWithoutACurrentValidURLFallsBackToCurrentEdit() async {
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

            #expect(outcome == .reminderEdit(Self.reminderID))
            #expect(routes.destinations == [.reminderEdit(Self.reminderID)])
            #expect(routes.openedURLs.isEmpty)
        }
    }

    @MainActor
    @Test func responsePreparationUsesOneCompleteSnapshotForLookupAndPublication() async {
        let expectedReminder = reminder(urlString: nil)
        let expectedSnapshot = CompleteReminderSnapshot(
            reminders: [expectedReminder],
            tags: []
        )
        let loader = ResponseSnapshotLoader(snapshots: [
            expectedSnapshot,
            CompleteReminderSnapshot(reminders: [], tags: [])
        ])
        let publications = ResponseSnapshotPublicationRecorder()
        let coordinator = LatestPresentationRefreshCoordinator<
            CompleteReminderSnapshot,
            Int
        >(
            loadSnapshot: { try? await loader.load() },
            publish: { snapshot, _ in publications.record(snapshot) }
        )
        let preparer = NotificationResponseSnapshotPreparer(
            prepareSnapshot: {
                await coordinator.refresh(state: 1)
            },
            coalesceSnapshot: { generation in
                await coordinator.latestTerminalResult(after: generation)
            }
        )

        let reminder = await preparer.prepare(reminderID: Self.reminderID)

        #expect(reminder == expectedReminder)
        #expect(await loader.loadCount == 1)
        #expect(publications.snapshots == [expectedSnapshot])
    }

    @MainActor
    @Test func routingSnapshotInvalidatesAnOlderSuspendedPresentationRefresh() async {
        let olderReminder = reminder(title: "Older projection", urlString: nil)
        let newerReminder = reminder(title: "Newer routing value", urlString: nil)
        let olderSnapshot = CompleteReminderSnapshot(
            reminders: [olderReminder],
            tags: []
        )
        let newerSnapshot = CompleteReminderSnapshot(
            reminders: [newerReminder],
            tags: []
        )
        let gate = ResponsePresentationSnapshotGate()
        let recorder = RoutingSnapshotProjectionRecorder()
        let coordinator = LatestPresentationRefreshCoordinator<
            CompleteReminderSnapshot,
            Int
        >(
            loadSnapshot: { await gate.load() },
            publish: { snapshot, state in
                recorder.publish(snapshot: snapshot, state: state)
            }
        )
        let preparer = NotificationResponseSnapshotPreparer(
            prepareSnapshot: {
                await coordinator.refresh(stateProvider: { 2 })
            },
            coalesceSnapshot: { generation in
                await coordinator.latestTerminalResult(after: generation)
            }
        )
        let olderRefresh = Task { @MainActor in
            await coordinator.refresh(state: 1)
        }
        await gate.waitForPendingCount(1)
        let routing = Task { @MainActor in
            await preparer.prepare(reminderID: Self.reminderID)
        }
        await gate.waitForPendingCount(2)

        await gate.resolve(attempt: 1, snapshot: newerSnapshot)
        let matchedReminder = await routing.value

        #expect(matchedReminder == newerReminder)
        #expect(recorder.publishedTitles == [["Newer routing value"]])
        #expect(recorder.publishedStates == [2])
        #expect(
            recorder.router.formModel(for: Self.reminderID)?.title
                == "Newer routing value"
        )

        await gate.resolve(attempt: 0, snapshot: olderSnapshot)
        _ = await olderRefresh.value

        #expect(recorder.publishedTitles == [["Newer routing value"]])
        #expect(recorder.publishedStates == [2])
        #expect(
            recorder.router.formModel(for: Self.reminderID)?.title
                == "Newer routing value"
        )
    }

    @MainActor
    @Test func newerLifecycleRefreshInvalidatesAnOlderSuspendedRoutingLookup() async {
        let staleURL = URL(string: "https://stale.example/path")!
        let currentURL = URL(string: "https://current.example/path")!
        let olderReminder = reminder(
            title: "Older routing value",
            urlString: staleURL.absoluteString
        )
        let newerReminder = reminder(
            title: "Newer lifecycle value",
            urlString: currentURL.absoluteString
        )
        let gate = ResponsePresentationSnapshotGate()
        let recorder = RoutingSnapshotProjectionRecorder()
        let routes = NotificationRouteRecorder()
        let coordinator = LatestPresentationRefreshCoordinator<
            CompleteReminderSnapshot,
            Int
        >(
            loadSnapshot: { await gate.load() },
            publish: { snapshot, state in
                recorder.publish(snapshot: snapshot, state: state)
            }
        )
        let preparer = NotificationResponseSnapshotPreparer(
            prepareSnapshot: {
                await coordinator.refresh(stateProvider: { 1 })
            },
            coalesceSnapshot: { generation in
                await coordinator.latestTerminalResult(after: generation)
            }
        )
        let delegate = NotificationApplicationDelegate(
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            reminderLookup: { reminderID in
                await preparer.prepare(reminderID: reminderID)
            },
            routeResponse: { routes.route($0) },
            openURL: { routes.open($0) },
            reconcileAfterNotification: { _ in }
        )
        let routing = Task { @MainActor in
            await delegate.handleResponse(
                actionIdentifier: NotificationApplicationDelegate
                    .openLinkActionIdentifier,
                categoryIdentifier: Self.openLinkCategory,
                userInfo: routingInfo(payloadURL: staleURL.absoluteString)
            )
        }
        await gate.waitForPendingCount(1)
        let lifecycle = Task { @MainActor in
            await coordinator.refresh(state: 2)
        }
        await gate.waitForPendingCount(2)

        await gate.resolve(
            attempt: 0,
            snapshot: CompleteReminderSnapshot(reminders: [olderReminder], tags: [])
        )
        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(routes.openedURLs.isEmpty)
        #expect(routes.destinations.isEmpty)

        await gate.resolve(
            attempt: 1,
            snapshot: CompleteReminderSnapshot(reminders: [newerReminder], tags: [])
        )
        _ = await lifecycle.value
        let outcome = await routing.value

        #expect(outcome == .openedURL(currentURL))
        #expect(routes.openedURLs == [currentURL])
        #expect(routes.destinations.isEmpty)
        #expect(recorder.publishedTitles == [["Newer lifecycle value"]])
        #expect(recorder.publishedStates == [2])
        #expect(
            recorder.router.formModel(for: Self.reminderID)?.title
                == "Newer lifecycle value"
        )
    }

    @MainActor
    @Test func supersededLookupImmediatelyCoalescesToAcceptedNewerSnapshot() async {
        let olderReminder = reminder(title: "Older routing value", urlString: nil)
        let newerReminder = reminder(title: "Newer lifecycle value", urlString: nil)
        let gate = ResponsePresentationSnapshotGate()
        let coordinator = LatestPresentationRefreshCoordinator<
            CompleteReminderSnapshot,
            Int
        >(
            loadSnapshot: { await gate.load() },
            publish: { _, _ in }
        )
        let preparer = NotificationResponseSnapshotPreparer(
            prepareSnapshot: {
                await coordinator.refresh(state: 1)
            },
            coalesceSnapshot: { generation in
                await coordinator.latestTerminalResult(after: generation)
            }
        )
        let routing = Task { @MainActor in
            await preparer.prepare(reminderID: Self.reminderID)
        }
        await gate.waitForPendingCount(1)
        let lifecycle = Task { @MainActor in
            await coordinator.refresh(state: 2)
        }
        await gate.waitForPendingCount(2)

        await gate.resolve(
            attempt: 1,
            snapshot: CompleteReminderSnapshot(reminders: [newerReminder], tags: [])
        )
        _ = await lifecycle.value
        await gate.resolve(
            attempt: 0,
            snapshot: CompleteReminderSnapshot(reminders: [olderReminder], tags: [])
        )

        #expect(await routing.value == newerReminder)
    }

    @MainActor
    @Test func currentUnavailableRefreshReleasesSupersededLookup() async {
        let olderReminder = reminder(title: "Older routing value", urlString: nil)
        let gate = ResponsePresentationSnapshotGate()
        let coalescing = ResponseCoalescingRecorder()
        let coordinator = LatestPresentationRefreshCoordinator<
            CompleteReminderSnapshot,
            Int
        >(
            loadSnapshot: { await gate.load() },
            publish: { _, _ in }
        )
        let preparer = NotificationResponseSnapshotPreparer(
            prepareSnapshot: {
                await coordinator.refresh(state: 1)
            },
            coalesceSnapshot: { generation in
                await coalescing.recordStart()
                return await coordinator.latestTerminalResult(after: generation)
            }
        )
        let routing = Task { @MainActor in
            await preparer.prepare(reminderID: Self.reminderID)
        }
        await gate.waitForPendingCount(1)
        let lifecycle = Task { @MainActor in
            await coordinator.refresh(state: 2)
        }
        await gate.waitForPendingCount(2)

        await gate.resolve(
            attempt: 0,
            snapshot: CompleteReminderSnapshot(reminders: [olderReminder], tags: [])
        )
        await coalescing.waitUntilStarted()
        await Task.yield()
        await gate.resolve(attempt: 1, snapshot: nil)

        #expect(await routing.value == nil)
        _ = await lifecycle.value
    }

    @MainActor
    @Test func cancellingCoalescedLookupDoesNotWaitForCurrentRefresh() async {
        let olderReminder = reminder(title: "Older routing value", urlString: nil)
        let newerReminder = reminder(title: "Newer lifecycle value", urlString: nil)
        let gate = ResponsePresentationSnapshotGate()
        let coalescing = ResponseCoalescingRecorder()
        let coordinator = LatestPresentationRefreshCoordinator<
            CompleteReminderSnapshot,
            Int
        >(
            loadSnapshot: { await gate.load() },
            publish: { _, _ in }
        )
        let preparer = NotificationResponseSnapshotPreparer(
            prepareSnapshot: {
                await coordinator.refresh(state: 1)
            },
            coalesceSnapshot: { generation in
                await coalescing.recordStart()
                return await coordinator.latestTerminalResult(after: generation)
            }
        )
        let routing = Task { @MainActor in
            await preparer.prepare(reminderID: Self.reminderID)
        }
        await gate.waitForPendingCount(1)
        let lifecycle = Task { @MainActor in
            await coordinator.refresh(state: 2)
        }
        await gate.waitForPendingCount(2)
        await gate.resolve(
            attempt: 0,
            snapshot: CompleteReminderSnapshot(reminders: [olderReminder], tags: [])
        )
        await coalescing.waitUntilStarted()
        await Task.yield()

        routing.cancel()
        #expect(await routing.value == nil)

        await gate.resolve(
            attempt: 1,
            snapshot: CompleteReminderSnapshot(reminders: [newerReminder], tags: [])
        )
        _ = await lifecycle.value
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
        #expect(
            routes.destinations == [
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
        #expect(
            await reconciles.triggers == [
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

        #expect(routes.destinations == [.reminderEdit(Self.reminderID)])
        #expect(await lookup.requestedIDs == [Self.reminderID])
        #expect(routes.openedURLs.isEmpty)
    }

    @MainActor
    @Test func nonisolatedIngressPreservesArrivalOrderAcrossBinding() async {
        let secondReminderID = UUID(
            uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        )!
        let events = OrderedNotificationResponseEvents()
        let lookup = BlockingFirstNotificationLookup(
            blockedReminderID: UUID(),
            events: events
        )
        let delegate = NotificationApplicationDelegate(
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            responseHandlingInitiallyBound: false
        )

        receiveFromNonisolatedNotificationCallback(
            delegate: delegate,
            reminderID: Self.reminderID,
            completion: { events.record("completion:\(Self.reminderID)") }
        )
        #expect(events.values == ["completion:\(Self.reminderID)"])

        delegate.bind(
            reminderLookup: { await lookup.reminder(id: $0) },
            routeResponse: { destination in
                events.record("route:\(destination.eventReminderID)")
            },
            openURL: { _ in events.record("open") },
            reconcileAfterNotification: { _ in events.record("reconcile") }
        )
        receiveFromNonisolatedNotificationCallback(
            delegate: delegate,
            reminderID: secondReminderID,
            completion: { events.record("completion:\(secondReminderID)") }
        )
        await events.waitForCount(8)

        #expect(
            events.values == [
                "completion:\(Self.reminderID)",
                "lookup:\(Self.reminderID)",
                "route:\(Self.reminderID)",
                "reconcile",
                "lookup:\(secondReminderID)",
                "route:\(secondReminderID)",
                "completion:\(secondReminderID)",
                "reconcile"
            ])
    }

    @MainActor
    @Test func boundResponsesStayFIFOAndCompleteBeforeEachReconcile() async {
        let secondReminderID = UUID(
            uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        )!
        let events = OrderedNotificationResponseEvents()
        let lookup = BlockingFirstNotificationLookup(
            blockedReminderID: Self.reminderID,
            events: events
        )
        let delegate = NotificationApplicationDelegate(
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            reminderLookup: { await lookup.reminder(id: $0) },
            routeResponse: { destination in
                events.record("route:\(destination.eventReminderID)")
            },
            openURL: { _ in events.record("open") },
            reconcileAfterNotification: { _ in events.record("reconcile") }
        )

        delegate.receiveResponse(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            categoryIdentifier: "",
            userInfo: [
                NotificationApplicationDelegate.reminderIDKey:
                    Self.reminderID.uuidString.lowercased()
            ],
            completion: { events.record("completion:\(Self.reminderID)") }
        )
        await lookup.waitUntilBlockedLookupStarts()
        delegate.receiveResponse(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            categoryIdentifier: "",
            userInfo: [
                NotificationApplicationDelegate.reminderIDKey:
                    secondReminderID.uuidString.lowercased()
            ],
            completion: { events.record("completion:\(secondReminderID)") }
        )

        for _ in 0..<50 {
            await Task.yield()
        }
        #expect(events.values == ["lookup:\(Self.reminderID)"])

        await lookup.releaseBlockedLookup()
        await events.waitForCount(8)

        #expect(
            events.values == [
                "lookup:\(Self.reminderID)",
                "route:\(Self.reminderID)",
                "completion:\(Self.reminderID)",
                "reconcile",
                "lookup:\(secondReminderID)",
                "route:\(secondReminderID)",
                "completion:\(secondReminderID)",
                "reconcile"
            ])
    }

    @MainActor
    @Test func backgroundDuringResponseLookupDoesNotRestartForegroundReconcile() async {
        let events = OrderedNotificationResponseEvents()
        let lookup = BlockingFirstNotificationLookup(
            blockedReminderID: Self.reminderID,
            events: events
        )
        let reconciles = LifecycleReconcileReasonRecorder()
        let lifecycle = AppLifecycleCoordinator(
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            requestReconcile: { await reconciles.record($0) },
            requestForegroundReconcile: { _ in await reconciles.record(.foreground) },
            enterBackground: { _ in }
        )
        await lifecycle.handle(.foreground)
        await reconciles.reset()
        let completion = NotificationResponseCompletionRecorder()
        let delegate = NotificationApplicationDelegate(
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            reminderLookup: { await lookup.reminder(id: $0) },
            routeResponse: { _ in },
            openURL: { _ in },
            reconcileAfterNotification: { await lifecycle.handle($0) }
        )

        delegate.receiveResponse(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            categoryIdentifier: "",
            userInfo: routingInfo(payloadURL: "https://stale.example/secret"),
            completion: { completion.record() }
        )
        await lookup.waitUntilBlockedLookupStarts()
        await lifecycle.handle(.background)
        await lookup.releaseBlockedLookup()
        while !completion.hasRecordedResponse {
            await Task.yield()
        }

        #expect(await reconciles.reasons.isEmpty)
    }

    @MainActor
    @Test func coldLaunchResponseQueueIsBoundedAndReplaysInFIFOOrder() async throws {
        let lookup = NotificationLookupRecorder(reminder: nil)
        let routes = NotificationRouteRecorder()
        let completion = NotificationResponseCompletionRecorder()
        let delegate = NotificationApplicationDelegate(
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            responseHandlingInitiallyBound: false
        )
        let identifiers = try (0...NotificationApplicationDelegate.pendingResponseLimit).map {
            try #require(
                UUID(
                    uuidString: String(
                        format: "00000000-0000-0000-0000-%012x",
                        $0
                    )))
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
        #expect(
            await reconciles.triggers == [
                .notificationResponseCompleted,
                .notificationResponseCompleted,
                .notificationResponseCompleted
            ])
    }

    @MainActor
    @Test func neutralAndSettingsRoutesClearSelectionAcrossAdaptiveTransitions() {
        let actions = ReminderActionCoordinator(
            handlers: ReminderActionHandlers(
                setEnabled: { command in .saved(command.reminderID) },
                delete: { _ in }
            ))
        let router = AppRouter(actions: actions)
        router.register(
            form: ReminderFormModel(
                snapshot: reminder(title: "Selected reminder", urlString: nil),
                savedRepeatPresentation: nil,
                now: Date(timeIntervalSince1970: 1),
                actions: ReminderFormActions(
                    save: { draft, _, _ in .saved(draft.id) },
                    delete: { _ in }
                )
            ))

        router.showReminder(Self.reminderID)
        #expect(router.selectedReminderID == Self.reminderID)
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

    private func reminder(
        title: String = "Current title",
        urlString: String?
    ) -> ReminderSnapshot {
        ReminderSnapshot(
            id: Self.reminderID,
            title: title,
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
        ReminderActionCoordinator(
            handlers: ReminderActionHandlers(
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

private func requireStrictNonisolatedNotificationDelegateWitnesses(
    delegate: NotificationApplicationDelegate,
    center: UNUserNotificationCenter,
    notification: UNNotification,
    response: UNNotificationResponse,
    presentationCompletion:
        @escaping @Sendable (
            UNNotificationPresentationOptions
        ) -> Void,
    responseCompletion: @escaping @Sendable () -> Void
) {
    delegate.userNotificationCenter(
        center,
        willPresent: notification,
        withCompletionHandler: presentationCompletion
    )
    delegate.userNotificationCenter(
        center,
        didReceive: response,
        withCompletionHandler: responseCompletion
    )
}

private func receiveFromNonisolatedNotificationCallback(
    delegate: NotificationApplicationDelegate,
    reminderID: UUID,
    completion: @escaping @Sendable () -> Void
) {
    delegate.receiveResponse(
        actionIdentifier: UNNotificationDefaultActionIdentifier,
        categoryIdentifier: "",
        userInfo: [
            NotificationApplicationDelegate.reminderIDKey:
                reminderID.uuidString.lowercased()
        ],
        completion: completion
    )
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

private actor ResponseSnapshotLoader {
    private var snapshots: [CompleteReminderSnapshot]
    private(set) var loadCount = 0

    init(snapshots: [CompleteReminderSnapshot]) {
        self.snapshots = snapshots
    }

    func load() throws -> CompleteReminderSnapshot {
        loadCount += 1
        guard !snapshots.isEmpty else {
            throw ResponseSnapshotTestFailure.exhausted
        }
        return snapshots.removeFirst()
    }
}

@MainActor
private final class ResponseSnapshotPublicationRecorder {
    private(set) var snapshots: [CompleteReminderSnapshot] = []

    func record(_ snapshot: CompleteReminderSnapshot) {
        snapshots.append(snapshot)
    }
}

private actor ResponsePresentationSnapshotGate {
    private var nextAttempt = 0
    private var pending: [Int: CheckedContinuation<CompleteReminderSnapshot?, Never>] = [:]

    func load() async -> CompleteReminderSnapshot? {
        let attempt = nextAttempt
        nextAttempt += 1
        return await withCheckedContinuation { continuation in
            pending[attempt] = continuation
        }
    }

    func waitForPendingCount(_ count: Int) async {
        while pending.count < count {
            await Task.yield()
        }
    }

    func resolve(attempt: Int, snapshot: CompleteReminderSnapshot?) {
        pending.removeValue(forKey: attempt)?.resume(returning: snapshot)
    }
}

private actor ResponseCoalescingRecorder {
    private var didStart = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func recordStart() {
        didStart = true
        let currentWaiters = waiters
        waiters.removeAll()
        for waiter in currentWaiters {
            waiter.resume()
        }
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

@MainActor
private final class RoutingSnapshotProjectionRecorder {
    let router: AppRouter
    private(set) var publishedTitles: [[String]] = []
    private(set) var publishedStates: [Int] = []

    init() {
        router = AppRouter(
            actions: ReminderActionCoordinator(
                handlers: ReminderActionHandlers(
                    setEnabled: { command in .saved(command.reminderID) },
                    delete: { _ in }
                )
            ))
    }

    func publish(snapshot: CompleteReminderSnapshot, state: Int) {
        router.prunePersistedReminders(keeping: Set(snapshot.reminders.map(\.id)))
        for reminder in snapshot.reminders {
            router.registerFormIfAbsent(
                ReminderFormModel(
                    snapshot: reminder,
                    savedRepeatPresentation: nil,
                    now: reminder.updatedAt,
                    actions: ReminderFormActions(
                        save: { draft, _, _ in .saved(draft.id) },
                        delete: { _ in }
                    )
                ))
        }
        publishedTitles.append(snapshot.reminders.map(\.title))
        publishedStates.append(state)
    }
}

private enum ResponseSnapshotTestFailure: Error {
    case exhausted
}

private actor BlockingFirstNotificationLookup {
    private let blockedReminderID: UUID
    private let events: OrderedNotificationResponseEvents
    private var blockedLookupStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(
        blockedReminderID: UUID,
        events: OrderedNotificationResponseEvents
    ) {
        self.blockedReminderID = blockedReminderID
        self.events = events
    }

    func reminder(id: UUID) async -> ReminderSnapshot? {
        events.record("lookup:\(id)")
        if id == blockedReminderID {
            blockedLookupStarted = true
            let waiters = startWaiters
            startWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }
        return ReminderSnapshot(
            id: id,
            title: "Current",
            notes: nil,
            urlString: nil,
            enabled: true,
            schedule: .corrupt(originalData: Data([0xff])),
            tagIDs: [],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
    }

    func waitUntilBlockedLookupStarts() async {
        guard !blockedLookupStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseBlockedLookup() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private final class OrderedNotificationResponseEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String] = []

    var values: [String] { lock.withLock { storedValues } }

    func record(_ value: String) {
        lock.withLock { storedValues.append(value) }
    }

    func waitForCount(_ count: Int) async {
        while values.count < count {
            await Task.yield()
        }
    }
}

extension NotificationResponseDestination {
    fileprivate var eventReminderID: UUID {
        switch self {
        case .reminderEdit(let reminderID):
            reminderID
        case .notificationUnavailable:
            UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
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

private actor LifecycleReconcileReasonRecorder {
    private(set) var reasons: [ReconcileReason] = []

    func record(_ reason: ReconcileReason) {
        reasons.append(reason)
    }

    func reset() {
        reasons.removeAll()
    }
}

extension Array {
    @MainActor
    fileprivate func asyncMap<T: Sendable>(
        _ transform: @MainActor (Element) async -> T
    ) async -> [T] {
        var result: [T] = []
        for element in self {
            result.append(await transform(element))
        }
        return result
    }
}

private final class PresentationCompletionRecorder: @unchecked Sendable {
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
    var hasRecordedResponse: Bool { lock.withLock { storedCount > 0 } }

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
