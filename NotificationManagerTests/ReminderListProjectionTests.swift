import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import Testing
@testable import NotificationManager

struct ReminderListProjectionTests {
    @Test func activeCapacityFailureRemainsUpcoming() {
        let item = ReminderListItemPresentation(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            title: "Visa renewal",
            reminderStatus: ReminderStatus(primary: .active, secondary: []),
            deviceSchedulingStatus: .unscheduledCapacity,
            nextPresentation: .rolling(PhysicalNotificationPresentation.fixture(
                alertInstant: date("2040-08-31T13:30:00Z")
            )),
            updatedAt: date("2040-08-01T00:00:00Z")
        )

        let sections = ReminderListProjection.make(from: [item], selectedTagID: nil)

        #expect(sections.upcoming.map(\.id) == [item.id])
        #expect(sections.needsAttention.isEmpty)
        #expect(sections.inactive.isEmpty)
    }

    @Test func secondaryStatusesRemainAttachedWithoutChangingPrimarySection() {
        let disabledExpired = ReminderListItemPresentation(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            title: "Disabled and expired",
            reminderStatus: ReminderStatus(primary: .disabled, secondary: [.expired]),
            deviceSchedulingStatus: .notApplicable,
            nextPresentation: nil,
            updatedAt: date("2040-08-01T00:00:00Z")
        )
        let updateDisabled = ReminderListItemPresentation(
            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
            title: "Update and disabled",
            reminderStatus: ReminderStatus(primary: .updateRequired, secondary: [.disabled]),
            deviceSchedulingStatus: .notApplicable,
            nextPresentation: nil,
            updatedAt: date("2040-08-02T00:00:00Z")
        )

        let sections = ReminderListProjection.make(
            from: [disabledExpired, updateDisabled],
            selectedTagID: nil
        )

        #expect(sections.inactive.map(\.id) == [disabledExpired.id])
        #expect(sections.needsAttention.map(\.id) == [updateDisabled.id])
        #expect(disabledExpired.reminderStatus.secondary == [.expired])
        #expect(updateDisabled.reminderStatus.secondary == [.disabled])
    }

