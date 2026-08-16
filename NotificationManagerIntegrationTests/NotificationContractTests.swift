import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import NotificationManagerPersistence
import Testing
import UserNotifications

@testable import NotificationManager

@Suite("Notification acceptance contracts")
struct NotificationContractTests {
    @Test func payloadIdentifiersTriggerKindsLocalizationAndCleanupStayCompatible() async throws {
        let result = try await NotificationContractHarness().payloadAndCleanupContract()

        #expect(result.payloadFormat == "notification-manager.schedule")
        #expect(result.payloadVersion == 2)
        #expect(result.directRequestsAreRepeating)
        #expect(result.rollingRequestsAreOneShot)
        #expect(result.identifierClassificationsAreCurrent)
        #expect(result.localeInvariantIdentifiersAndTriggers)
        #expect(result.localizedBodiesDiffer)
        #expect(result.remainingPendingIdentifiers == ["other-app.notification"])
        #expect(result.remainingDeliveredIdentifiers == ["other-app.notification"])
    }

    @Test func reconcilerPartialAddFailureKeepsSuccessAndFansOutError() async throws {
        let result = try await NotificationContractHarness().partialFailureContract()

        #expect(result.successfulIdentifiers.count == 1)
        #expect(result.publishedPendingOrAdded == Set(result.successfulIdentifiers))
        #expect(result.scheduledOutcomeCount == 1)
        #expect(result.errorOutcomeCount == 1)
        #expect(result.globalFailure == nil)
    }

    @MainActor
    @Test func materializedRequestUsesEligibilityAndCurrentStoreOnly() async throws {
        let result = try await NotificationContractHarness().routingContract()

        #expect(result.presentationRequestedBannerListAndSound)
        #expect(result.defaultDestination == .reminderEdit(result.reminderID))
        #expect(result.openedURL == URL(string: "https://example.com/current"))
        #expect(result.missingDestination == .notificationUnavailable)
    }
}

private struct PayloadAndCleanupContractResult: Sendable {
    let payloadFormat: String
    let payloadVersion: UInt32
    let directRequestsAreRepeating: Bool
    let rollingRequestsAreOneShot: Bool
    let identifierClassificationsAreCurrent: Bool
    let localeInvariantIdentifiersAndTriggers: Bool
    let localizedBodiesDiffer: Bool
    let remainingPendingIdentifiers: [String]
    let remainingDeliveredIdentifiers: [String]
}

private struct PartialFailureContractResult: Sendable {
    let successfulIdentifiers: [String]
    let publishedPendingOrAdded: Set<String>
    let scheduledOutcomeCount: Int
    let errorOutcomeCount: Int
    let globalFailure: SchedulingGlobalFailure?
}

private struct RoutingContractResult: Sendable {
    let reminderID: UUID
    let presentationRequestedBannerListAndSound: Bool
    let defaultDestination: NotificationResponseOutcome
    let openedURL: URL?
    let missingDestination: NotificationResponseOutcome
}

private struct NotificationContractHarness {
    private let primaryID = UUID(uuidString: "123e4567-e89b-12d3-a456-426614174000")!
    private let secondaryID = UUID(uuidString: "223e4567-e89b-12d3-a456-426614174000")!
    private let evaluationNow = contractDate("2039-12-01T00:00:00Z")
    private let environment = FoundationRecurrenceEnvironment()

