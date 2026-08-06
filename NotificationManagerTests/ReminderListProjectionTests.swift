import Foundation
import NotificationManagerDomain
import Testing
@testable import NotificationManager

struct ReminderListProjectionTests {
    @Test func activeCapacityFailureRemainsUpcoming() {
        let item = ReminderListItemPresentation(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            title: "Visa renewal",
            lifecycleStatus: .active,
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
            lifecycleStatus: .active,
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
        let model = ReminderListModel(
            items: [tagged],
            availableTags: [beta, upperA, lowerA]
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
            lifecycleStatus: .active,
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
            setEnabled: { id, enabled in await recorder.recordEnabled(id, enabled) },
            delete: { id in await recorder.recordDelete(id) }
        ))
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!

        await coordinator.setEnabled(false, for: id, fallback: true)

        #expect(!coordinator.enabledValue(for: id, fallback: true))
        #expect(await recorder.enabledCalls() == [EnabledActionCall(id: id, enabled: false)])

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
            setEnabled: { _, _ in throw ReminderManagementActionProbeError.failed },
            delete: { _ in }
        ))
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!

        await coordinator.setEnabled(false, for: id, fallback: true)

        #expect(coordinator.enabledValue(for: id, fallback: true))
        #expect(coordinator.state == .failed(id, .enabledChange))
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

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    @MainActor
    private func routerWithRegisteredReminder(
        id: UUID,
        delete: @escaping @Sendable (UUID) async throws -> Void = { _ in },
        formDelete: @escaping @Sendable (UUID) async throws -> Void = { _ in }
    ) -> AppRouter {
        let coordinator = ReminderActionCoordinator(handlers: ReminderActionHandlers(
            setEnabled: { _, _ in },
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
                save: { draft, _, _ in .saved(draft.id) },
                delete: formDelete
            )
        ))
        return router
    }
}

private struct EnabledActionCall: Sendable, Equatable {
    let id: UUID
    let enabled: Bool
}

private actor ReminderManagementActionRecorder {
    private var enabled: [EnabledActionCall] = []
    private var deleted: [UUID] = []

    func recordEnabled(_ id: UUID, _ value: Bool) {
        enabled.append(EnabledActionCall(id: id, enabled: value))
    }

    func recordDelete(_ id: UUID) {
        deleted.append(id)
    }

    func enabledCalls() -> [EnabledActionCall] { enabled }
    func deletedIDs() -> [UUID] { deleted }
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

private extension PhysicalNotificationPresentation {
    static func fixture(alertInstant: Date) -> Self {
        Self(
            alertInstant: alertInstant,
            primaryReason: .main,
            secondaryEarlyReasonCount: 0,
            baseOccurrenceInstants: [alertInstant],
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
        tags: [ReminderTagPresentation] = []
    ) -> Self {
        Self(
            id: UUID(uuidString: id)!,
            title: id,
            lifecycleStatus: lifecycleStatus,
            deviceSchedulingStatus: lifecycleStatus == .active ? .scheduled : .notApplicable,
            nextPresentation: nextAlertInstant.map {
                .rolling(PhysicalNotificationPresentation.fixture(alertInstant: $0))
            },
            tags: tags,
            updatedAt: updatedAt
        )
    }
}