    @Test func notificationProjectionPreservesEveryReasonOccurrencePairAndRole() {
        let alertInstant = date("2040-08-31T13:30:00Z")
        let mainOccurrence = BaseOccurrence(
            instant: alertInstant,
            sourceComponents: DateComponents(year: 2040, month: 8, day: 31)
        )
        let earlyOccurrence = BaseOccurrence(
            instant: date("2040-09-01T13:30:00Z"),
            sourceComponents: DateComponents(year: 2040, month: 9, day: 1)
        )
        let notification = PhysicalNotification(
            reminderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            alertInstant: alertInstant,
            reasons: [
                EffectiveAlert(
                    kind: .early,
                    baseOccurrence: earlyOccurrence,
                    alertInstant: alertInstant
                ),
                EffectiveAlert(
                    kind: .main,
                    baseOccurrence: mainOccurrence,
                    alertInstant: alertInstant
                )
            ]
        )

        let presentation = PhysicalNotificationPresentation(
            notification: notification,
            sourceTimeZoneIdentifier: "America/New_York",
            deviceLocalTime: alertInstant
        )

        #expect(presentation.reasons == [
            PhysicalNotificationReasonPresentation(
                role: .primary,
                kind: .main,
                baseOccurrenceInstant: mainOccurrence.instant
            ),
            PhysicalNotificationReasonPresentation(
                role: .secondary,
                kind: .early,
                baseOccurrenceInstant: earlyOccurrence.instant
            )
        ])
    }

    @Test func sectionOrderingAndSingleTagFilterAreDeterministic() {
        let work = ReminderTagPresentation(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000000")!,
            name: "Work",
            normalizedName: "work"
        )
        let earlier = ReminderListItemPresentation.fixture(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            lifecycleStatus: .active,
            nextAlertInstant: date("2040-08-31T13:30:00Z"),
            tags: [work]
        )
        let later = ReminderListItemPresentation.fixture(
            id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            lifecycleStatus: .active,
            nextAlertInstant: date("2040-09-01T13:30:00Z")
        )
        let invalidOld = ReminderListItemPresentation.fixture(
            id: "cccccccc-cccc-cccc-cccc-cccccccccccc",
            lifecycleStatus: .invalidSchedule,
            updatedAt: date("2040-07-01T00:00:00Z"),
            tags: [work]
        )
        let updateNew = ReminderListItemPresentation.fixture(
            id: "dddddddd-dddd-dddd-dddd-dddddddddddd",
            lifecycleStatus: .updateRequired,
            updatedAt: date("2040-08-01T00:00:00Z"),
            tags: [work]
        )
        let disabled = ReminderListItemPresentation.fixture(
            id: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
            lifecycleStatus: .disabled,
            updatedAt: date("2040-06-01T00:00:00Z"),
            tags: [work]
        )

        let sections = ReminderListProjection.make(
            from: [later, invalidOld, earlier, disabled, updateNew],
            selectedTagID: work.id
        )

        #expect(sections.upcoming.map(\.id) == [earlier.id])
        #expect(sections.needsAttention.map(\.id) == [updateNew.id, invalidOld.id])
        #expect(sections.inactive.map(\.id) == [disabled.id])
    }

    @Test func directOrderingUsesAuthoritativeOSFireRatherThanFoundationPreview() {
        let direct = ReminderListItemPresentation(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            title: "Direct",
            reminderStatus: ReminderStatus(primary: .active, secondary: []),
            deviceSchedulingStatus: .scheduled,
            nextPresentation: .directOSFire(
                authoritative: date("2040-08-31T10:00:00Z"),
                foundationPreview: date("2040-08-31T09:00:00Z")
            ),
            updatedAt: .distantPast
        )
        let rolling = ReminderListItemPresentation.fixture(
            id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            lifecycleStatus: .active,
            nextAlertInstant: date("2040-08-31T09:30:00Z")
        )

        let sections = ReminderListProjection.make(
            from: [direct, rolling],
            selectedTagID: nil
        )

        #expect(sections.upcoming.map(\.id) == [rolling.id, direct.id])
        guard case let .directOSFire(authoritative, foundationPreview) = direct.nextPresentation else {
            Issue.record("Expected direct OS fire presentation")
            return
        }
        #expect(authoritative == date("2040-08-31T10:00:00Z"))
        #expect(foundationPreview == date("2040-08-31T09:00:00Z"))
    }

    @MainActor
    @Test func listModelSortsTagChoicesByNormalizedNameNameAndID() {
        let upperA = ReminderTagPresentation(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000000")!,
            name: "Álpha",
            normalizedName: "alpha"
        )
        let lowerA = ReminderTagPresentation(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000000")!,
            name: "Alpha",
            normalizedName: "alpha"
        )
        let beta = ReminderTagPresentation(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000000")!,
            name: "Beta",
            normalizedName: "beta"
        )
        let tagged = ReminderListItemPresentation.fixture(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            lifecycleStatus: .active,
            nextAlertInstant: date("2040-08-31T13:30:00Z"),
            tags: [beta]
        )
        let actions = ReminderActionCoordinator(handlers: ReminderActionHandlers(
            setEnabled: { command in .saved(command.reminderID) },
            delete: { _ in }
        ))
        let model = ReminderListModel(
            snapshot: ReminderListSnapshot(
                generation: 1,
                items: [tagged],
                availableTags: [beta, upperA, lowerA]
            ),
            actions: actions
        )

        #expect(model.tagFilterChoices.map(\.id) == [lowerA.id, upperA.id, beta.id])
        model.selectedTagID = beta.id
        #expect(model.sections.upcoming.map(\.id) == [tagged.id])
        model.selectedTagID = lowerA.id
        #expect(model.sections.upcoming.isEmpty)
    }

    @Test func detailHidesNotApplicableDeviceRowWithoutDroppingGroupDiagnostics() {
        let item = ReminderListItemPresentation.fixture(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            lifecycleStatus: .invalidSchedule,
            updatedAt: date("2040-08-01T00:00:00Z")
        )
        let group = AlertGroupSchedulingPresentation(
            groupID: AlertGroupID(
                reminderID: item.id,
                baseOccurrenceInstant: date("2040-08-31T13:30:00Z")
            ),
            outcome: .unscheduledError
        )
        let detail = ReminderDetailModel(
            item: item,
            sourceTime: nil,
            currentDeviceTime: nil,
            localizedRepeatSummary: nil,
            nextNotifications: [],
            alertGroups: [group],
            scheduledThrough: nil,
            requestDiagnostics: [.init(identifier: "request", kind: .oneShot)]
        )

        #expect(detail.deviceSchedulingStatusForDisplay == nil)
        #expect(detail.alertGroups == [group])
        #expect(detail.requestDiagnostics.map(\.kind) == [.oneShot])
    }

    @Test func activeDetailKeepsDeviceStatusSeparateFromLifecycle() {
        let item = ReminderListItemPresentation(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            title: "Capacity constrained",
            reminderStatus: ReminderStatus(primary: .active, secondary: []),
            deviceSchedulingStatus: .unscheduledCapacity,
            nextPresentation: nil,
            updatedAt: date("2040-08-01T00:00:00Z")
        )
        let detail = ReminderDetailModel(
            item: item,
            sourceTime: date("2040-08-31T13:30:00Z"),
            currentDeviceTime: date("2040-08-31T21:30:00Z"),
            localizedRepeatSummary: "Every weekday.",
            nextNotifications: [],
            alertGroups: [],
            scheduledThrough: nil,
            requestDiagnostics: []
        )

        #expect(detail.lifecycleStatus == .active)
        #expect(detail.deviceSchedulingStatusForDisplay == .unscheduledCapacity)
    }

    @MainActor
    @Test func managementActionsDriveEnabledAndRequireDeleteConfirmation() async {
        let recorder = ReminderManagementActionRecorder()
        let coordinator = ReminderActionCoordinator(handlers: ReminderActionHandlers(
            setEnabled: { command in
                await recorder.recordEnabled(command)
                return .saved(command.reminderID)
            },
            delete: { id in await recorder.recordDelete(id) }
        ))
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!

        await coordinator.setEnabled(false, for: id, fallback: true)

        #expect(!coordinator.enabledValue(for: id, fallback: true))
        #expect(await recorder.enabledCalls() == [SetReminderEnabledCommand(
            reminderID: id,
            enabled: false,
            capacityConsent: .notProvided
        )])

        coordinator.requestDelete(id)

        #expect(coordinator.pendingDeleteID == id)
        #expect(await recorder.deletedIDs().isEmpty)

        await coordinator.confirmDelete(id)

        #expect(await recorder.deletedIDs() == [id])
        #expect(coordinator.state == .deleted(id))
    }

    @MainActor
    @Test func failedEnabledActionRestoresPresentedValue() async {
        let coordinator = ReminderActionCoordinator(handlers: ReminderActionHandlers(
            setEnabled: { _ in throw ReminderManagementActionProbeError.failed },
            delete: { _ in }
        ))
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!

        await coordinator.setEnabled(false, for: id, fallback: true)

        #expect(coordinator.enabledValue(for: id, fallback: true))
        #expect(coordinator.state == .failed(id, .enabledChange))
    }

    @MainActor
    @Test func newerEqualValuedPublicationClearsCompletedOptimisticOverride() async {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let authoritativeDisabled = ReminderListItemPresentation.fixture(
            id: id.uuidString,
            lifecycleStatus: .disabled,
            enabled: false
        )
        let coordinator = ReminderActionCoordinator(handlers: ReminderActionHandlers(
            setEnabled: { command in .saved(command.reminderID) },
            delete: { _ in }
        ))
        let model = ReminderListModel(
            snapshot: ReminderListSnapshot(
                generation: 1,
                items: [authoritativeDisabled],
                availableTags: []
            ),
            actions: coordinator
        )

        await coordinator.setEnabled(true, for: id, fallback: model.items[0].enabled)
        #expect(coordinator.enabledValue(for: id, fallback: false))

        model.publish(ReminderListSnapshot(
            generation: 2,
            items: [authoritativeDisabled],
            availableTags: []
        ))

        #expect(!coordinator.enabledValue(for: id, fallback: true))
        #expect(model.snapshot.generation == 2)
        #expect(coordinator.state == .idle)
    }

    @MainActor
    @Test func newerIntendedValuePublicationKeepsAuthoritativeEnabledPresentation() async {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let disabled = ReminderListItemPresentation.fixture(
            id: id.uuidString,
            lifecycleStatus: .disabled,
            enabled: false
        )
        let authoritativeEnabled = ReminderListItemPresentation.fixture(
            id: id.uuidString,
            lifecycleStatus: .active,
            enabled: true
        )
        let coordinator = ReminderActionCoordinator(handlers: ReminderActionHandlers(
            setEnabled: { command in .saved(command.reminderID) },
            delete: { _ in }
        ))
        let model = ReminderListModel(
            snapshot: ReminderListSnapshot(
                generation: 1,
                items: [disabled],
                availableTags: []
            ),
            actions: coordinator
        )

        await coordinator.setEnabled(true, for: id, fallback: model.items[0].enabled)
        model.publish(ReminderListSnapshot(
            generation: 2,
            items: [authoritativeEnabled],
            availableTags: []
        ))

        #expect(model.snapshot.generation == 2)
        #expect(coordinator.enabledValue(for: id, fallback: false))
    }

    @MainActor
    @Test func staleSnapshotGenerationIsIgnoredByProductionIngestion() {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let disabled = ReminderListItemPresentation.fixture(
            id: id.uuidString,
            lifecycleStatus: .disabled,
            enabled: false
        )
        let enabled = ReminderListItemPresentation.fixture(
            id: id.uuidString,
            lifecycleStatus: .active,
            enabled: true
        )
        let coordinator = ReminderActionCoordinator(handlers: ReminderActionHandlers(
            setEnabled: { command in .saved(command.reminderID) },
            delete: { _ in }
        ))
        let model = ReminderListModel(
            snapshot: ReminderListSnapshot(
                generation: 10,
                items: [disabled],
                availableTags: []
            ),
            actions: coordinator
        )

        model.publish(ReminderListSnapshot(
            generation: 11,
            items: [enabled],
            availableTags: []
        ))
        model.publish(ReminderListSnapshot(
            generation: 11,
            items: [disabled],
            availableTags: []
        ))
        model.publish(ReminderListSnapshot(
            generation: 10,
            items: [disabled],
            availableTags: []
        ))

        #expect(model.snapshot.generation == 11)
        #expect(model.items == [enabled])
        #expect(coordinator.enabledValue(for: id, fallback: false))
    }

    @MainActor
    @Test func publicationWhileEnabledSaveIsWorkingWaitsForPostCompletionGeneration() async {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let authoritativeDisabled = ReminderListItemPresentation.fixture(
            id: id.uuidString,
            lifecycleStatus: .disabled,
            enabled: false
        )
        let action = SuspendedEnabledOutcomeAction()
        let coordinator = ReminderActionCoordinator(handlers: ReminderActionHandlers(
            setEnabled: { command in await action.execute(command) },
            delete: { _ in }
        ))
        let model = ReminderListModel(
            snapshot: ReminderListSnapshot(
                generation: 1,
                items: [authoritativeDisabled],
                availableTags: []
            ),
            actions: coordinator
        )
        let save = Task { @MainActor in
            await coordinator.setEnabled(true, for: id, fallback: model.items[0].enabled)
        }
        await action.waitUntilCalled()

        model.publish(ReminderListSnapshot(
            generation: 2,
            items: [authoritativeDisabled],
            availableTags: []
        ))
        #expect(coordinator.enabledValue(for: id, fallback: false))
        #expect(coordinator.state == .working(id))

        await action.resolve(.saved(id))
        #expect(await save.value)
        #expect(coordinator.enabledValue(for: id, fallback: false))

        model.publish(ReminderListSnapshot(
            generation: 3,
            items: [authoritativeDisabled],
            availableTags: []
        ))
        #expect(!coordinator.enabledValue(for: id, fallback: true))
    }

    @MainActor
    @Test func enabledCapacityPendingPublicationWaitsForAcknowledgedCompletion() async {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let authoritativeDisabled = ReminderListItemPresentation.fixture(
            id: id.uuidString,
            lifecycleStatus: .disabled,
            enabled: false
        )
        let warning = CapacityWarning(
            reminderID: id,
            earliestGroupID: AlertGroupID(
                reminderID: id,
                baseOccurrenceInstant: date("2040-08-31T13:30:00Z")
            ),
            planningCapacity: 60
        )
        let recorder = EnabledOutcomeRecorder(outcomes: [
            .requiresCapacityConfirmation(warning),
            .saved(id)
        ])
        let coordinator = ReminderActionCoordinator(handlers: ReminderActionHandlers(
            setEnabled: { command in try await recorder.execute(command) },
            delete: { _ in }
        ))
        let model = ReminderListModel(
            snapshot: ReminderListSnapshot(
                generation: 1,
                items: [authoritativeDisabled],
                availableTags: []
            ),
            actions: coordinator
        )

        await coordinator.setEnabled(true, for: id, fallback: model.items[0].enabled)

        #expect(coordinator.state == .requiresCapacityConfirmation(id, true, warning))
        #expect(coordinator.enabledValue(for: id, fallback: false))

        model.publish(ReminderListSnapshot(
            generation: 2,
            items: [authoritativeDisabled],
            availableTags: []
        ))
        #expect(coordinator.state == .requiresCapacityConfirmation(id, true, warning))
        #expect(coordinator.enabledValue(for: id, fallback: false))

        let saved = await coordinator.confirmEnabledCapacityChange(id)

        #expect(saved)
        #expect(coordinator.state == .idle)
        #expect(coordinator.enabledValue(for: id, fallback: false))

        model.publish(ReminderListSnapshot(
            generation: 3,
            items: [authoritativeDisabled],
            availableTags: []
        ))
        #expect(!coordinator.enabledValue(for: id, fallback: true))
        #expect(await recorder.recordedCommands() == [
            SetReminderEnabledCommand(
                reminderID: id,
                enabled: true,
                capacityConsent: .notProvided
            ),
            SetReminderEnabledCommand(
                reminderID: id,
                enabled: true,
                capacityConsent: .acknowledged
            )
        ])
    }

    @MainActor
    @Test func deletedReminderClearsRegularDestinationSelectionAndCaches() {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let router = routerWithRegisteredReminder(id: id)
        router.synchronizeLayout(.regular)
        router.showReminder(id)

        #expect(router.regularDestination == .reminderDetail(id))
        #expect(router.selectedReminderID == id)
        #expect(router.detailModel(for: id) != nil)
        #expect(router.formModel(for: id) != nil)

        router.reminderWasDeleted(id)

        #expect(router.regularDestination == nil)
        #expect(router.selectedReminderID == nil)
        #expect(router.detailModel(for: id) == nil)
        #expect(router.formModel(for: id) == nil)
    }

    @MainActor
    @Test func compactDeletionCannotResurrectReminderAfterRegularTransition() {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let router = routerWithRegisteredReminder(id: id)
        router.showReminder(id)
        router.showEdit(id)

        #expect(router.compactPath == [.reminderDetail(id), .reminderEdit(id)])

        router.reminderWasDeleted(id)
        router.synchronizeLayout(.regular)

        #expect(router.compactPath.isEmpty)
        #expect(router.regularDestination == nil)
        #expect(router.selectedReminderID == nil)
    }

    @MainActor
    @Test func compactPathBindingPopClearsExitedSelectionBeforeRegularTransition() {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let router = routerWithRegisteredReminder(id: id)
        router.showReminder(id)
        router.showEdit(id)

        router.setCompactPathFromSystem([.reminderDetail(id)])
        #expect(router.selectedReminderID == id)

        router.setCompactPathFromSystem([])
        router.synchronizeLayout(.regular)

        #expect(router.selectedReminderID == nil)
        #expect(router.regularDestination == nil)
    }

    @MainActor
    @Test func delayedDeleteStillInvalidatesRouterAfterCompactViewIsPopped() async {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let gate = SuspendedReminderDeleteAction()
        let router = routerWithRegisteredReminder(
            id: id,
            delete: { reminderID in try await gate.delete(reminderID) }
        )
        router.showReminder(id)
        router.actions.requestDelete(id)
        let deletion = Task { @MainActor in
            await router.performReminderDeletion(id) {
                await router.actions.confirmDelete(id)
            }
        }
        await gate.waitUntilCalled()

        router.compactPath = []
        await gate.succeed()

        #expect(await deletion.value)
        router.synchronizeLayout(.regular)
        #expect(router.regularDestination == nil)
        #expect(router.selectedReminderID == nil)
        #expect(router.detailModel(for: id) == nil)
        #expect(router.formModel(for: id) == nil)
    }

    @MainActor
    @Test func failedDeleteDoesNotInvalidateRouterState() async {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let router = routerWithRegisteredReminder(
            id: id,
            delete: { _ in throw ReminderManagementActionProbeError.failed }
        )
        router.synchronizeLayout(.regular)
        router.showReminder(id)
        router.actions.requestDelete(id)

        let deleted = await router.performReminderDeletion(id) {
            await router.actions.confirmDelete(id)
        }

        #expect(!deleted)
        #expect(router.regularDestination == .reminderDetail(id))
        #expect(router.selectedReminderID == id)
        #expect(router.detailModel(for: id) != nil)
        #expect(router.formModel(for: id) != nil)
    }

    @MainActor
    @Test func delayedFormDeleteStillInvalidatesRouterAfterEditViewIsPopped() async {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let gate = SuspendedReminderDeleteAction()
        let router = routerWithRegisteredReminder(
            id: id,
            formDelete: { reminderID in try await gate.delete(reminderID) }
        )
        router.showReminder(id)
        router.showEdit(id)
        guard let form = router.formModel(for: id) else {
            Issue.record("Expected a registered edit form")
            return
        }
        form.requestDeleteConfirmation()
        let deletion = Task { @MainActor in
            await router.performReminderDeletion(id) {
                await form.confirmDelete()
            }
        }
        await gate.waitUntilCalled()

        router.compactPath = []
        await gate.succeed()

        #expect(await deletion.value)
        router.synchronizeLayout(.regular)
        #expect(router.regularDestination == nil)
        #expect(router.selectedReminderID == nil)
        #expect(router.detailModel(for: id) == nil)
        #expect(router.formModel(for: id) == nil)
    }

    @MainActor
    @Test func alertDismissalAfterDetailConfirmationCannotCancelDelete() async {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let recorder = ReminderManagementActionRecorder()
        let router = routerWithRegisteredReminder(
            id: id,
            delete: { reminderID in await recorder.recordDelete(reminderID) }
        )
        router.showReminder(id)
        router.actions.requestDelete(id)

        #expect(router.actions.consumeDeleteConfirmation(id))
        router.actions.cancelDelete(id)
        let deleted = await router.performReminderDeletion(id) {
            await router.actions.performConfirmedDelete(id)
        }

        #expect(deleted)
        #expect(await recorder.deletedIDs() == [id])
        #expect(router.compactPath.isEmpty)
        #expect(router.selectedReminderID == nil)
    }

    @MainActor
    @Test func alertDismissalAfterFormConfirmationCannotCancelDelete() async {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let recorder = ReminderManagementActionRecorder()
        let router = routerWithRegisteredReminder(
            id: id,
            formDelete: { reminderID in await recorder.recordDelete(reminderID) }
        )
        router.showReminder(id)
        router.showEdit(id)
        guard let form = router.formModel(for: id) else {
            Issue.record("Expected a registered edit form")
            return
        }
        form.requestDeleteConfirmation()

        #expect(form.consumeDeleteConfirmation())
        form.cancelDeleteConfirmation()
        let deleted = await router.performReminderDeletion(id) {
            await form.performConfirmedDelete()
        }

        #expect(deleted)
        #expect(await recorder.deletedIDs() == [id])
        #expect(router.compactPath.isEmpty)
        #expect(router.selectedReminderID == nil)
    }

    @MainActor
    @Test func successfulCompactSaveCompletesFormRouteAndEvictsSession() async {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let router = routerWithRegisteredReminder(id: id)
        router.showReminder(id)
        router.showEdit(id)
        guard let form = router.formModel(for: id) else {
            Issue.record("Expected a registered edit form")
            return
        }

        let saved = await router.performReminderSave(id) {
            await form.save()
        }

        #expect(saved)
        #expect(router.compactPath == [.reminderDetail(id)])
        #expect(router.formModel(for: id) == nil)
    }

    @MainActor
    @Test func successfulRegularSaveClearsFormDestinationAndEvictsSession() async {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let router = routerWithRegisteredReminder(id: id)
        router.synchronizeLayout(.regular)
        router.showEdit(id)
        guard let form = router.formModel(for: id) else {
            Issue.record("Expected a registered edit form")
            return
        }

        let saved = await router.performReminderSave(id) {
            await form.save()
        }

        #expect(saved)
        #expect(router.regularDestination == nil)
        #expect(router.formModel(for: id) == nil)
    }

    @MainActor
    @Test func failedSaveRetainsFormRouteAndSession() async {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let router = routerWithRegisteredReminder(
            id: id,
            formSave: { _, _, _ in throw ReminderManagementActionProbeError.failed }
        )
        router.showEdit(id)
        guard let form = router.formModel(for: id) else {
            Issue.record("Expected a registered edit form")
            return
        }

        let saved = await router.performReminderSave(id) {
            await form.save()
        }

        #expect(!saved)
        #expect(router.compactPath == [.reminderEdit(id)])
        #expect(router.formModel(for: id) === form)
    }

    @MainActor
    @Test func compactPopDuringSaveStillEvictsCompletedFormSession() async {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let gate = SuspendedReminderSaveAction()
        let router = routerWithRegisteredReminder(
            id: id,
            formSave: { draft, _, _ in await gate.save(draft) }
        )
        router.showReminder(id)
        router.showEdit(id)
        guard let form = router.formModel(for: id) else {
            Issue.record("Expected a registered edit form")
            return
        }
        let save = Task { @MainActor in
            await router.performReminderSave(id) { await form.save() }
        }
        await gate.waitUntilCalled()

        router.compactPath = [.reminderDetail(id)]
        await gate.resolve(.saved(id))

        #expect(await save.value)
        #expect(router.compactPath == [.reminderDetail(id)])
        #expect(router.formModel(for: id) == nil)
    }

    @MainActor
    @Test func regularDismissDuringSaveStillEvictsCompletedFormSession() async {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let gate = SuspendedReminderSaveAction()
        let router = routerWithRegisteredReminder(
            id: id,
            formSave: { draft, _, _ in await gate.save(draft) }
        )
        router.synchronizeLayout(.regular)
        router.showEdit(id)
        guard let form = router.formModel(for: id) else {
            Issue.record("Expected a registered edit form")
            return
        }
        let save = Task { @MainActor in
            await router.performReminderSave(id) { await form.save() }
        }
        await gate.waitUntilCalled()

        router.regularDestination = nil
        await gate.resolve(.saved(id))

        #expect(await save.value)
        #expect(router.regularDestination == nil)
        #expect(router.formModel(for: id) == nil)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    @MainActor
    private func routerWithRegisteredReminder(
        id: UUID,
        delete: @escaping @Sendable (UUID) async throws -> Void = { _ in },
        formDelete: @escaping @Sendable (UUID) async throws -> Void = { _ in },
        formSave: @escaping @Sendable (
            ReminderDraft,
            CapacityConsent,
            ExpiredScheduleConsent
        ) async throws -> SaveReminderOutcome = { draft, _, _ in .saved(draft.id) }
    ) -> AppRouter {
        let coordinator = ReminderActionCoordinator(handlers: ReminderActionHandlers(
            setEnabled: { command in .saved(command.reminderID) },
            delete: delete
        ))
        let router = AppRouter(actions: coordinator)
        let item = ReminderListItemPresentation.fixture(
            id: id.uuidString,
            lifecycleStatus: .active
        )
        router.register(detail: ReminderDetailModel(
            item: item,
            sourceTime: nil,
            currentDeviceTime: nil,
            localizedRepeatSummary: nil,
            nextNotifications: [],
            alertGroups: [],
            scheduledThrough: nil,
            requestDiagnostics: []
        ))
        let schedule = ScheduleDefinition(
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
        )
        router.register(form: ReminderFormModel(
            snapshot: ReminderSnapshot(
                id: id,
                title: "Registered reminder",
                notes: nil,
                urlString: nil,
                enabled: true,
                schedule: .valid(schedule, sourceVersion: 1, originalData: Data([1])),
                tagIDs: [],
                createdAt: date("2040-01-01T00:00:00Z"),
                updatedAt: date("2040-08-01T00:00:00Z")
            ),
            savedRepeatPresentation: .standard(localizedSummary: "Every day"),
            now: date("2040-08-01T00:00:00Z"),
            actions: ReminderFormActions(
                save: formSave,
                delete: formDelete
            )
        ))
        return router
    }
}