    func payloadAndCleanupContract() async throws -> PayloadAndCleanupContractResult {
        let codec = SchedulePayloadCodec()
        let directSchedule = weekdaySchedule()
        let payload = try codec.encodeCurrent(directSchedule)
        guard case .valid(let decodedSchedule, let sourceVersion, _) = codec.decode(payload.data),
            sourceVersion == payload.version,
            decodedSchedule == directSchedule,
            let envelope = try JSONSerialization.jsonObject(with: payload.data) as? [String: Any],
            let payloadFormat = envelope["format"] as? String,
            let payloadVersionNumber = envelope["version"] as? NSNumber
        else {
            throw NotificationContractError.invalidPayloadRoundTrip
        }
        let payloadVersion = UInt32(payloadVersionNumber.uintValue)
        let directReminder = reminder(
            id: primaryID,
            title: "Direct weekday",
            schedule: directSchedule,
            payload: payload
        )
        let directPlan = try plan(reminders: [directReminder])

        let rollingSchedule = ScheduleDefinition(
            source: directSchedule.source,
            rule: .daily(interval: 2),
            end: .never,
            early: nil
        )
        let rollingPayload = try codec.encodeCurrent(rollingSchedule)
        let rollingReminder = reminder(
            id: secondaryID,
            title: "Rolling interval",
            schedule: rollingSchedule,
            payload: rollingPayload
        )
        let rollingPlan = try plan(reminders: [rollingReminder])
        guard let directLogical = directPlan.requests.first else {
            throw NotificationContractError.missingDirectRequest
        }
        let materializer = NotificationRequestMaterializer(
            formatter: ContractNotificationTextFormatter()
        )
        let english = try materializer.materialize(
            directLogical,
            input: MaterializationInput(
                reminder: directReminder,
                locale: Locale(identifier: "en_US"),
                evaluationNow: evaluationNow,
                recurrenceEnvironment: environment
            )
        )
        let japanese = try materializer.materialize(
            directLogical,
            input: MaterializationInput(
                reminder: directReminder,
                locale: Locale(identifier: "ja_JP"),
                evaluationNow: evaluationNow,
                recurrenceEnvironment: environment
            )
        )
        guard let englishTrigger = english.trigger as? UNCalendarNotificationTrigger,
            let japaneseTrigger = japanese.trigger as? UNCalendarNotificationTrigger
        else {
            throw NotificationContractError.unexpectedTrigger
        }

        let futureNamespace = "notification-manager.local.v9.future-shape"
        let unrelated = "other-app.notification"
        let center = ContractNotificationCenter(
            pending: [
                NotificationInventoryItem(identifier: directLogical.identifier),
                NotificationInventoryItem(
                    identifier: futureNamespace,
                    reminderRoutingValue: primaryID.uuidString.lowercased()
                ),
                NotificationInventoryItem(identifier: unrelated)
            ],
            delivered: [
                NotificationInventoryItem(
                    identifier: futureNamespace,
                    reminderRoutingValue: primaryID.uuidString.lowercased()
                ),
                NotificationInventoryItem(identifier: unrelated)
            ]
        )
        await NotificationCleanupService(notificationCenter: center)
            .removeNotifications(for: primaryID)

        let classificationsAreCurrent = (directPlan.requests + rollingPlan.requests)
            .allSatisfy { request in
                switch NotificationIdentifierCodec().classify(request.identifier) {
                case .currentOneShot(let reminderID, _),
                    .currentRepeating(let reminderID, _):
                    reminderID == request.reminderID
                case .appOwnedStale, .unrelated:
                    false
                }
            }
        return PayloadAndCleanupContractResult(
            payloadFormat: payloadFormat,
            payloadVersion: payloadVersion,
            directRequestsAreRepeating: directPlan.requests.count == 5
                && directPlan.requests.allSatisfy(\.isRepeating),
            rollingRequestsAreOneShot: !rollingPlan.requests.isEmpty
                && rollingPlan.requests.allSatisfy { !$0.isRepeating },
            identifierClassificationsAreCurrent: classificationsAreCurrent,
            localeInvariantIdentifiersAndTriggers: english.identifier == japanese.identifier
                && englishTrigger.dateComponents == japaneseTrigger.dateComponents
                && englishTrigger.repeats == japaneseTrigger.repeats,
            localizedBodiesDiffer: english.content.body != japanese.content.body,
            remainingPendingIdentifiers: center.pendingIdentifiers,
            remainingDeliveredIdentifiers: center.deliveredIdentifiers
        )
    }

    func partialFailureContract() async throws -> PartialFailureContractResult {
        let first = try oneShotReminder(
            id: primaryID,
            title: "First",
            sourceDay: 3
        )
        let second = try oneShotReminder(
            id: secondaryID,
            title: "Second",
            sourceDay: 4
        )
        let snapshot = CompleteReminderSnapshot(reminders: [first, second], tags: [])
        let expectedPlan = try plan(reminders: snapshot.reminders)
        guard expectedPlan.requests.count == 2,
            let failedIdentifier = expectedPlan.requests.last?.identifier
        else {
            throw NotificationContractError.unexpectedRequestCount
        }
        let center = ContractNotificationCenter(addFailures: [failedIdentifier])
        let stateStore = DeviceSchedulingStateStore()
        let worker = NotificationReconcileWorker(
            snapshotLoader: ContractSnapshotLoader(snapshot: snapshot),
            preferenceStore: ContractPreferenceStore(enabled: true),
            authorizationProvider: ContractAuthorizationProvider(),
            notificationCenter: center,
            eligibilityIndexStore: ForegroundEligibilityIndexStore(),
            stateStore: stateStore,
            materializer: NotificationRequestMaterializer(
                formatter: ContractNotificationTextFormatter()
            ),
            recurrenceEnvironmentProvider: { FoundationRecurrenceEnvironment() },
            localeProvider: { Locale(identifier: "en_US") },
            clock: NotificationReconcileClock(
                now: { evaluationNow },
                sleep: { _ in throw CancellationError() }
            ),
            retryDelays: []
        )

        await worker.requestReconcile(.modelChanged)
        await worker.waitUntilIdle()
        let state = await stateStore.snapshot()

        return PartialFailureContractResult(
            successfulIdentifiers: center.addedIdentifiers,
            publishedPendingOrAdded: state.pendingOrAddedIdentifiers,
            scheduledOutcomeCount: state.outcomes.values.filter { $0 == .scheduled }.count,
            errorOutcomeCount: state.outcomes.values.filter { $0 == .unscheduledError }.count,
            globalFailure: state.globalFailure
        )
    }

