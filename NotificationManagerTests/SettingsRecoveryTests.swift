import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import NotificationManagerPersistence
import Testing
import UserNotifications
@testable import NotificationManager

@Suite("Settings and recovery")
struct SettingsRecoveryTests {
    @MainActor
    @Test func loadingUsesTheDeviceLocalDefaultOffPreference() async {
        let preference = RecordingPreferenceStore(enabled: false)
        let authorization = RecordingAuthorizationController(
            snapshots: [.fixture(rawValue: 0)]
        )
        let model = NotificationSettingsModel(
            preferenceStore: preference,
            authorizationProvider: authorization,
            authorizationRequester: authorization,
            pendingCleaner: RecordingPendingCleaner(),
            reconciler: RecordingReconciler()
        )

        await model.load()

        #expect(!model.isEnabled)
        #expect(model.authorization.rawStatus == .notDetermined)
        #expect(await authorization.requestCount == 0)
    }

    @MainActor
    @Test func turningOnFromRawNotDeterminedRequestsOnceAndRetainsIntentAfterDenial() async {
        let trace = SettingsTrace()
        let preference = RecordingPreferenceStore(enabled: false, trace: trace)
        let authorization = RecordingAuthorizationController(
            snapshots: [.fixture(rawValue: 0), .fixture(rawValue: 1)],
            trace: trace
        )
        let reconciler = RecordingReconciler(trace: trace)
        let model = NotificationSettingsModel(
            preferenceStore: preference,
            authorizationProvider: authorization,
            authorizationRequester: authorization,
            pendingCleaner: RecordingPendingCleaner(trace: trace),
            reconciler: reconciler
        )

        await model.setEnabled(true)

        #expect(model.isEnabled)
        #expect(await preference.enabled)
        #expect(model.authorization.rawStatus == .denied)
        #expect(await authorization.requestCount == 1)
        #expect(await reconciler.reasons == [.deviceSettingsChanged])
        #expect(await trace.events == [
            .preferenceSet(true),
            .authorizationRead(0),
            .authorizationRequested,
            .authorizationRead(1),
            .reconcileRequested
        ])
    }

    @MainActor
    @Test func turningOnFromDeniedNeverRequestsAuthorizationAgain() async {
        let preference = RecordingPreferenceStore(enabled: false)
        let authorization = RecordingAuthorizationController(
            snapshots: [.fixture(rawValue: 1)]
        )
        let model = NotificationSettingsModel(
            preferenceStore: preference,
            authorizationProvider: authorization,
            authorizationRequester: authorization,
            pendingCleaner: RecordingPendingCleaner(),
            reconciler: RecordingReconciler()
        )

        await model.setEnabled(true)

        #expect(model.isEnabled)
        #expect(await authorization.requestCount == 0)
        #expect(model.authorization.rawStatus == .denied)
    }

    @MainActor
    @Test func authorizationRequestFailureRetainsTheOnIntentAndSurfacesAnActionError() async {
        let preference = RecordingPreferenceStore(enabled: false)
        let authorization = RecordingAuthorizationController(
            snapshots: [.fixture(rawValue: 0), .fixture(rawValue: 0)],
            requestError: AuthorizationTestError.requestFailed
        )
        let model = NotificationSettingsModel(
            preferenceStore: preference,
            authorizationProvider: authorization,
            authorizationRequester: authorization,
            pendingCleaner: RecordingPendingCleaner(),
            reconciler: RecordingReconciler()
        )

        await model.setEnabled(true)

        #expect(model.isEnabled)
        #expect(await preference.enabled)
        #expect(model.actionError == .authorizationRequest)
        #expect(await authorization.requestCount == 1)
    }

    @MainActor
    @Test func turningOffCleansPendingRootInventoryBeforeRequestingReconcile() async {
        let trace = SettingsTrace()
        let preference = RecordingPreferenceStore(enabled: true, trace: trace)
        let authorization = RecordingAuthorizationController(
            snapshots: [.fixture(rawValue: 2)],
            trace: trace
        )
        let cleaner = RecordingPendingCleaner(trace: trace)
        let reconciler = RecordingReconciler(trace: trace)
        let model = NotificationSettingsModel(
            preferenceStore: preference,
            authorizationProvider: authorization,
            authorizationRequester: authorization,
            pendingCleaner: cleaner,
            reconciler: reconciler
        )

        await model.setEnabled(false)

        #expect(!model.isEnabled)
        #expect(await cleaner.callCount == 1)
        #expect(await trace.events == [
            .preferenceSet(false),
            .pendingCleanup,
            .reconcileRequested
        ])
    }

    @MainActor
    @Test func futureAuthorizationRawValueRemainsVisibleAndDisallowed() async {
        let authorization = RecordingAuthorizationController(
            snapshots: [.fixture(rawValue: 9_999)]
        )
        let model = NotificationSettingsModel(
            preferenceStore: RecordingPreferenceStore(enabled: true),
            authorizationProvider: authorization,
            authorizationRequester: authorization,
            pendingCleaner: RecordingPendingCleaner(),
            reconciler: RecordingReconciler()
        )

        await model.load()

        #expect(model.authorization.rawStatus == .unknown(rawValue: 9_999))
        #expect(model.authorization.rawValue == 9_999)
        #expect(!model.authorization.allowsScheduling)
    }

    @MainActor
    @Test func dataUnavailableOffPersistsAndCleansWithoutStoreBackedReconcile() async {
        let trace = SettingsTrace()
        let preference = RecordingPreferenceStore(enabled: true, trace: trace)
        let authorization = RecordingAuthorizationController(
            snapshots: [.fixture(rawValue: 2)],
            trace: trace
        )
        let cleaner = RecordingPendingCleaner(trace: trace)
        let actions = DataUnavailableActions(
            preferenceStore: preference,
            authorizationProvider: authorization,
            authorizationRequester: authorization,
            pendingCleaner: cleaner,
            retry: {}
        )

        await actions.setEnabled(false)

        #expect(!actions.isEnabled)
        #expect(await preference.enabled == false)
        #expect(await cleaner.callCount == 1)
        #expect(await trace.events == [.preferenceSet(false), .pendingCleanup])
    }

    @MainActor
    @Test func dataUnavailableCleanupFailureKeepsStoreAndPreferenceNonDestructive() async {
        let preference = RecordingPreferenceStore(enabled: true)
        let cleaner = RecordingPendingCleaner(error: PendingCleanerTestError.inventoryUnavailable)
        let authorization = RecordingAuthorizationController(
            snapshots: [.fixture(rawValue: 2)]
        )
        let actions = DataUnavailableActions(
            preferenceStore: preference,
            authorizationProvider: authorization,
            authorizationRequester: authorization,
            pendingCleaner: cleaner,
            retry: {}
        )

        await actions.setEnabled(false)

        #expect(!actions.isEnabled)
        #expect(await preference.enabled == false)
        #expect(actions.actionError == .pendingCleanup)
        #expect(actions.didRequestRetry == false)
    }
}

