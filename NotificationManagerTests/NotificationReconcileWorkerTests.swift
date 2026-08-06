import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import Testing
import UserNotifications
@testable import NotificationManager

struct NotificationReconcileWorkerTests {
    @Test(arguments: [
        CompleteSchedulingSnapshotLoadError.fetch,
        .relationshipTraversal,
        .classification
    ])
    func incompleteSnapshotNeverTouchesNotificationInventory(
        error: CompleteSchedulingSnapshotLoadError
    ) async {
        let center = NotificationCenterClientSpy()
        let worker = NotificationReconcileWorker(
            snapshotLoader: FailingSchedulingSnapshotLoader(error: error),
            preferenceStore: FixedDeviceNotificationPreferenceStore(enabled: true),
            authorizationProvider: FixedNotificationAuthorizationProvider(.allowed),
            notificationCenter: center,
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            stateStore: DeviceSchedulingStateStore()
        )

        await worker.requestReconcile(.modelChanged)
        await worker.waitUntilIdle()

        #expect(await center.recordedCalls().isEmpty)
    }

    @Test func completeLoaderRejectsDanglingRelationshipsAndDuplicateIdentities() async {
        let missingTagID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let danglingReminder = validReminder(tagIDs: [missingTagID])
        let relationshipLoader = CompleteSchedulingSnapshotLoader(
            repository: SnapshotRepositoryStub(snapshot: CompleteReminderSnapshot(
                reminders: [danglingReminder],
                tags: []
            ))
        )

        await #expect(throws: CompleteSchedulingSnapshotLoadError.relationshipTraversal) {
            try await relationshipLoader.loadCompleteSnapshot()
        }