    @MainActor
    func routingContract() async throws -> RoutingContractResult {
        let reminder = try oneShotReminder(
            id: primaryID,
            title: "Current reminder",
            sourceDay: 3,
            urlString: "https://example.com/current"
        )
        let request = try materializedRequest(for: reminder)
        let currentStore = ContractCurrentReminderStore(reminder: reminder)
        let eligibility = ForegroundEligibilityIndexStore()
        eligibility.publish(eligibleReminderIDs: [primaryID])
        let delegate = NotificationApplicationDelegate(
            eligibilityIndexStore: eligibility,
            reminderLookup: { reminderID in
                await currentStore.reminder(id: reminderID)
            }
        )
        let presentation = delegate.immediatePresentationOptions(for: request)
        let defaultDestination = await delegate.handleResponse(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            categoryIdentifier: request.content.categoryIdentifier,
            userInfo: request.content.userInfo
        )
        let openOutcome = await delegate.handleResponse(
            actionIdentifier: NotificationApplicationDelegate.openLinkActionIdentifier,
            categoryIdentifier: NotificationApplicationDelegate.openLinkCategoryIdentifier,
            userInfo: request.content.userInfo
        )
        let openedURL: URL? =
            if case .openedURL(let value) = openOutcome {
                value
            } else {
                nil
            }
        await currentStore.delete()
        let missingDestination = await delegate.handleResponse(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            categoryIdentifier: request.content.categoryIdentifier,
            userInfo: request.content.userInfo
        )

        return RoutingContractResult(
            reminderID: primaryID,
            presentationRequestedBannerListAndSound: presentation.contains(.banner)
                && presentation.contains(.list)
                && presentation.contains(.sound),
            defaultDestination: defaultDestination,
            openedURL: openedURL,
            missingDestination: missingDestination
        )
    }

    private func plan(reminders: [ReminderSnapshot]) throws -> LogicalPlan {
        try LogicalNotificationPlanner().plan(
            PlannerInput(
                snapshot: CompleteReminderSnapshot(reminders: reminders, tags: []),
                evaluationNow: evaluationNow,
                deviceNotificationsEnabled: true,
                authorizationAllowsScheduling: true,
                capacity: 60,
                recurrenceEnvironment: environment
            ))
    }

    private func weekdaySchedule() -> ScheduleDefinition {
        ScheduleDefinition(
            source: SourceWallClock(
                year: 2039,
                month: 11,
                day: 28,
                hour: 9,
                minute: 30,
                timeZoneIdentifier: "America/New_York"
            ),
            rule: .weekly(
                interval: 1,
                weekdaySetKind: .weekday,
                weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday]
            ),
            end: .never,
            early: nil
        )
    }

    private func oneShotReminder(
        id: UUID,
        title: String,
        sourceDay: Int,
        urlString: String? = nil
    ) throws -> ReminderSnapshot {
        let schedule = ScheduleDefinition(
            source: SourceWallClock(
                year: 2040,
                month: 6,
                day: sourceDay,
                hour: 9,
                minute: 30,
                timeZoneIdentifier: "America/New_York"
            ),
            rule: .none,
            end: .never,
            early: nil
        )
        return reminder(
            id: id,
            title: title,
            urlString: urlString,
            schedule: schedule,
            payload: try SchedulePayloadCodec().encodeCurrent(schedule)
        )
    }

    private func reminder(
        id: UUID,
        title: String,
        urlString: String? = nil,
        schedule: ScheduleDefinition,
        payload: EncodedSchedulePayload
    ) -> ReminderSnapshot {
        ReminderSnapshot(
            id: id,
            title: title,
            notes: nil,
            urlString: urlString,
            enabled: true,
            schedule: .valid(
                schedule,
                sourceVersion: payload.version,
                originalData: payload.data
            ),
            tagIDs: [],
            createdAt: evaluationNow,
            updatedAt: evaluationNow
        )
    }

    private func materializedRequest(
        for reminder: ReminderSnapshot
    ) throws -> UNNotificationRequest {
        guard let logical = try plan(reminders: [reminder]).requests.first else {
            throw NotificationContractError.missingLogicalRequest
        }
        return try NotificationRequestMaterializer(
            formatter: ContractNotificationTextFormatter()
        ).materialize(
            logical,
            input: MaterializationInput(
                reminder: reminder,
                locale: Locale(identifier: "en_US"),
                evaluationNow: evaluationNow,
                recurrenceEnvironment: environment
            )
        )
    }
}