@Suite("Recovery privacy boundaries")
struct RecoveryPrivacyBoundaryTests {
    @Test func rootCleanupRemovesOnlyPendingAppInventoryAndNeverReadsDelivered() async throws {
        let appOwned = NotificationIdentifierCodec.root + "future.namespace"
        let unrelated = "another-app.request"
        let center = RecoveryNotificationCenterSpy(pending: [
            NotificationInventoryItem(identifier: appOwned),
            NotificationInventoryItem(identifier: unrelated)
        ])
        let cleanup = NotificationCleanupService(notificationCenter: center)

        try await cleanup.removeAllPendingAppNotificationsReportingFailure()

        #expect(await center.pendingRemovals == [[appOwned]])
        #expect(await center.deliveredInventoryReadCount == 0)
        #expect(await center.deliveredRemovals.isEmpty)
    }

    @Test func aboutPrivacyDisclosuresKeepEachNormativeLimitationExplicit() {
        #expect(Set(AboutPrivacyDisclosure.allCases) == [
            .automaticICloudSync,
            .syncCompletionNotGuaranteed,
            .accountBehaviorNotGuaranteed,
            .notificationStorageManagedByOS,
            .notificationPreviewsControlledByOS,
            .staleSyncedContentMayAppear,
            .notificationRemovalIsNonAtomic,
            .deliveredNotificationRetention,
            .delayedOperationsAfterTermination,
            .staleRepeatingRequestsUntilReconcile,
            .noServerAnalyticsOrAdvertising,
            .foundationModelsRunOnDevice
        ])
    }

    @Test func neutralUnavailableContentExposesOnlySemanticRecoveryCopy() {
        #expect(NotificationUnavailableContent.titleKey == "notification_unavailable.title")
        #expect(
            NotificationUnavailableContent.messageKey
                == "notification_unavailable.message"
        )
    }
}