        let duplicate = validReminder()
        let classificationLoader = CompleteSchedulingSnapshotLoader(
            repository: SnapshotRepositoryStub(snapshot: CompleteReminderSnapshot(
                reminders: [duplicate, duplicate],
                tags: []
            ))
        )
        await #expect(throws: CompleteSchedulingSnapshotLoadError.classification) {
            try await classificationLoader.loadCompleteSnapshot()
        }
    }

    @Test func classifiedUnsupportedAndCorruptItemsRemainACompleteSnapshot() async throws {
        let unsupported = validReminder(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            schedule: .unsupportedFuture(version: 9, originalData: Data([9]))
        )
        let corrupt = validReminder(
            id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            schedule: .corrupt(originalData: Data([0xff]))
        )
        let expected = CompleteReminderSnapshot(reminders: [unsupported, corrupt], tags: [])
        let loader = CompleteSchedulingSnapshotLoader(
            repository: SnapshotRepositoryStub(snapshot: expected)
        )

        let loaded = try await loader.loadCompleteSnapshot()

        #expect(loaded == expected)
    }

    @Test func concreteWorkerExcludesEveryInvalidScheduleAndCleansOwnedPending() async throws {
        let reminders = [
            validReminder(
                id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
                schedule: .unsupportedFuture(version: 9, originalData: Data([9]))
            ),
            validReminder(
                id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
                schedule: .corrupt(originalData: Data([0xff]))
            ),
            validReminder(
                id: "cccccccc-cccc-cccc-cccc-cccccccccccc",
                schedule: .domainInvalid(
                    repairSeed: ScheduleRepairSeed(),
                    originalData: Data([1]),
                    issues: [.invalidTimeZone]
                )
            )
        ]
        let identifiers = try reminders.map {
            try NotificationIdentifierCodec().oneShotIdentifier(
                reminderID: $0.id,
                alertInstant: testDate("2040-08-31T13:30:00Z")
            )
        }
        let unrelated = "other-app.notification"
        let center = NotificationCenterClientSpy(pending: identifiers.map {
            NotificationInventoryItem(identifier: $0)
        } + [NotificationInventoryItem(identifier: unrelated)])
        let worker = NotificationReconcileWorker(
            snapshotLoader: CompleteSchedulingSnapshotLoader(
                repository: SnapshotRepositoryStub(snapshot: CompleteReminderSnapshot(
                    reminders: reminders,
                    tags: []
                ))
            ),
            preferenceStore: FixedDeviceNotificationPreferenceStore(enabled: true),
            authorizationProvider: FixedNotificationAuthorizationProvider(.allowed),
            notificationCenter: center,
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            stateStore: DeviceSchedulingStateStore(),
            recurrenceEnvironmentProvider: { .foundation },
            localeProvider: { Locale(identifier: "en_US") },
            clock: NotificationReconcileClock(
                now: { testDate("2040-08-01T00:00:00Z") },
                sleep: { _ in }
            ),
            retryDelays: []
        )

        await worker.requestReconcile(.foreground)
        await worker.waitUntilIdle()

        #expect(await center.addedIdentifiers().isEmpty)
        #expect(await center.pendingIdentifiers() == [unrelated])
        #expect(await center.recordedCalls() == [
            "pending",
            "remove-pending:\(identifiers.sorted().joined(separator: ","))"
        ])
    }

    @Test func validEmptySnapshotCleansOnlyAppOwnedPendingWithoutReadingDelivered() async {
        let stale = "notification-manager.local.v2.future"
        let unrelated = "other-app.notification"
        let center = NotificationCenterClientSpy(pending: [
            NotificationInventoryItem(identifier: stale),
            NotificationInventoryItem(identifier: unrelated)
        ], delivered: [NotificationInventoryItem(identifier: stale)])
        let worker = NotificationReconcileWorker(
            snapshotLoader: FixedSchedulingSnapshotLoader(
                CompleteReminderSnapshot(reminders: [], tags: [])
            ),
            preferenceStore: FixedDeviceNotificationPreferenceStore(enabled: true),
            authorizationProvider: FixedNotificationAuthorizationProvider(.allowed),
            notificationCenter: center,
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            stateStore: DeviceSchedulingStateStore()
        )

        await worker.requestReconcile(.foreground)
        await worker.waitUntilIdle()

        #expect(await center.recordedCalls() == [
            "pending",
            "remove-pending:\(stale)"
        ])
        #expect(await center.pendingIdentifiers() == [unrelated])
    }

    @Test(arguments: [
        DeviceGateFixture(enabled: false, authorization: .allowed),
        DeviceGateFixture(enabled: true, authorization: .denied)
    ])
    func deviceOrPermissionOffStillCleansPendingWithoutDeliveredMutation(
        gate: DeviceGateFixture
    ) async {
        let appOwned = "notification-manager.local.v7.stale"
        let center = NotificationCenterClientSpy(
            pending: [NotificationInventoryItem(identifier: appOwned)],
            delivered: [NotificationInventoryItem(identifier: appOwned)]
        )
        let stateStore = DeviceSchedulingStateStore()
        let worker = NotificationReconcileWorker(
            snapshotLoader: FixedSchedulingSnapshotLoader(CompleteReminderSnapshot(
                reminders: [validReminder()],
                tags: []
            )),
            preferenceStore: FixedDeviceNotificationPreferenceStore(enabled: gate.enabled),
            authorizationProvider: FixedNotificationAuthorizationProvider(gate.authorization),
            notificationCenter: center,
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            stateStore: stateStore,
            planner: FixedNotificationPlanner(plan: plan(requests: [], outcomes: [:])),
            materializer: RecordingNotificationMaterializer { logical, _ in
                notificationRequest(identifier: logical.identifier)
            },
            recurrenceEnvironmentProvider: { .foundation },
            localeProvider: { Locale(identifier: "en_US") },
            clock: NotificationReconcileClock(
                now: { testDate("2040-08-01T00:00:00Z") },
                sleep: { _ in }
            ),
            retryDelays: []
        )

        await worker.requestReconcile(.foreground)
        await worker.waitUntilIdle()

        #expect(await center.recordedCalls() == [
            "pending",
            "remove-pending:\(appOwned)"
        ])
        #expect(await center.deliveredIdentifiers() == [appOwned])
        let state = await stateStore.snapshot()
        #expect(state.deviceNotificationsEnabled == gate.enabled)
        #expect(state.authorization.state == gate.authorization)
    }

    @Test func desiredIdentifierIsReaddedForReplacementAfterStalePendingCleanup() async throws {
        let reminder = validReminder()
        let desired = try oneShotRequest(
            reminderID: reminder.id,
            alertInstant: testDate("2040-08-31T13:30:00Z"),
            baseInstant: testDate("2040-08-31T13:30:00Z")
        )
        let stale = "notification-manager.local.v3.stale"
        let unrelated = "another-app.request"
        let center = NotificationCenterClientSpy(pending: [
            NotificationInventoryItem(identifier: desired.identifier),
            NotificationInventoryItem(identifier: stale),
            NotificationInventoryItem(identifier: unrelated)
        ])
        let planner = FixedNotificationPlanner(plan: plan(
            requests: [desired],
            outcomes: desired.contributingGroupIDs.reduce(into: [:]) {
                $0[$1] = .scheduled
            }
        ))
        let materializer = RecordingNotificationMaterializer { logical, _ in
            notificationRequest(identifier: logical.identifier, title: "fresh content")
        }
        let worker = testWorker(
            snapshot: CompleteReminderSnapshot(reminders: [reminder], tags: []),
            center: center,
            planner: planner,
            materializer: materializer,
            clock: SequenceReconcileClock([
                testDate("2040-08-01T00:00:00Z"),
                testDate("2040-08-02T00:00:00Z")
            ]),
            triggerInspector: { request in
                NotificationTriggerInspection(
                    repeats: false,
                    nextTriggerDate: request.identifier == desired.identifier
                        ? testDate("2040-08-31T13:30:00Z") : nil
                )
            }
        )

        await worker.requestReconcile(.foreground)
        await worker.waitUntilIdle()

        #expect(await center.recordedCalls() == [
            "pending",
            "remove-pending:\(stale)",
            "add:\(desired.identifier)"
        ])
        #expect(await center.addedTitles() == ["fresh content"])
        #expect(await center.pendingIdentifiers() == [
            desired.identifier,
            unrelated
        ])
    }

    @Test func materializationFailureMarksEverySharedContributorWithoutRollingBackSuccess() async throws {
        let reminder = validReminder()
        let groupA = AlertGroupID(
            reminderID: reminder.id,
            baseOccurrenceInstant: testDate("2040-08-31T13:30:00Z")
        )
        let groupB = AlertGroupID(
            reminderID: reminder.id,
            baseOccurrenceInstant: testDate("2040-09-01T13:30:00Z")
        )
        let groupC = AlertGroupID(
            reminderID: reminder.id,
            baseOccurrenceInstant: testDate("2040-09-02T13:30:00Z")
        )
        let shared = try oneShotRequest(
            reminderID: reminder.id,
            alertInstant: testDate("2040-08-31T13:30:00Z"),
            baseInstant: groupA.baseOccurrenceInstant,
            contributors: [groupA, groupB]
        )
        let success = try oneShotRequest(
            reminderID: reminder.id,
            alertInstant: testDate("2040-09-02T13:30:00Z"),
            baseInstant: groupC.baseOccurrenceInstant
        )
        let stateStore = DeviceSchedulingStateStore()
        let center = NotificationCenterClientSpy(pending: [
            NotificationInventoryItem(identifier: shared.identifier)
        ])
        let materializer = RecordingNotificationMaterializer { logical, _ in
            if logical.identifier == shared.identifier {
                throw TestFailure.materialization
            }
            return notificationRequest(identifier: logical.identifier)
        }
        let worker = testWorker(
            snapshot: CompleteReminderSnapshot(reminders: [reminder], tags: []),
            center: center,
            planner: FixedNotificationPlanner(plan: plan(
                requests: [shared, success],
                outcomes: [groupA: .scheduled, groupB: .scheduled, groupC: .scheduled]
            )),
            materializer: materializer,
            stateStore: stateStore,
            clock: SequenceReconcileClock([
                testDate("2040-08-01T00:00:00Z"),
                testDate("2040-08-02T00:00:00Z")
            ]),
            triggerInspector: { request in
                NotificationTriggerInspection(
                    repeats: false,
                    nextTriggerDate: request.identifier == success.identifier
                        ? testDate("2040-09-02T13:30:00Z") : nil
                )
            }
        )

        await worker.requestReconcile(.foreground)
        await worker.waitUntilIdle()

        #expect(await stateStore.outcome(for: groupA) == .unscheduledError)
        #expect(await stateStore.outcome(for: groupB) == .unscheduledError)
        #expect(await stateStore.outcome(for: groupC) == .scheduled)
        #expect(await center.addedIdentifiers() == [success.identifier])
        #expect(await center.pendingIdentifiers() == [success.identifier])
    }

    @Test func addFailureFansOutAndKeepsPreviouslyAddedRequest() async throws {
        let reminder = validReminder()
        let first = try oneShotRequest(
            reminderID: reminder.id,
            alertInstant: testDate("2040-08-31T13:30:00Z"),
            baseInstant: testDate("2040-08-31T13:30:00Z")
        )
        let second = try oneShotRequest(
            reminderID: reminder.id,
            alertInstant: testDate("2040-09-01T13:30:00Z"),
            baseInstant: testDate("2040-09-01T13:30:00Z")
        )
        let firstGroup = try #require(first.contributingGroupIDs.first)
        let secondGroup = try #require(second.contributingGroupIDs.first)
        let stateStore = DeviceSchedulingStateStore()
        let center = NotificationCenterClientSpy(addFailures: [second.identifier])
        let worker = testWorker(
            snapshot: CompleteReminderSnapshot(reminders: [reminder], tags: []),
            center: center,
            planner: FixedNotificationPlanner(plan: plan(
                requests: [first, second],
                outcomes: [firstGroup: .scheduled, secondGroup: .scheduled]
            )),
            materializer: RecordingNotificationMaterializer { logical, _ in
                notificationRequest(identifier: logical.identifier)
            },
            stateStore: stateStore,
            clock: SequenceReconcileClock([
                testDate("2040-08-01T00:00:00Z"),
                testDate("2040-08-02T00:00:00Z"),
                testDate("2040-08-02T00:00:01Z")
            ]),
            triggerInspector: { request in
                NotificationTriggerInspection(
                    repeats: false,
                    nextTriggerDate: request.identifier == first.identifier
                        ? testDate("2040-08-31T13:30:00Z")
                        : testDate("2040-09-01T13:30:00Z")
                )
            }
        )

        await worker.requestReconcile(.foreground)
        await worker.waitUntilIdle()

        #expect(await stateStore.outcome(for: firstGroup) == .scheduled)
        #expect(await stateStore.outcome(for: secondGroup) == .unscheduledError)
        #expect(await center.addedIdentifiers() == [first.identifier])
    }

    @Test func dispatchSmokeFailuresMarkOneShotAndRepeatingContributors() async throws {
        let reminder = validReminder()
        let oneShot = try oneShotRequest(
            reminderID: reminder.id,
            alertInstant: testDate("2040-08-31T13:30:00Z"),
            baseInstant: testDate("2040-08-31T13:30:00Z")
        )
        let repeating = repeatingRequest(
            reminderID: reminder.id,
            baseInstant: testDate("2040-09-01T13:30:00Z")
        )
        let oneShotGroup = try #require(oneShot.contributingGroupIDs.first)
        let repeatingGroup = try #require(repeating.contributingGroupIDs.first)
        let stateStore = DeviceSchedulingStateStore()
        let center = NotificationCenterClientSpy()
        let worker = testWorker(
            snapshot: CompleteReminderSnapshot(reminders: [reminder], tags: []),
            center: center,
            planner: FixedNotificationPlanner(plan: plan(
                requests: [oneShot, repeating],
                outcomes: [oneShotGroup: .scheduled, repeatingGroup: .scheduled]
            )),
            materializer: RecordingNotificationMaterializer { logical, _ in
                notificationRequest(identifier: logical.identifier)
            },
            stateStore: stateStore,
            clock: SequenceReconcileClock([
                testDate("2040-08-01T00:00:00Z"),
                testDate("2040-08-02T00:00:00Z"),
                testDate("2040-08-02T00:00:01Z")
            ]),
            triggerInspector: { request in
                if request.identifier == oneShot.identifier {
                    return NotificationTriggerInspection(
                        repeats: false,
                        nextTriggerDate: testDate("2040-08-31T13:30:01Z")
                    )
                }
                return NotificationTriggerInspection(repeats: true, nextTriggerDate: nil)
            }
        )

        await worker.requestReconcile(.foreground)
        await worker.waitUntilIdle()

        #expect(await stateStore.outcome(for: oneShotGroup) == .unscheduledError)
        #expect(await stateStore.outcome(for: repeatingGroup) == .unscheduledError)
        #expect(await center.addedIdentifiers().isEmpty)
    }

    @Test func plannerClassifiedRequestFailureIsPublishedWithoutInventingARequest() async {
        let reminder = validReminder()
        let group = AlertGroupID(
            reminderID: reminder.id,
            baseOccurrenceInstant: testDate("2040-08-31T13:30:00Z")
        )
        let stateStore = DeviceSchedulingStateStore()
        let center = NotificationCenterClientSpy()
        let worker = testWorker(
            snapshot: CompleteReminderSnapshot(reminders: [reminder], tags: []),
            center: center,
            planner: FixedNotificationPlanner(plan: plan(
                requests: [],
                outcomes: [group: .unscheduledError]
            )),
            materializer: RecordingNotificationMaterializer { logical, _ in
                notificationRequest(identifier: logical.identifier)
            },
            stateStore: stateStore,
            clock: SequenceReconcileClock([testDate("2040-08-01T00:00:00Z")]),
            triggerInspector: { _ in
                NotificationTriggerInspection(repeats: false, nextTriggerDate: nil)
            }
        )

        await worker.requestReconcile(.foreground)
        await worker.waitUntilIdle()

        #expect(await stateStore.outcome(for: group) == .unscheduledError)
        #expect(await center.recordedCalls() == ["pending"])
    }

    @Test func globalPlanningFailureStopsBeforeInventoryAndStalesEligibility() async {
        let eligibility = ForegroundEligibilityIndexStore()
        let reminder = validReminder()
        eligibility.publish(eligibleReminderIDs: [reminder.id])
        let stateStore = DeviceSchedulingStateStore()
        let center = NotificationCenterClientSpy()
        let worker = NotificationReconcileWorker(
            snapshotLoader: FixedSchedulingSnapshotLoader(
                CompleteReminderSnapshot(reminders: [reminder], tags: [])
            ),
            preferenceStore: FixedDeviceNotificationPreferenceStore(enabled: true),
            authorizationProvider: FixedNotificationAuthorizationProvider(.allowed),
            notificationCenter: center,
            eligibilityIndexStore: eligibility,
            stateStore: stateStore,
            planner: ThrowingNotificationPlanner(),
            materializer: RecordingNotificationMaterializer { logical, _ in
                notificationRequest(identifier: logical.identifier)
            },
            recurrenceEnvironmentProvider: { .foundation },
            localeProvider: { Locale(identifier: "en_US") },
            clock: NotificationReconcileClock(
                now: { testDate("2040-08-01T00:00:00Z") },
                sleep: { _ in }
            ),
            retryDelays: []
        )

        await worker.requestReconcile(.foreground)
        await worker.waitUntilIdle()

        #expect(await center.recordedCalls().isEmpty)
        #expect(eligibility.snapshot().isStale)
        #expect(await stateStore.snapshot().globalFailure == .planning)
    }

    @Test func pendingInventoryFailureDoesNotRemoveOrAddAndPublishesGlobalFailure() async throws {
        let reminder = validReminder()
        let logical = try oneShotRequest(
            reminderID: reminder.id,
            alertInstant: testDate("2040-08-31T13:30:00Z"),
            baseInstant: testDate("2040-08-31T13:30:00Z")
        )
        let stateStore = DeviceSchedulingStateStore()
        let eligibility = ForegroundEligibilityIndexStore()
        let center = NotificationCenterClientSpy(pendingFailure: true)
        let worker = testWorker(
            snapshot: CompleteReminderSnapshot(reminders: [reminder], tags: []),
            center: center,
            planner: FixedNotificationPlanner(plan: plan(
                requests: [logical],
                outcomes: logical.contributingGroupIDs.reduce(into: [:]) {
                    $0[$1] = .scheduled
                }
            )),
            materializer: RecordingNotificationMaterializer { logical, _ in
                notificationRequest(identifier: logical.identifier)
            },
            eligibilityIndexStore: eligibility,
            stateStore: stateStore,
            clock: SequenceReconcileClock([testDate("2040-08-01T00:00:00Z")]),
            triggerInspector: { _ in
                NotificationTriggerInspection(repeats: false, nextTriggerDate: nil)
            }
        )

        await worker.requestReconcile(.foreground)
        await worker.waitUntilIdle()

        #expect(await center.recordedCalls() == ["pending"])
        #expect(await center.addedIdentifiers().isEmpty)
        #expect(await stateStore.snapshot().globalFailure == .inventory)
        #expect(eligibility.isEligible(reminder.id))
    }

    @Test func passInputsStayFixedAndEveryRequestMaterializesBeforeInventory() async throws {
        let reminder = validReminder()
        let first = try oneShotRequest(
            reminderID: reminder.id,
            alertInstant: testDate("2040-08-31T13:30:00Z"),
            baseInstant: testDate("2040-08-31T13:30:00Z")
        )
        let second = try oneShotRequest(
            reminderID: reminder.id,
            alertInstant: testDate("2040-09-01T13:30:00Z"),
            baseInstant: testDate("2040-09-01T13:30:00Z")
        )
        let eventLog = OrderedEventLog()
        let environment = MarkerRecurrenceEnvironment()
        let planner = PassRecordingPlanner(
            plan: plan(
                requests: [first, second],
                outcomes: (first.contributingGroupIDs.union(second.contributingGroupIDs))
                    .reduce(into: [:]) { $0[$1] = .scheduled }
            ),
            eventLog: eventLog
        )
        let materializer = PassRecordingMaterializer(eventLog: eventLog)
        let preferences = CountingPreferenceStore(enabled: true)
        let authorization = CountingAuthorizationProvider(.allowed)
        let environmentCalls = LockedCounter()
        let localeCalls = LockedCounter()
        let center = NotificationCenterClientSpy(onCall: { eventLog.append($0) })
        let evaluationNow = testDate("2040-08-01T00:00:00Z")
        let worker = NotificationReconcileWorker(
            snapshotLoader: FixedSchedulingSnapshotLoader(
                CompleteReminderSnapshot(reminders: [reminder], tags: [])
            ),
            preferenceStore: preferences,
            authorizationProvider: authorization,
            notificationCenter: center,
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            stateStore: DeviceSchedulingStateStore(),
            planner: planner,
            materializer: materializer,
            recurrenceEnvironmentProvider: {
                environmentCalls.increment()
                return environment
            },
            localeProvider: {
                localeCalls.increment()
                return Locale(identifier: "ja_JP")
            },
            clock: SequenceReconcileClock([
                evaluationNow,
                testDate("2040-08-02T00:00:00Z"),
                testDate("2040-08-02T00:00:01Z")
            ]).value,
            retryDelays: [],
            triggerInspector: { request in
                NotificationTriggerInspection(
                    repeats: false,
                    nextTriggerDate: request.identifier == first.identifier
                        ? testDate("2040-08-31T13:30:00Z")
                        : testDate("2040-09-01T13:30:00Z")
                )
            }
        )

        await worker.requestReconcile(.foreground)
        await worker.waitUntilIdle()

        #expect(eventLog.values.prefix(4) == [
            "plan",
            "materialize:\(first.identifier)",
            "materialize:\(second.identifier)",
            "pending"
        ])
        #expect(planner.evaluationNow == evaluationNow)
        #expect(planner.environmentIdentity == ObjectIdentifier(environment))
        #expect(materializer.evaluationNows == [evaluationNow, evaluationNow])
        #expect(materializer.environmentIdentities == [
            ObjectIdentifier(environment),
            ObjectIdentifier(environment)
        ])
        #expect(materializer.localeIdentifiers == ["ja_JP", "ja_JP"])
        #expect(await preferences.readCount == 1)
        #expect(await authorization.readCount == 1)
        #expect(environmentCalls.value == 1)
        #expect(localeCalls.value == 1)
    }

    @Test func crossedOneShotBoundaryReplansLatestStateInsteadOfAddingCatchUp() async throws {
        let reminder = validReminder()
        let crossed = try oneShotRequest(
            reminderID: reminder.id,
            alertInstant: testDate("2040-08-31T13:30:00Z"),
            baseInstant: testDate("2040-08-31T13:30:00Z")
        )
        let latest = try oneShotRequest(
            reminderID: reminder.id,
            alertInstant: testDate("2040-09-01T13:30:00Z"),
            baseInstant: testDate("2040-09-01T13:30:00Z")
        )
        let planner = SequenceNotificationPlanner([
            plan(
                requests: [crossed],
                outcomes: crossed.contributingGroupIDs.reduce(into: [:]) {
                    $0[$1] = .scheduled
                }
            ),
            plan(
                requests: [latest],
                outcomes: latest.contributingGroupIDs.reduce(into: [:]) {
                    $0[$1] = .scheduled
                }
            )
        ])
        let center = NotificationCenterClientSpy()
        let worker = testWorker(
            snapshot: CompleteReminderSnapshot(reminders: [reminder], tags: []),
            center: center,
            planner: planner,
            materializer: RecordingNotificationMaterializer { logical, _ in
                notificationRequest(identifier: logical.identifier)
            },
            clock: SequenceReconcileClock([
                testDate("2040-08-31T13:29:59Z"),
                testDate("2040-08-31T13:30:00Z"),
                testDate("2040-08-31T13:30:00Z"),
                testDate("2040-08-31T13:30:01Z"),
                testDate("2040-08-31T13:30:02Z"),
                testDate("2040-08-31T13:30:02Z")
            ]),
            triggerInspector: { request in
                NotificationTriggerInspection(
                    repeats: false,
                    nextTriggerDate: request.identifier == crossed.identifier
                        ? testDate("2040-08-31T13:30:00Z")
                        : testDate("2040-09-01T13:30:00Z")
                )
            }
        )

        await worker.requestReconcile(.foreground)
        await worker.waitUntilIdle()

        #expect(planner.callCount == 2)
        #expect(await center.addedIdentifiers() == [latest.identifier])
    }

    @Test func crossedBoundaryWithProductionZeroDelayRunsExactlyOneFollowUp() async throws {
        let reminder = validReminder()
        let crossed = try oneShotRequest(
            reminderID: reminder.id,
            alertInstant: testDate("2040-08-31T13:30:00Z"),
            baseInstant: testDate("2040-08-31T13:30:00Z")
        )
        let latest = try oneShotRequest(
            reminderID: reminder.id,
            alertInstant: testDate("2040-09-01T13:30:00Z"),
            baseInstant: testDate("2040-09-01T13:30:00Z")
        )
        let planner = SequenceNotificationPlanner([
            plan(
                requests: [crossed],
                outcomes: crossed.contributingGroupIDs.reduce(into: [:]) {
                    $0[$1] = .scheduled
                }
            ),
            plan(
                requests: [latest],
                outcomes: latest.contributingGroupIDs.reduce(into: [:]) {
                    $0[$1] = .scheduled
                }
            )
        ])
        let center = BlockingSecondPendingNotificationCenter()
        let worker = NotificationReconcileWorker(
            snapshotLoader: FixedSchedulingSnapshotLoader(
                CompleteReminderSnapshot(reminders: [reminder], tags: [])
            ),
            preferenceStore: FixedDeviceNotificationPreferenceStore(enabled: true),
            authorizationProvider: FixedNotificationAuthorizationProvider(.allowed),
            notificationCenter: center,
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            stateStore: DeviceSchedulingStateStore(),
            planner: planner,
            materializer: RecordingNotificationMaterializer { logical, _ in
                notificationRequest(identifier: logical.identifier)
            },
            recurrenceEnvironmentProvider: { .foundation },
            localeProvider: { Locale(identifier: "en_US") },
            clock: NotificationReconcileClock(
                now: { testDate("2040-08-31T13:30:02Z") },
                sleep: { delay in
                    guard delay > 0 else { return }
                    try await Task.sleep(for: .seconds(3_600))
                }
            ),
            retryDelays: [],
            triggerInspector: { request in
                NotificationTriggerInspection(
                    repeats: false,
                    nextTriggerDate: request.identifier == crossed.identifier
                        ? testDate("2040-08-31T13:30:00Z")
                        : testDate("2040-09-01T13:30:00Z")
                )
            }
        )

        await worker.requestReconcile(.foreground)
        await center.waitUntilSecondPendingStarts()
        await drainScheduledTasks()
        await center.releaseSecondPending()
        await worker.waitUntilIdle()

        #expect(planner.callCount == 2)
        #expect(await center.addedIdentifiers() == [latest.identifier])
        await worker.enterBackground()
    }

    @Test func requestsDuringInflightPassCoalesceIntoOneLatestSnapshotFollowUp() async {
        let first = CompleteReminderSnapshot(
            reminders: [validReminder(title: "first")],
            tags: []
        )
        let latest = CompleteReminderSnapshot(
            reminders: [validReminder(title: "latest")],
            tags: []
        )
        let loader = BlockingSequenceSnapshotLoader(first: first, latest: latest)
        let planner = SnapshotRecordingPlanner()
        let center = NotificationCenterClientSpy()
        let worker = NotificationReconcileWorker(
            snapshotLoader: loader,
            preferenceStore: FixedDeviceNotificationPreferenceStore(enabled: true),
            authorizationProvider: FixedNotificationAuthorizationProvider(.allowed),
            notificationCenter: center,
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            stateStore: DeviceSchedulingStateStore(),
            planner: planner,
            materializer: RecordingNotificationMaterializer { logical, _ in
                notificationRequest(identifier: logical.identifier)
            },
            recurrenceEnvironmentProvider: { .foundation },
            localeProvider: { Locale(identifier: "en_US") },
            clock: NotificationReconcileClock(
                now: { testDate("2040-08-01T00:00:00Z") },
                sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }
            ),
            retryDelays: [],
            triggerInspector: { _ in nil }
        )

        await worker.requestReconcile(.foreground)
        await loader.waitUntilFirstLoadStarts()
        await worker.requestReconcile(.modelChanged)
        await worker.requestReconcile(.modelChanged)
        await loader.releaseFirstLoad()
        await worker.waitUntilIdle()

        #expect(await loader.loadCount == 2)
        #expect(planner.observedTitles == [["first"], ["latest"]])
        #expect(await center.recordedCalls() == ["pending", "pending"])
    }

    @Test func expiredLifecycleProjectionDoesNotSuppressMatchingMaterializedOneShot() async throws {
        let reminder = validReminder()
        let logical = try oneShotRequest(
            reminderID: reminder.id,
            alertInstant: testDate("2040-08-31T13:30:00Z"),
            baseInstant: testDate("2040-08-31T13:30:00Z")
        )
        let group = try #require(logical.contributingGroupIDs.first)
        let eligibility = ForegroundEligibilityIndexStore()
        let expiredPlan = LogicalPlan(
            requests: [logical],
            outcomes: [group: .scheduled],
            selectedGroupIDs: [group],
            scheduledThrough: [:],
            reminderStatuses: [reminder.id: ReminderStatus(primary: .expired, secondary: [])]
        )
        let worker = testWorker(
            snapshot: CompleteReminderSnapshot(reminders: [reminder], tags: []),
            center: NotificationCenterClientSpy(),
            planner: FixedNotificationPlanner(plan: expiredPlan),
            materializer: RecordingNotificationMaterializer { logical, _ in
                notificationRequest(identifier: logical.identifier)
            },
            eligibilityIndexStore: eligibility,
            clock: SequenceReconcileClock([
                testDate("2040-08-01T00:00:00Z"),
                testDate("2040-08-02T00:00:00Z")
            ]),
            triggerInspector: { _ in
                NotificationTriggerInspection(
                    repeats: false,
                    nextTriggerDate: testDate("2040-08-31T13:30:00Z")
                )
            }
        )

        await worker.requestReconcile(.foreground)
        await worker.waitUntilIdle()

        #expect(eligibility.isEligible(reminder.id))
    }

    @Test func observedModelChangeStalesPublishedIndexBeforeBlockedLoadCompletes() async {
        let snapshot = CompleteReminderSnapshot(reminders: [], tags: [])
        let loader = BlockingSequenceSnapshotLoader(first: snapshot, latest: snapshot)
        let eligibility = ForegroundEligibilityIndexStore()
        let stateStore = DeviceSchedulingStateStore()
        let reminderID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        eligibility.publish(eligibleReminderIDs: [reminderID])
        let worker = NotificationReconcileWorker(
            snapshotLoader: loader,
            preferenceStore: FixedDeviceNotificationPreferenceStore(enabled: true),
            authorizationProvider: FixedNotificationAuthorizationProvider(.allowed),
            notificationCenter: NotificationCenterClientSpy(),
            eligibilityIndexStore: eligibility,
            stateStore: stateStore
        )

        await worker.requestReconcile(.modelChanged)

        #expect(eligibility.snapshot().isStale)
        #expect(!eligibility.isEligible(reminderID))
        #expect(await stateStore.snapshot().reconcileInProgressOrQueued)
        await loader.waitUntilFirstLoadStarts()
        await loader.releaseFirstLoad()
        await worker.waitUntilIdle()
    }

    @Test func boundedBackoffStopsAfterConfiguredInMemoryAttempts() async {
        let loader = CountingFailingSnapshotLoader()
        let sleeper = ImmediateSleeper()
        let worker = NotificationReconcileWorker(
            snapshotLoader: loader,
            preferenceStore: FixedDeviceNotificationPreferenceStore(enabled: true),
            authorizationProvider: FixedNotificationAuthorizationProvider(.allowed),
            notificationCenter: NotificationCenterClientSpy(),
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            stateStore: DeviceSchedulingStateStore(),
            clock: NotificationReconcileClock(
                now: { testDate("2040-08-01T00:00:00Z") },
                sleep: { delay in await sleeper.sleep(delay) }
            ),
            retryDelays: [1, 2]
        )

        await worker.requestReconcile(.foreground)
        await waitUntil { await loader.count == 3 }
        await worker.waitUntilIdle()

        #expect(await sleeper.delays == [1, 2])
        #expect(await loader.count == 3)
        #expect(await worker.timerState() == NotificationReconcileTimerState(
            retryScheduled: false,
            foregroundReplenishmentScheduled: false,
            retryAttempt: 2
        ))
    }

    @Test func supersededRetryCallbackCannotReplaceTheCurrentTimer() async {
        let loader = CountingFailingSnapshotLoader()
        let sleeper = ManuallyResumedSleeper()
        let worker = NotificationReconcileWorker(
            snapshotLoader: loader,
            preferenceStore: FixedDeviceNotificationPreferenceStore(enabled: true),
            authorizationProvider: FixedNotificationAuthorizationProvider(.allowed),
            notificationCenter: NotificationCenterClientSpy(),
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            stateStore: DeviceSchedulingStateStore(),
            clock: NotificationReconcileClock(
                now: { testDate("2040-08-01T00:00:00Z") },
                sleep: { delay in try await sleeper.sleep(delay) }
            ),
            retryDelays: [1, 2, 4]
        )

        await worker.requestReconcile(.foreground)
        await worker.waitUntilIdle()
        await waitUntil { await sleeper.recordedDelays.count == 1 }
        await worker.requestReconcile(.foreground)
        await worker.waitUntilIdle()
        await waitUntil { await sleeper.recordedDelays.count == 2 }

        await sleeper.resume(id: 0)
        await waitUntil { await sleeper.hasReturned(id: 0) }
        await drainScheduledTasks()

        #expect(await loader.count == 2)
        #expect(await sleeper.recordedDelays == [1, 1])
        #expect(await worker.timerState() == NotificationReconcileTimerState(
            retryScheduled: true,
            foregroundReplenishmentScheduled: false,
            retryAttempt: 1
        ))
        await worker.enterBackground()
        await sleeper.resumeAll()
        await drainScheduledTasks()
    }

    @Test func supersededReplenishmentCallbackCannotReplaceTheCurrentTimer() async throws {
        let reminder = validReminder()
        let logical = try oneShotRequest(
            reminderID: reminder.id,
            alertInstant: testDate("2040-08-31T13:30:00Z"),
            baseInstant: testDate("2040-08-31T13:30:00Z")
        )
        let planner = SequenceNotificationPlanner([plan(
            requests: [logical],
            outcomes: logical.contributingGroupIDs.reduce(into: [:]) {
                $0[$1] = .scheduled
            }
        )])
        let center = NotificationCenterClientSpy()
        let sleeper = ManuallyResumedSleeper()
        let worker = NotificationReconcileWorker(
            snapshotLoader: FixedSchedulingSnapshotLoader(
                CompleteReminderSnapshot(reminders: [reminder], tags: [])
            ),
            preferenceStore: FixedDeviceNotificationPreferenceStore(enabled: true),
            authorizationProvider: FixedNotificationAuthorizationProvider(.allowed),
            notificationCenter: center,
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            stateStore: DeviceSchedulingStateStore(),
            planner: planner,
            materializer: RecordingNotificationMaterializer { logical, _ in
                notificationRequest(identifier: logical.identifier)
            },
            recurrenceEnvironmentProvider: { .foundation },
            localeProvider: { Locale(identifier: "en_US") },
            clock: NotificationReconcileClock(
                now: { testDate("2040-08-01T00:00:00Z") },
                sleep: { delay in try await sleeper.sleep(delay) }
            ),
            retryDelays: [],
            triggerInspector: { _ in NotificationTriggerInspection(
                repeats: false,
                nextTriggerDate: testDate("2040-08-31T13:30:00Z")
            ) }
        )

        await worker.requestReconcile(.foreground)
        await worker.waitUntilIdle()
        await waitUntil { await sleeper.recordedDelays.count == 1 }
        await worker.requestReconcile(.foreground)
        await worker.waitUntilIdle()
        await waitUntil { await sleeper.recordedDelays.count == 2 }

        await sleeper.resume(id: 0)
        await waitUntil { await sleeper.hasReturned(id: 0) }
        await drainScheduledTasks()

        #expect(planner.callCount == 2)
        #expect(await center.addedIdentifiers() == [logical.identifier, logical.identifier])
        #expect(await sleeper.recordedDelays.count == 2)
        #expect(await worker.timerState().foregroundReplenishmentScheduled)
        await worker.enterBackground()
        await sleeper.resumeAll()
        await drainScheduledTasks()
    }

    @Test func backgroundPreventsResumedCancelledRetryFromReconciling() async {
        let loader = CountingFailingSnapshotLoader()
        let sleeper = ManuallyResumedSleeper()
        let worker = NotificationReconcileWorker(
            snapshotLoader: loader,
            preferenceStore: FixedDeviceNotificationPreferenceStore(enabled: true),
            authorizationProvider: FixedNotificationAuthorizationProvider(.allowed),
            notificationCenter: NotificationCenterClientSpy(),
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            stateStore: DeviceSchedulingStateStore(),
            clock: NotificationReconcileClock(
                now: { testDate("2040-08-01T00:00:00Z") },
                sleep: { delay in try await sleeper.sleep(delay) }
            ),
            retryDelays: [1]
        )

        await worker.requestReconcile(.foreground)
        await worker.waitUntilIdle()
        await waitUntil { await sleeper.recordedDelays.count == 1 }
        await worker.enterBackground()
        await sleeper.resume(id: 0)
        await waitUntil { await sleeper.hasReturned(id: 0) }
        await drainScheduledTasks()

        #expect(await loader.count == 1)
        #expect(!(await worker.timerState()).retryScheduled)
    }

    @Test func backgroundPreventsResumedCancelledReplenishmentFromReconciling() async throws {
        let reminder = validReminder()
        let logical = try oneShotRequest(
            reminderID: reminder.id,
            alertInstant: testDate("2040-08-31T13:30:00Z"),
            baseInstant: testDate("2040-08-31T13:30:00Z")
        )
        let planner = SequenceNotificationPlanner([plan(
            requests: [logical],
            outcomes: logical.contributingGroupIDs.reduce(into: [:]) {
                $0[$1] = .scheduled
            }
        )])
        let center = NotificationCenterClientSpy()
        let sleeper = ManuallyResumedSleeper()
        let worker = NotificationReconcileWorker(
            snapshotLoader: FixedSchedulingSnapshotLoader(
                CompleteReminderSnapshot(reminders: [reminder], tags: [])
            ),
            preferenceStore: FixedDeviceNotificationPreferenceStore(enabled: true),
            authorizationProvider: FixedNotificationAuthorizationProvider(.allowed),
            notificationCenter: center,
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            stateStore: DeviceSchedulingStateStore(),
            planner: planner,
            materializer: RecordingNotificationMaterializer { logical, _ in
                notificationRequest(identifier: logical.identifier)
            },
            recurrenceEnvironmentProvider: { .foundation },
            localeProvider: { Locale(identifier: "en_US") },
            clock: NotificationReconcileClock(
                now: { testDate("2040-08-01T00:00:00Z") },
                sleep: { delay in try await sleeper.sleep(delay) }
            ),
            retryDelays: [],
            triggerInspector: { _ in NotificationTriggerInspection(
                repeats: false,
                nextTriggerDate: testDate("2040-08-31T13:30:00Z")
            ) }
        )

        await worker.requestReconcile(.foreground)
        await worker.waitUntilIdle()
        await waitUntil { await sleeper.recordedDelays.count == 1 }
        await worker.enterBackground()
        await sleeper.resume(id: 0)
        await waitUntil { await sleeper.hasReturned(id: 0) }
        await drainScheduledTasks()

        #expect(planner.callCount == 1)
        #expect(await center.addedIdentifiers() == [logical.identifier])
        #expect(!(await worker.timerState()).foregroundReplenishmentScheduled)
    }

    @Test func backgroundTransitionCancelsRetryAndForegroundReplenishmentTimers() async throws {
        let suspendedSleeper = SuspendedSleeper()
        let failingWorker = NotificationReconcileWorker(
            snapshotLoader: CountingFailingSnapshotLoader(),
            preferenceStore: FixedDeviceNotificationPreferenceStore(enabled: true),
            authorizationProvider: FixedNotificationAuthorizationProvider(.allowed),
            notificationCenter: NotificationCenterClientSpy(),
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            stateStore: DeviceSchedulingStateStore(),
            clock: NotificationReconcileClock(
                now: { testDate("2040-08-01T00:00:00Z") },
                sleep: { delay in try await suspendedSleeper.sleep(delay) }
            ),
            retryDelays: [1]
        )
        await failingWorker.requestReconcile(.foreground)
        await failingWorker.waitUntilIdle()
        #expect(await failingWorker.timerState().retryScheduled)
        await failingWorker.enterBackground()
        let cancelledRetryState = await failingWorker.timerState()
        #expect(!cancelledRetryState.retryScheduled)
        await waitUntil { await suspendedSleeper.cancellationCount == 1 }

        let reminder = validReminder()
        let logical = try oneShotRequest(
            reminderID: reminder.id,
            alertInstant: testDate("2040-08-31T13:30:00Z"),
            baseInstant: testDate("2040-08-31T13:30:00Z")
        )
        let foregroundSleeper = SuspendedSleeper()
        let successfulWorker = testWorker(
            snapshot: CompleteReminderSnapshot(reminders: [reminder], tags: []),
            center: NotificationCenterClientSpy(),
            planner: FixedNotificationPlanner(plan: plan(
                requests: [logical],
                outcomes: logical.contributingGroupIDs.reduce(into: [:]) {
                    $0[$1] = .scheduled
                }
            )),
            materializer: RecordingNotificationMaterializer { logical, _ in
                notificationRequest(identifier: logical.identifier)
            },
            clock: SequenceReconcileClock(
                [
                    testDate("2040-08-01T00:00:00Z"),
                    testDate("2040-08-02T00:00:00Z")
                ],
                sleep: { delay in try await foregroundSleeper.sleep(delay) }
            ),
            triggerInspector: { _ in
                NotificationTriggerInspection(
                    repeats: false,
                    nextTriggerDate: testDate("2040-08-31T13:30:00Z")
                )
            }
        )
        await successfulWorker.requestReconcile(.foreground)
        await successfulWorker.waitUntilIdle()
        #expect(await successfulWorker.timerState().foregroundReplenishmentScheduled)
        await waitUntil { await foregroundSleeper.delays.count == 1 }
        #expect(await foregroundSleeper.delays == [
            testDate("2040-08-31T13:30:01Z").timeIntervalSince(
                testDate("2040-08-02T00:00:00Z")
            )
        ])
        await successfulWorker.enterBackground()
        let cancelledForegroundState = await successfulWorker.timerState()
        #expect(!cancelledForegroundState.foregroundReplenishmentScheduled)
        await waitUntil { await foregroundSleeper.cancellationCount == 1 }
    }

    @Test func explicitDeleteMatchesCurrentIdentifierOrStableRoutingKey() async throws {
        let reminderID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let current = try NotificationIdentifierCodec().oneShotIdentifier(
            reminderID: reminderID,
            alertInstant: Date(timeIntervalSince1970: 2_229_984_000)
        )
        let future = "notification-manager.local.v9.future-shape"
        let unknownWithoutRouting = "notification-manager.local.v10.unknown"
        let center = NotificationCenterClientSpy(
            pending: [
                NotificationInventoryItem(identifier: current),
                NotificationInventoryItem(
                    identifier: future,
                    reminderRoutingValue: reminderID.uuidString.lowercased()
                )
            ],
            delivered: [
                NotificationInventoryItem(
                    identifier: future,
                    reminderRoutingValue: reminderID.uuidString.lowercased()
                ),
                NotificationInventoryItem(identifier: unknownWithoutRouting)
            ]
        )
        let cleanup = NotificationCleanupService(notificationCenter: center)

        await cleanup.removeNotifications(for: reminderID)

        #expect(await center.pendingIdentifiers().isEmpty)
        #expect(await center.deliveredIdentifiers() == [unknownWithoutRouting])
    }

    @Test func removeAllPendingUsesRootPrefixAndNeverReadsDelivered() async {
        let appOwned = "notification-manager.local.malformed"
        let unrelated = "other-app.notification"
        let center = NotificationCenterClientSpy(
            pending: [
                NotificationInventoryItem(identifier: appOwned),
                NotificationInventoryItem(identifier: unrelated)
            ],
            delivered: [NotificationInventoryItem(identifier: appOwned)]
        )
        let cleanup = NotificationCleanupService(notificationCenter: center)

        await cleanup.removeAllPendingAppNotifications()

        #expect(await center.recordedCalls() == [
            "pending",
            "remove-pending:\(appOwned)"
        ])
        #expect(await center.pendingIdentifiers() == [unrelated])
    }
}