private struct ContractNotificationTextFormatter: LocalizedNotificationTextFormatting {
    func content(for input: NotificationTextInput, locale: Locale) -> NotificationText {
        NotificationText(
            title: input.title,
            body: locale.language.languageCode == .japanese ? "通知" : "Notification",
            ellipsis: "…"
        )
    }
}

private struct ContractSnapshotLoader: CompleteSchedulingSnapshotLoading {
    let snapshot: CompleteReminderSnapshot

    func loadCompleteSnapshot() async throws -> CompleteReminderSnapshot { snapshot }
}

private struct ContractPreferenceStore: DeviceNotificationPreferenceStore {
    let enabled: Bool

    func isEnabled() async -> Bool { enabled }

    func setEnabled(_ enabled: Bool) async {}
}

private struct ContractAuthorizationProvider: NotificationAuthorizationProviding {
    func currentAuthorization() async -> NotificationAuthorizationSnapshot {
        NotificationAuthorizationSnapshot(state: .allowed, diagnostic: nil)
    }
}

private final class ContractNotificationCenter: NotificationCenterClient, @unchecked Sendable {
    private struct State {
        var pending: [NotificationInventoryItem]
        var delivered: [NotificationInventoryItem]
        var addedIdentifiers: [String] = []
    }

    private let lock = NSLock()
    private let addFailures: Set<String>
    private var state: State

    init(
        pending: [NotificationInventoryItem] = [],
        delivered: [NotificationInventoryItem] = [],
        addFailures: Set<String> = []
    ) {
        state = State(pending: pending, delivered: delivered)
        self.addFailures = addFailures
    }

    var pendingIdentifiers: [String] {
        lock.withLock { state.pending.map(\.identifier) }
    }

    var deliveredIdentifiers: [String] {
        lock.withLock { state.delivered.map(\.identifier) }
    }

    var addedIdentifiers: [String] {
        lock.withLock { state.addedIdentifiers }
    }

    func pendingNotificationInventory() async throws -> [NotificationInventoryItem] {
        lock.withLock { state.pending }
    }

    func deliveredNotificationInventory() async -> [NotificationInventoryItem] {
        lock.withLock { state.delivered }
    }

    func add(_ request: UNNotificationRequest) async throws {
        let identifier = request.identifier
        if addFailures.contains(identifier) {
            throw NotificationContractError.injectedAddFailure
        }
        lock.withLock {
            state.addedIdentifiers.append(identifier)
            state.pending.removeAll { $0.identifier == identifier }
            state.pending.append(NotificationInventoryItem(identifier: identifier))
        }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        lock.withLock {
            state.pending.removeAll { identifiers.contains($0.identifier) }
        }
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {
        lock.withLock {
            state.delivered.removeAll { identifiers.contains($0.identifier) }
        }
    }
}

private actor ContractCurrentReminderStore {
    private var current: ReminderSnapshot?

    init(reminder: ReminderSnapshot) {
        current = reminder
    }

    func reminder(id: UUID) -> ReminderSnapshot? {
        current?.id == id ? current : nil
    }

    func delete() {
        current = nil
    }
}

private enum NotificationContractError: Error {
    case invalidPayloadRoundTrip
    case missingDirectRequest
    case missingLogicalRequest
    case unexpectedTrigger
    case unexpectedRequestCount
    case injectedAddFailure
}

private func contractDate(_ value: String) -> Date {
    guard let date = ISO8601DateFormatter().date(from: value) else {
        preconditionFailure("Invalid notification contract date fixture")
    }
    return date
}