private actor ReminderManagementActionRecorder {
    private var enabled: [SetReminderEnabledCommand] = []
    private var deleted: [UUID] = []

    func recordEnabled(_ command: SetReminderEnabledCommand) {
        enabled.append(command)
    }

    func recordDelete(_ id: UUID) {
        deleted.append(id)
    }

    func enabledCalls() -> [SetReminderEnabledCommand] { enabled }
    func deletedIDs() -> [UUID] { deleted }
}

private actor EnabledOutcomeRecorder {
    private var outcomes: [SaveReminderOutcome]
    private var commands: [SetReminderEnabledCommand] = []

    init(outcomes: [SaveReminderOutcome]) {
        self.outcomes = outcomes
    }

    func execute(_ command: SetReminderEnabledCommand) throws -> SaveReminderOutcome {
        commands.append(command)
        guard !outcomes.isEmpty else { throw ReminderManagementActionProbeError.failed }
        return outcomes.removeFirst()
    }

    func recordedCommands() -> [SetReminderEnabledCommand] { commands }
}

private actor SuspendedEnabledOutcomeAction {
    private var called = false
    private var callWaiters: [CheckedContinuation<Void, Never>] = []
    private var resultContinuation: CheckedContinuation<SaveReminderOutcome, Never>?

    func execute(_ command: SetReminderEnabledCommand) async -> SaveReminderOutcome {
        called = true
        let waiters = callWaiters
        callWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
        }
    }

    func waitUntilCalled() async {
        guard !called else { return }
        await withCheckedContinuation { continuation in
            callWaiters.append(continuation)
        }
    }

    func resolve(_ outcome: SaveReminderOutcome) {
        resultContinuation?.resume(returning: outcome)
        resultContinuation = nil
    }
}