private struct FailingSchedulingSnapshotLoader: CompleteSchedulingSnapshotLoading {
    let error: CompleteSchedulingSnapshotLoadError

    func loadCompleteSnapshot() async throws -> CompleteReminderSnapshot {
        throw error
    }
}

private struct FixedSchedulingSnapshotLoader: CompleteSchedulingSnapshotLoading {
    let snapshot: CompleteReminderSnapshot

    init(_ snapshot: CompleteReminderSnapshot) {
        self.snapshot = snapshot
    }

    func loadCompleteSnapshot() async throws -> CompleteReminderSnapshot { snapshot }
}

private actor FixedDeviceNotificationPreferenceStore: DeviceNotificationPreferenceStore {
    private var enabled: Bool

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func isEnabled() async -> Bool { enabled }
    func setEnabled(_ enabled: Bool) async { self.enabled = enabled }
}

private actor CountingPreferenceStore: DeviceNotificationPreferenceStore {
    private var enabled: Bool
    private(set) var readCount = 0

    init(enabled: Bool) { self.enabled = enabled }

    func isEnabled() async -> Bool {
        readCount += 1
        return enabled
    }

    func setEnabled(_ enabled: Bool) async { self.enabled = enabled }
}

private struct FixedNotificationAuthorizationProvider: NotificationAuthorizationProviding {
    let snapshot: NotificationAuthorizationSnapshot

