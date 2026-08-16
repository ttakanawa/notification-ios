import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import NotificationManagerPersistence
import Testing
import UserNotifications

@testable import NotificationManager

@Suite("Offline local persistence acceptance")
struct OfflinePersistenceTests {
    @Test func localCRUDAndSchedulingRequireNoNetworkContract() async throws {
        let result = try await OfflineAcceptanceHarness().exerciseLocalStore()

        #expect(result.createdID == result.draftID)
        #expect(result.snapshotID == result.draftID)
        #expect(result.materializedRoutingID == result.draftID.uuidString.lowercased())
        #expect(result.editedTitle == "Offline itinerary updated")
        #expect(result.deletedReminderIsAbsent)
        #expect(result.cleanedReminderIDs == [result.draftID])
        #expect(
            result.reconcileReasons == [
                .reminderSaved(result.draftID),
                .reminderSaved(result.draftID),
                .reminderDeleted(result.draftID)
            ])
    }
}

private struct OfflineAcceptanceResult: Sendable {
    let draftID: UUID
    let createdID: UUID
    let snapshotID: UUID
    let materializedRoutingID: String?
    let editedTitle: String
    let deletedReminderIsAbsent: Bool
    let cleanedReminderIDs: [UUID]
    let reconcileReasons: [ReconcileReason]
}

private struct OfflineAcceptanceHarness {
    private let reminderID = UUID(uuidString: "123e4567-e89b-12d3-a456-426614174000")!
    private let evaluationNow = offlineDate("2039-12-01T00:00:00Z")

    func exerciseLocalStore() async throws -> OfflineAcceptanceResult {
        // This boundary intentionally controls only a local SwiftData store. It makes no claim
        // that a test can force CloudKit or network state.
        let repository = try SwiftDataReminderRepository.inMemory()
        let preference = OfflinePreferenceStore(enabled: true)
        let reconcileTrace = OfflineReconcileTrace()
        let cleanupTrace = OfflineCleanupTrace()
        let save = SaveReminderUseCase(
            repository: repository,
            scheduleCodec: SchedulePayloadCodec(),
            preferenceStore: preference,
            authorizationState: { .allowed },
            reconcileRequester: reconcileTrace,
            now: { evaluationNow }
        )
        let schedule = ScheduleDefinition(
            source: SourceWallClock(
                year: 2040,
                month: 6,
                day: 3,
                hour: 9,
                minute: 30,
                timeZoneIdentifier: "America/New_York"
            ),
            rule: .none,
            end: .never,
            early: EarlyReminder(value: 5, unit: .minutes, mainEnabled: true)
        )
        var draft = ReminderDraft(
            id: reminderID,
            title: "Offline itinerary",
            notes: "Cached locally",
            urlString: "https://example.com/offline",
            enabled: true,
            scheduleChange: .replace(schedule),
            createdAt: evaluationNow,
            updatedAt: evaluationNow
        )

        let createdID = try savedID(await save.execute(draft: draft))
        let snapshot = try await repository.fetchCompleteSnapshot()
        guard let stored = snapshot.reminders.first else {
            throw OfflineAcceptanceError.missingSnapshot
        }
        let plan = try LogicalNotificationPlanner().plan(
            PlannerInput(
                snapshot: snapshot,
                evaluationNow: evaluationNow,
                deviceNotificationsEnabled: true,
                authorizationAllowsScheduling: true,
                capacity: 60,
                recurrenceEnvironment: FoundationRecurrenceEnvironment()
            ))
        guard let logicalRequest = plan.requests.first else {
            throw OfflineAcceptanceError.missingLogicalRequest
        }
        let materialized = try NotificationRequestMaterializer(
            formatter: OfflineNotificationTextFormatter()
        ).materialize(
            logicalRequest,
            input: MaterializationInput(
                reminder: stored,
                locale: Locale(identifier: "en_US"),
                evaluationNow: evaluationNow,
                recurrenceEnvironment: FoundationRecurrenceEnvironment()
            )
        )

        draft = ReminderDraft(snapshot: stored)
        draft.title = "Offline itinerary updated"
        _ = try savedID(await save.execute(draft: draft))
        guard let edited = try await repository.reminder(id: reminderID) else {
            throw OfflineAcceptanceError.missingEditedReminder
        }

        let delete = DeleteReminderUseCase(
            repository: repository,
            notificationCleanup: cleanupTrace,
            reconcileRequester: reconcileTrace
        )
        try await delete.execute(reminderID: reminderID)
        let deletedReminderIsAbsent = try await repository.reminder(id: reminderID) == nil

        return OfflineAcceptanceResult(
            draftID: reminderID,
            createdID: createdID,
            snapshotID: stored.id,
            materializedRoutingID: materialized.content.userInfo[
                "notification-manager.reminder-id"
            ] as? String,
            editedTitle: edited.title,
            deletedReminderIsAbsent: deletedReminderIsAbsent,
            cleanedReminderIDs: await cleanupTrace.reminderIDs,
            reconcileReasons: await reconcileTrace.reasons
        )
    }

    private func savedID(_ outcome: SaveReminderOutcome) throws -> UUID {
        guard case .saved(let id) = outcome else {
            throw OfflineAcceptanceError.unexpectedSaveOutcome
        }
        return id
    }
}

private actor OfflinePreferenceStore: DeviceNotificationPreferenceStore {
    private var enabled: Bool

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func isEnabled() -> Bool { enabled }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
    }
}

private actor OfflineReconcileTrace: ReconcileRequesting {
    private(set) var reasons: [ReconcileReason] = []

    func requestReconcile(_ reason: ReconcileReason) {
        reasons.append(reason)
    }
}

private actor OfflineCleanupTrace: NotificationCleanup {
    private(set) var reminderIDs: [UUID] = []

    func removeNotifications(for reminderID: UUID) {
        reminderIDs.append(reminderID)
    }

    func removeAllPendingAppNotifications() {}
}

private struct OfflineNotificationTextFormatter: LocalizedNotificationTextFormatting {
    func content(for input: NotificationTextInput, locale: Locale) -> NotificationText {
        NotificationText(title: input.title, body: "Offline reminder", ellipsis: "…")
    }
}

private enum OfflineAcceptanceError: Error {
    case missingSnapshot
    case missingLogicalRequest
    case missingEditedReminder
    case unexpectedSaveOutcome
}

private func offlineDate(_ value: String) -> Date {
    guard let date = ISO8601DateFormatter().date(from: value) else {
        preconditionFailure("Invalid offline acceptance date fixture")
    }
    return date
}