@Suite("Tag management and picker")
struct TagManagementPresentationTests {
    @MainActor
    @Test func createUsesTask11NormalizationAndSurfacesRepositoryDuplicateWithoutLosingTags() async throws {
        let (model, _) = try makeTagModel()
        await model.load()

        let created = await model.create(name: "  ＷＯＲＫ  ")
        let duplicate = await model.create(name: "work")

        #expect(created?.name == "  ＷＯＲＫ  ")
        #expect(created?.normalizedName == "work")
        #expect(duplicate == nil)
        #expect(model.actionError == .duplicateName)
        #expect(model.tags.map(\.id) == [created?.id].compactMap { $0 })
    }

    @MainActor
    @Test func whitespaceOnlyCreateSurfacesStableEmptyIdentityWithoutPersistence() async throws {
        let (model, repository) = try makeTagModel()

        let created = await model.create(name: "\u{2003}\u{00A0}")

        #expect(created == nil)
        #expect(model.actionError == .emptyName)
        #expect(try await repository.fetchCompleteSnapshot().tags.isEmpty)
    }

    @MainActor
    @Test func renameAndDeleteUseTask11IdentityPreservingMutations() async throws {
        let (model, _) = try makeTagModel()
        let created = try #require(await model.create(name: "Travel"))

        let renamed = await model.rename(tagID: created.id, name: "Trips")
        let deleted = await model.delete(tagID: created.id)

        #expect(renamed?.id == created.id)
        #expect(renamed?.name == "Trips")
        #expect(deleted)
        #expect(model.tags.isEmpty)
        #expect(model.actionError == nil)
    }

    @MainActor
    @Test func missingRenameMapsToStableNotFoundIdentity() async throws {
        let (model, _) = try makeTagModel()
        let missing = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!

        let renamed = await model.rename(tagID: missing, name: "Missing")

        #expect(renamed == nil)
        #expect(model.actionError == .notFound)
        #expect(model.tags.isEmpty)
    }

    @Test func pickerPrunesUnavailableIDsAndSelectsTheNewlyCreatedTag() {
        let existing = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let removed = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let created = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!

        let pruned = TagPickerSelection.reconciled(
            selectedIDs: [existing, removed],
            availableIDs: [existing]
        )
        let selected = TagPickerSelection.selecting(created, in: pruned)

        #expect(pruned == [existing])
        #expect(selected == [existing, created])
    }

    @MainActor
    private func makeTagModel() throws -> (
        TagManagementModel,
        SwiftDataReminderRepository
    ) {
        let repository = try SwiftDataReminderRepository.inMemory()
        let useCase = TagManagementUseCase(
            repository: repository,
            normalizer: TagNameNormalizerV1(),
            now: { Date(timeIntervalSince1970: 1_786_003_200) }
        )
        return (
            TagManagementModel(repository: repository, useCase: useCase),
            repository
        )
    }
}

@Suite("Locale-aware source time presentation")
struct SourceTimePresentationTests {
    private let source = SourceWallClock(
        year: 2026,
        month: 8,
        day: 6,
        hour: 9,
        minute: 30,
        timeZoneIdentifier: "America/New_York"
    )

    @Test func savedWallClockUsesExplicitLocaleAndBidiIsolatesTheIANAIdentifier() {
        let formatter = SourceDateTimePresentationFormatter(
            localizer: LocalizedTextProvider { key, _ in
                #expect(key == "reminder.source-wall-clock.presentation")
                return "%1$@ · %2$@"
            }
        )

        #expect(
            formatter.wallClock(source, locale: Locale(identifier: "en_US"))
                == "8/6/2026, 9:30\u{202F}AM · \u{2066}America/New_York\u{2069}"
        )
        #expect(
            formatter.wallClock(source, locale: Locale(identifier: "ja_JP"))
                == "2026/8/6 9:30 · \u{2066}America/New_York\u{2069}"
        )
        #expect(
            formatter.wallClock(source, locale: Locale(identifier: "ar"))
                == "6\u{200F}/8\u{200F}/2026، 9:30\u{00A0}ص · \u{2066}America/New_York\u{2069}"
        )
    }

    @Test func sourceInstantUsesTheSameLocaleAndRTLContract() throws {
        let formatter = SourceDateTimePresentationFormatter(
            localizer: LocalizedTextProvider { key, _ in
                #expect(key == "reminder.source-instant.presentation")
                return "%1$@ · %2$@"
            }
        )
        let instant = try #require(
            ISO8601DateFormatter().date(from: "2026-08-06T13:30:00Z")
        )

        #expect(
            formatter.instant(
                instant,
                timeZoneIdentifier: source.timeZoneIdentifier,
                locale: Locale(identifier: "en_US")
            ) == "8/6/2026, 9:30\u{202F}AM · \u{2066}America/New_York\u{2069}"
        )
    }
}