    init(_ state: DeviceAuthorizationSchedulingState) {
        snapshot = NotificationAuthorizationSnapshot(state: state, diagnostic: nil)
    }

    func currentAuthorization() async -> NotificationAuthorizationSnapshot { snapshot }
}

private actor CountingAuthorizationProvider: NotificationAuthorizationProviding {
    private let snapshot: NotificationAuthorizationSnapshot
    private(set) var readCount = 0

    init(_ state: DeviceAuthorizationSchedulingState) {
        snapshot = NotificationAuthorizationSnapshot(state: state, diagnostic: nil)
    }

    func currentAuthorization() async -> NotificationAuthorizationSnapshot {
        readCount += 1
        return snapshot
    }
}

private actor NotificationCenterClientSpy: NotificationCenterClient {
    private var calls: [String] = []

    private var pending: [NotificationInventoryItem]
    private var delivered: [NotificationInventoryItem]
    private let addFailures: Set<String>
    private let pendingFailure: Bool
    private var addedRequests: [UNNotificationRequest] = []
    private let onCall: @Sendable (String) -> Void

    init(
        pending: [NotificationInventoryItem] = [],
        delivered: [NotificationInventoryItem] = [],
        addFailures: Set<String> = [],
        pendingFailure: Bool = false,
        onCall: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.pending = pending
        self.delivered = delivered
        self.addFailures = addFailures
        self.pendingFailure = pendingFailure
        self.onCall = onCall
    }

    func pendingNotificationInventory() async throws -> [NotificationInventoryItem] {
        calls.append("pending")
        onCall("pending")
        if pendingFailure { throw TestFailure.inventory }
        return pending
    }

    func deliveredNotificationInventory() async -> [NotificationInventoryItem] {
        calls.append("delivered")
        onCall("delivered")
        return delivered
    }

    func add(_ request: UNNotificationRequest) async throws {
        calls.append("add:\(request.identifier)")
        onCall("add:\(request.identifier)")
        if addFailures.contains(request.identifier) {
            throw TestFailure.add
        }
        addedRequests.append(request)
        pending.removeAll { $0.identifier == request.identifier }
        pending.append(NotificationInventoryItem(
            identifier: request.identifier,
            reminderRoutingValue: request.content.userInfo["notification-manager.reminder-id"]
                as? String
        ))
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        calls.append("remove-pending:\(identifiers.sorted().joined(separator: ","))")
        onCall("remove-pending")
        let removed = Set(identifiers)
        pending.removeAll { removed.contains($0.identifier) }
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {
        calls.append("remove-delivered:\(identifiers.sorted().joined(separator: ","))")
        onCall("remove-delivered")
        let removed = Set(identifiers)
        delivered.removeAll { removed.contains($0.identifier) }
    }

    func recordedCalls() -> [String] { calls }
    func pendingIdentifiers() -> Set<String> { Set(pending.map(\.identifier)) }
    func deliveredIdentifiers() -> Set<String> { Set(delivered.map(\.identifier)) }
    func addedIdentifiers() -> [String] { addedRequests.map(\.identifier) }
    func addedTitles() -> [String] { addedRequests.map(\.content.title) }
}

private actor BlockingSecondPendingNotificationCenter: NotificationCenterClient {
    private var pendingCallCount = 0
    private var secondPendingStarted = false
    private var secondPendingStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var secondPendingRelease: CheckedContinuation<Void, Never>?
    private var added: [String] = []

    func pendingNotificationInventory() async throws -> [NotificationInventoryItem] {
        pendingCallCount += 1
        guard pendingCallCount == 2 else { return [] }
        secondPendingStarted = true
        let waiters = secondPendingStartWaiters
        secondPendingStartWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            secondPendingRelease = continuation
        }
        return []
    }

    func deliveredNotificationInventory() async -> [NotificationInventoryItem] { [] }

    func add(_ request: UNNotificationRequest) async throws {
        added.append(request.identifier)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {}
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {}

    func waitUntilSecondPendingStarts() async {
        guard !secondPendingStarted else { return }
        await withCheckedContinuation { continuation in
            secondPendingStartWaiters.append(continuation)
        }
    }

    func releaseSecondPending() {
        secondPendingRelease?.resume()
        secondPendingRelease = nil
    }

    func addedIdentifiers() -> [String] { added }
}

private struct FixedNotificationPlanner: NotificationPlanning {
    let plan: LogicalPlan
    func makePlan(_ input: PlannerInput) throws -> LogicalPlan { plan }
}

private struct ThrowingNotificationPlanner: NotificationPlanning {
    func makePlan(_ input: PlannerInput) throws -> LogicalPlan {
        throw TestFailure.planning
    }
}

private final class PassRecordingPlanner: NotificationPlanning, @unchecked Sendable {
    private let lock = NSLock()
    private let result: LogicalPlan
    private let eventLog: OrderedEventLog
    private var recordedEvaluationNow: Date?
    private var recordedEnvironmentIdentity: ObjectIdentifier?

    init(plan: LogicalPlan, eventLog: OrderedEventLog) {
        result = plan
        self.eventLog = eventLog
    }

    var evaluationNow: Date? { lock.withLock { recordedEvaluationNow } }
    var environmentIdentity: ObjectIdentifier? {
        lock.withLock { recordedEnvironmentIdentity }
    }

    func makePlan(_ input: PlannerInput) throws -> LogicalPlan {
        eventLog.append("plan")
        lock.withLock {
            recordedEvaluationNow = input.evaluationNow
            recordedEnvironmentIdentity = ObjectIdentifier(
                input.recurrenceEnvironment as AnyObject
            )
        }
        return result
    }
}

private final class SequenceNotificationPlanner: NotificationPlanning, @unchecked Sendable {
    private let lock = NSLock()
    private var plans: [LogicalPlan]
    private var calls = 0

    init(_ plans: [LogicalPlan]) {
        precondition(!plans.isEmpty)
        self.plans = plans
    }

    var callCount: Int { lock.withLock { calls } }

    func makePlan(_ input: PlannerInput) throws -> LogicalPlan {
        lock.withLock {
            calls += 1
            if plans.count == 1 { return plans[0] }
            return plans.removeFirst()
        }
    }
}

private final class SnapshotRecordingPlanner: NotificationPlanning, @unchecked Sendable {
    private let lock = NSLock()
    private var titles: [[String]] = []

    var observedTitles: [[String]] { lock.withLock { titles } }

    func makePlan(_ input: PlannerInput) throws -> LogicalPlan {
        lock.withLock { titles.append(input.snapshot.reminders.map(\.title)) }
        return plan(requests: [], outcomes: [:])
    }
}

private final class RecordingNotificationMaterializer:
    NotificationRequestMaterializing,
    @unchecked Sendable
{
    private let body: @Sendable (
        LogicalNotificationRequest,
        MaterializationInput
    ) throws -> UNNotificationRequest

    init(
        _ body: @escaping @Sendable (
            LogicalNotificationRequest,
            MaterializationInput
        ) throws -> UNNotificationRequest
    ) {
        self.body = body
    }

    func makeRequest(
        _ logical: LogicalNotificationRequest,
        input: MaterializationInput
    ) throws -> UNNotificationRequest {
        try body(logical, input)
    }
}

private final class PassRecordingMaterializer:
    NotificationRequestMaterializing,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let eventLog: OrderedEventLog
    private var dates: [Date] = []
    private var environments: [ObjectIdentifier] = []
    private var locales: [String] = []

    init(eventLog: OrderedEventLog) { self.eventLog = eventLog }

    var evaluationNows: [Date] { lock.withLock { dates } }
    var environmentIdentities: [ObjectIdentifier] { lock.withLock { environments } }
    var localeIdentifiers: [String] { lock.withLock { locales } }

    func makeRequest(
        _ logical: LogicalNotificationRequest,
        input: MaterializationInput
    ) throws -> UNNotificationRequest {
        eventLog.append("materialize:\(logical.identifier)")
        lock.withLock {
            dates.append(input.evaluationNow)
            environments.append(ObjectIdentifier(input.recurrenceEnvironment as AnyObject))
            locales.append(input.locale.identifier)
        }
        return notificationRequest(identifier: logical.identifier)
    }
}