private enum ReminderManagementActionProbeError: Error {
    case failed
}

private actor SuspendedReminderDeleteAction {
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func delete(_ id: UUID) async throws {
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilCalled() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func succeed() {
        continuation?.resume()
        continuation = nil
    }
}

private actor SuspendedReminderSaveAction {
    private var called = false
    private var callWaiters: [CheckedContinuation<Void, Never>] = []
    private var resultContinuation: CheckedContinuation<SaveReminderOutcome, Never>?

    func save(_ draft: ReminderDraft) async -> SaveReminderOutcome {
        called = true
        let waiters = callWaiters
        callWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
        }
    }

    func waitUntilCalled() async {
        guard !called else { return }
        await withCheckedContinuation { continuation in
            callWaiters.append(continuation)
        }
    }

    func resolve(_ outcome: SaveReminderOutcome) {
        resultContinuation?.resume(returning: outcome)
        resultContinuation = nil
    }
}

private extension PhysicalNotificationPresentation {
    static func fixture(alertInstant: Date) -> Self {
        Self(
            alertInstant: alertInstant,
            reasons: [PhysicalNotificationReasonPresentation(
                role: .primary,
                kind: .main,
                baseOccurrenceInstant: alertInstant
            )],
            sourceTime: alertInstant,
            deviceLocalTime: alertInstant
        )
    }
}

private extension ReminderListItemPresentation {
    static func fixture(
        id: String,
        lifecycleStatus: LifecycleStatus,
        nextAlertInstant: Date? = nil,
        updatedAt: Date = .distantPast,
        tags: [ReminderTagPresentation] = [],
        enabled: Bool = true
    ) -> Self {
        Self(
            id: UUID(uuidString: id)!,
            title: id,
            reminderStatus: ReminderStatus(primary: lifecycleStatus, secondary: []),
            deviceSchedulingStatus: lifecycleStatus == .active ? .scheduled : .notApplicable,
            nextPresentation: nextAlertInstant.map {
                .rolling(PhysicalNotificationPresentation.fixture(alertInstant: $0))
            },
            tags: tags,
            enabled: enabled,
            updatedAt: updatedAt
        )
    }
}