@Suite("Localized notification reason presentation")
struct LocalizedNotificationReasonPresentationTests {
    @Test func emptyRepeatingContributorsProduceNoReasonWithoutLocalizationLookup() {
        let formatter = LocalizedReasonFormatter(
            localizer: LocalizedTextProvider { key, _ in
                Issue.record("Unexpected localization lookup for \(key)")
                return key
            }
        )
        let components = RepeatingTriggerComponents(
            timeZoneIdentifier: "America/New_York",
            hour: 9,
            minute: 30,
            second: 0
        )

        #expect(
            formatter.reasons(
                for: .repeating(components: components, contributors: []),
                sourceTimeZoneIdentifier: "America/New_York",
                locale: Locale(identifier: "en_US")
            ).isEmpty
        )
    }

    @Test func catalogTemplatesAndFoundationLocaleDataDriveRepeatAndReasonText() throws {
        let localizer = LocalizedTextProvider { key, locale in
            let japanese = locale.language.languageCode == .japanese
            switch key {
            case "localization.repeat.weekly.one":
                return japanese ? "毎週%@に繰り返します。" : "Every %@."
            case "localization.source-time.sentence":
                return japanese ? "基準時刻：%1$@（%2$@）。" : "Source time: %1$@ (%2$@)."
            case "localization.reason.one-shot.main.primary":
                return japanese ? "%@の予定時刻です。" : "At the scheduled time for %@."
            default:
                Issue.record("Unexpected localization lookup for \(key)")
                return key
            }
        }
        let source = SourceWallClock(
            year: 2040,
            month: 8,
            day: 31,
            hour: 9,
            minute: 30,
            timeZoneIdentifier: "America/New_York"
        )
        let schedule = ScheduleDefinition(
            source: source,
            rule: .weekly(
                interval: 1,
                weekdaySetKind: .explicit,
                weekdays: [.monday, .wednesday, .friday]
            ),
            end: .never,
            early: nil
        )
        let repeatFormatter = LocalizedRepeatFormatter(localizer: localizer)
        let instant = try #require(
            ISO8601DateFormatter().date(from: "2040-08-31T13:30:00Z")
        )
        let reason = EffectiveAlert(
            kind: .main,
            baseOccurrence: BaseOccurrence(
                instant: instant,
                sourceComponents: DateComponents()
            ),
            alertInstant: instant
        )
        let reasonFormatter = LocalizedReasonFormatter(localizer: localizer)

        #expect(
            repeatFormatter.summary(for: schedule, locale: Locale(identifier: "en_US"))
                == "Every Monday, Wednesday, and Friday."
        )
        #expect(
            repeatFormatter.summary(for: schedule, locale: Locale(identifier: "ja_JP"))
                == "毎週月曜日、水曜日、金曜日に繰り返します。"
        )
        #expect(
            repeatFormatter.sourceTime(for: source, locale: Locale(identifier: "en_US"))
                == "Source time: 9:30\u{202F}AM (\u{2066}America/New_York\u{2069})."
        )
        #expect(
            repeatFormatter.sourceTime(for: source, locale: Locale(identifier: "ja_JP"))
                == "基準時刻：9:30（\u{2066}America/New_York\u{2069}）。"
        )
        #expect(
            reasonFormatter.reasons(
                for: .oneShot(alertInstant: instant, reasons: [reason]),
                sourceTimeZoneIdentifier: source.timeZoneIdentifier,
                locale: Locale(identifier: "en_US")
            ) == "At the scheduled time for August 31, 2040 at 9:30\u{202F}AM."
        )
    }
}

@Suite("Accessibility error announcement identity")
struct AccessibilityErrorAnnouncementTests {
    @Test func newlySurfacedErrorIsSelectedByStableSemanticIdentity() {
        let resolver = AccessibilityErrorAnnouncementResolver()

        let identity = resolver.newIdentity(
            previous: [.reminderTitleRequired],
            current: [.reminderTitleRequired, .reminderURLInvalid]
        )

        #expect(identity == .reminderURLInvalid)
    }