private enum TestFailure: Error {
    case materialization
    case add
    case planning
    case repository
    case inventory
}

struct DeviceGateFixture: Sendable {
    let enabled: Bool
    let authorization: DeviceAuthorizationSchedulingState
}

private final class OrderedEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) { lock.withLock { storage.append(value) } }
    var values: [String] { lock.withLock { storage } }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0
    func increment() { lock.withLock { storage += 1 } }
    var value: Int { lock.withLock { storage } }
}

private final class MarkerRecurrenceEnvironment: RecurrenceEnvironment, @unchecked Sendable {
    func timeZone(identifier: String) -> TimeZone? { TimeZone(identifier: identifier) }

    func gregorianCalendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

private actor SnapshotRepositoryStub: ReminderRepository {
    private let snapshot: CompleteReminderSnapshot

    init(snapshot: CompleteReminderSnapshot) { self.snapshot = snapshot }

    func fetchCompleteSnapshot() async throws -> CompleteReminderSnapshot { snapshot }
    func reminder(id: UUID) async throws -> ReminderSnapshot? {
        snapshot.reminders.first { $0.id == id }
    }
    func save(_ mutation: EncodedReminderMutation) async throws -> ReminderSnapshot {
        throw TestFailure.repository
    }
    func delete(id: UUID) async throws { throw TestFailure.repository }
    func saveTag(_ mutation: EncodedTagMutation) async throws -> TagSnapshot {
        throw TestFailure.repository
    }
    func deleteTag(id: UUID) async throws { throw TestFailure.repository }
}

private func testWorker(
    snapshot: CompleteReminderSnapshot,
    center: NotificationCenterClientSpy,
    planner: any NotificationPlanning,
    materializer: any NotificationRequestMaterializing,
    eligibilityIndexStore: ForegroundEligibilityIndexStore = ForegroundEligibilityIndexStore(),
    stateStore: DeviceSchedulingStateStore = DeviceSchedulingStateStore(),
    clock: SequenceReconcileClock,
    triggerInspector: @escaping @Sendable (UNNotificationRequest) -> NotificationTriggerInspection
) -> NotificationReconcileWorker {
    NotificationReconcileWorker(
        snapshotLoader: FixedSchedulingSnapshotLoader(snapshot),
        preferenceStore: FixedDeviceNotificationPreferenceStore(enabled: true),
        authorizationProvider: FixedNotificationAuthorizationProvider(.allowed),
        notificationCenter: center,
        eligibilityIndexStore: eligibilityIndexStore,
        stateStore: stateStore,
        planner: planner,
        materializer: materializer,
        recurrenceEnvironmentProvider: { .foundation },
        localeProvider: { Locale(identifier: "en_US") },
        clock: clock.value,
        retryDelays: [],
        triggerInspector: triggerInspector
    )
}

private final class SequenceReconcileClock: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Date]
    private let sleepBody: @Sendable (TimeInterval) async throws -> Void

    init(
        _ values: [Date],
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
            _ in try await Task.sleep(for: .seconds(3_600))
        }
    ) {
        precondition(!values.isEmpty)
        self.values = values
        sleepBody = sleep
    }

    var value: NotificationReconcileClock {
        NotificationReconcileClock(
            now: { [self] in
                lock.withLock {
                    if values.count == 1 { return values[0] }
                    return values.removeFirst()
                }
            },
            sleep: sleepBody
        )
    }
}

private actor BlockingSequenceSnapshotLoader: CompleteSchedulingSnapshotLoading {
    private let first: CompleteReminderSnapshot
    private let latest: CompleteReminderSnapshot
    private var firstRelease: CheckedContinuation<Void, Never>?
    private var firstStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstStarted = false
    private(set) var loadCount = 0

    init(first: CompleteReminderSnapshot, latest: CompleteReminderSnapshot) {
        self.first = first
        self.latest = latest
    }

    func loadCompleteSnapshot() async throws -> CompleteReminderSnapshot {
        loadCount += 1
        guard loadCount == 1 else { return latest }
        firstStarted = true
        let waiters = firstStartWaiters
        firstStartWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            firstRelease = continuation
        }
        return first
    }

    func waitUntilFirstLoadStarts() async {
        guard !firstStarted else { return }
        await withCheckedContinuation { continuation in
            firstStartWaiters.append(continuation)
        }
    }

    func releaseFirstLoad() {
        firstRelease?.resume()
        firstRelease = nil
    }
}

private actor CountingFailingSnapshotLoader: CompleteSchedulingSnapshotLoading {
    private(set) var count = 0

    func loadCompleteSnapshot() async throws -> CompleteReminderSnapshot {
        count += 1
        throw CompleteSchedulingSnapshotLoadError.fetch
    }
}