    @Test func unchangedErrorsAreDeduplicatedWithoutLocalizedTextComparison() {
        let resolver = AccessibilityErrorAnnouncementResolver()

        #expect(
            resolver.newIdentity(
                previous: [.settingsPendingCleanup],
                current: [.settingsPendingCleanup]
            ) == nil
        )
        #expect(
            resolver.newIdentity(
                previous: [],
                current: [.settingsPendingCleanup]
            ) == .settingsPendingCleanup
        )
    }
}

private enum SettingsTraceEvent: Sendable, Equatable {
    case preferenceSet(Bool)
    case authorizationRead(Int)
    case authorizationRequested
    case pendingCleanup
    case reconcileRequested
}

private actor SettingsTrace {
    private(set) var events: [SettingsTraceEvent] = []

    func record(_ event: SettingsTraceEvent) {
        events.append(event)
    }
}

private actor RecordingPreferenceStore: DeviceNotificationPreferenceStore {
    private(set) var enabled: Bool
    private let trace: SettingsTrace?

    init(enabled: Bool, trace: SettingsTrace? = nil) {
        self.enabled = enabled
        self.trace = trace
    }

    func isEnabled() -> Bool { enabled }

    func setEnabled(_ enabled: Bool) async {
        self.enabled = enabled
        await trace?.record(.preferenceSet(enabled))
    }
}

private actor RecordingAuthorizationController:
    NotificationAuthorizationProviding,
    NotificationAuthorizationRequesting
{
    private var snapshots: [NotificationAuthorizationSnapshot]
    private let requestError: (any Error)?
    private let trace: SettingsTrace?
    private(set) var requestCount = 0

    init(
        snapshots: [NotificationAuthorizationSnapshot],
        requestError: (any Error)? = nil,
        trace: SettingsTrace? = nil
    ) {
        self.snapshots = snapshots
        self.requestError = requestError
        self.trace = trace
    }

    func currentAuthorization() async -> NotificationAuthorizationSnapshot {
        let snapshot = snapshots.count > 1 ? snapshots.removeFirst() : snapshots[0]
        await trace?.record(.authorizationRead(snapshot.rawValue))
        return snapshot
    }

    func requestAuthorization() async throws -> Bool {
        requestCount += 1
        await trace?.record(.authorizationRequested)
        if let requestError { throw requestError }
        return false
    }
}

private enum AuthorizationTestError: Error {
    case requestFailed
}

private enum PendingCleanerTestError: Error {
    case inventoryUnavailable
}

private actor RecordingPendingCleaner: PendingAppNotificationCleaning {
    private let error: (any Error)?
    private let trace: SettingsTrace?
    private(set) var callCount = 0

    init(error: (any Error)? = nil, trace: SettingsTrace? = nil) {
        self.error = error
        self.trace = trace
    }

    func removeAllPendingAppNotificationsReportingFailure() async throws {
        callCount += 1
        await trace?.record(.pendingCleanup)
        if let error { throw error }
    }
}

private actor RecordingReconciler: ReconcileRequesting {
    private let trace: SettingsTrace?
    private(set) var reasons: [ReconcileReason] = []

    init(trace: SettingsTrace? = nil) {
        self.trace = trace
    }

    func requestReconcile(_ reason: ReconcileReason) async {
        reasons.append(reason)
        await trace?.record(.reconcileRequested)
    }
}

private actor RecoveryNotificationCenterSpy: NotificationCenterClient {
    private let pending: [NotificationInventoryItem]
    private(set) var pendingRemovals: [[String]] = []
    private(set) var deliveredInventoryReadCount = 0
    private(set) var deliveredRemovals: [[String]] = []

    init(pending: [NotificationInventoryItem]) {
        self.pending = pending
    }

    func pendingNotificationInventory() async throws -> [NotificationInventoryItem] {
        pending
    }

    func deliveredNotificationInventory() async -> [NotificationInventoryItem] {
        deliveredInventoryReadCount += 1
        return []
    }

    nonisolated func add(_ request: UNNotificationRequest) async throws {}

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        pendingRemovals.append(identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {
        deliveredRemovals.append(identifiers)
    }
}

private extension NotificationAuthorizationSnapshot {
    static func fixture(rawValue: Int) -> NotificationAuthorizationSnapshot {
        NotificationAuthorizationService.map(rawValue: rawValue)
    }
}