private actor ImmediateSleeper {
    private(set) var delays: [TimeInterval] = []
    func sleep(_ delay: TimeInterval) { delays.append(delay) }
}

private actor SuspendedSleeper {
    private(set) var cancellationCount = 0
    private(set) var delays: [TimeInterval] = []

    func sleep(_ delay: TimeInterval) async throws {
        delays.append(delay)
        do {
            try await Task.sleep(for: .seconds(3_600))
        } catch {
            cancellationCount += 1
            throw error
        }
    }
}

private actor ManuallyResumedSleeper {
    private var delays: [TimeInterval] = []
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var returnedIDs: Set<Int> = []

    var recordedDelays: [TimeInterval] { delays }

    func sleep(_ delay: TimeInterval) async throws {
        let id = delays.count
        delays.append(delay)
        await withCheckedContinuation { continuation in
            continuations[id] = continuation
        }
        returnedIDs.insert(id)
    }

    func resume(id: Int) {
        continuations.removeValue(forKey: id)?.resume()
    }

    func resumeAll() {
        let pending = continuations.values
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }

    func hasReturned(id: Int) -> Bool { returnedIDs.contains(id) }
}

private func plan(
    requests: [LogicalNotificationRequest],
    outcomes: [AlertGroupID: AlertGroupSchedulingOutcome]
) -> LogicalPlan {
    LogicalPlan(
        requests: requests,
        outcomes: outcomes,
        selectedGroupIDs: Array(outcomes.keys),
        scheduledThrough: [:],
        reminderStatuses: [:]
    )
}

private func oneShotRequest(
    reminderID: UUID,
    alertInstant: Date,
    baseInstant: Date,
    contributors: Set<AlertGroupID>? = nil
) throws -> LogicalNotificationRequest {
    var source = DateComponents()
    source.calendar = Calendar(identifier: .gregorian)
    source.timeZone = TimeZone(identifier: "America/New_York")!
    source.year = 2040
    source.month = 8
    source.day = 31
    source.hour = 9
    source.minute = 30
    source.second = 0
    let reason = EffectiveAlert(
        kind: .main,
        baseOccurrence: BaseOccurrence(instant: baseInstant, sourceComponents: source),
        alertInstant: alertInstant
    )
    return LogicalNotificationRequest(
        identifier: try NotificationIdentifierCodec().oneShotIdentifier(
            reminderID: reminderID,
            alertInstant: alertInstant
        ),
        reminderID: reminderID,
        payload: .oneShot(alertInstant: alertInstant, reasons: [reason]),
        contributingGroupIDs: contributors ?? [AlertGroupID(
            reminderID: reminderID,
            baseOccurrenceInstant: baseInstant
        )]
    )
}

private func repeatingRequest(
    reminderID: UUID,
    baseInstant: Date
) -> LogicalNotificationRequest {
    let components = RepeatingTriggerComponents(
        timeZoneIdentifier: "America/New_York",
        hour: 9,
        minute: 30,
        second: 0
    )
    let identifier = try! NotificationIdentifierCodec().repeatingIdentifier(
        reminderID: reminderID,
        components: components
    )
    return LogicalNotificationRequest(
        identifier: identifier,
        reminderID: reminderID,
        payload: .repeating(
            components: components,
            contributors: [RepeatingTriggerContributor(
                kind: .main,
                sourceComponents: components
            )]
        ),
        contributingGroupIDs: [AlertGroupID(
            reminderID: reminderID,
            baseOccurrenceInstant: baseInstant
        )]
    )
}

private func validReminder(
    id: String = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
    title: String = "Trip",
    schedule: ScheduleReadState? = nil,
    tagIDs: Set<UUID> = []
) -> ReminderSnapshot {
    let date = testDate("2040-08-01T00:00:00Z")
    return ReminderSnapshot(
        id: UUID(uuidString: id)!,
        title: title,
        notes: nil,
        urlString: nil,
        enabled: true,
        schedule: schedule ?? .valid(
            ScheduleDefinition(
                source: SourceWallClock(
                    year: 2040,
                    month: 8,
                    day: 31,
                    hour: 9,
                    minute: 30,
                    timeZoneIdentifier: "America/New_York"
                ),
                rule: .daily(interval: 1),
                end: .never,
                early: nil
            ),
            sourceVersion: 1,
            originalData: Data([1])
        ),
        tagIDs: tagIDs,
        createdAt: date,
        updatedAt: date
    )
}

private func notificationRequest(
    identifier: String,
    title: String = "content"
) -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = title
    return UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
}

private func testDate(_ value: String) -> Date {
    guard let result = ISO8601DateFormatter().date(from: value) else {
        preconditionFailure("Invalid test date")
    }
    return result
}

private func waitUntil(
    _ condition: @escaping @Sendable () async -> Bool
) async {
    for _ in 0..<1_000 {
        if await condition() { return }
        await Task.yield()
    }
    Issue.record("Condition did not become true")
}

private func drainScheduledTasks() async {
    for _ in 0..<1_000 {
        await Task.yield()
    }
}
