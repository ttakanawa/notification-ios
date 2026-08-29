import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
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
        #expect(
            await trace.events == [
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
        #expect(
            await trace.events == [
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
        #expect(actions.isRetrying == false)
    }

    @MainActor
    @Test func dataUnavailableRetryRejectsOnlyConcurrentAttempts() async {
        let retry = BlockingRetryAction()
        let actions = DataUnavailableActions(
            preferenceStore: RecordingPreferenceStore(enabled: false),
            authorizationProvider: RecordingAuthorizationController(
                snapshots: [.fixture(rawValue: 0)]
            ),
            authorizationRequester: RecordingAuthorizationController(
                snapshots: [.fixture(rawValue: 0)]
            ),
            pendingCleaner: RecordingPendingCleaner(),
            retry: { await retry.run() }
        )

        let firstAttempt = Task { @MainActor in await actions.retry() }
        await retry.waitUntilStarted()

        #expect(actions.isRetrying)
        await actions.retry()
        #expect(await retry.callCount == 1)

        await retry.release()
        await firstAttempt.value
        #expect(!actions.isRetrying)
    }

    @MainActor
    @Test func dataUnavailableRetryIsAvailableAgainAfterCompletion() async {
        let counter = RetryCounter()
        let actions = DataUnavailableActions(
            preferenceStore: RecordingPreferenceStore(enabled: false),
            authorizationProvider: RecordingAuthorizationController(
                snapshots: [.fixture(rawValue: 0)]
            ),
            authorizationRequester: RecordingAuthorizationController(
                snapshots: [.fixture(rawValue: 0)]
            ),
            pendingCleaner: RecordingPendingCleaner(),
            retry: { await counter.increment() }
        )

        await actions.retry()
        await actions.retry()

        #expect(await counter.value == 2)
        #expect(!actions.isRetrying)
    }

    @Test func dynamicRecoveryAndPrivacyContentExposeLocalizedResources() {
        let recoveryTitle: LocalizedStringResource = NotificationUnavailableContent.title
        let disclosure: LocalizedStringResource =
            AboutPrivacyDisclosure.automaticICloudSync.localizedResource

        #expect(String(localized: recoveryTitle).isEmpty == false)
        #expect(String(localized: disclosure).isEmpty == false)
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
        #expect(
            Set(AboutPrivacyDisclosure.allCases) == [
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

}

@Suite("Tag management and picker")
struct TagManagementPresentationTests {
    @MainActor
    @Test func createTrimsDisplayNameAndPreservesTagsForCaseVariants() async throws {
        let (model, _) = makeTagModel()
        await model.load()

        let created = try #require(await model.create(name: "  ＷＯＲＫ  "))
        let caseVariant = try #require(await model.create(name: "work"))

        #expect(created.name == "ＷＯＲＫ")
        #expect(created.normalizedName == "work")
        #expect(caseVariant.name == "work")
        #expect(caseVariant.normalizedName == "work")
        #expect(model.actionError == nil)
        #expect(model.tags.count == 2)
        #expect(Set(model.tags.map(\.id)) == Set([created.id, caseVariant.id]))
    }

    @MainActor
    @Test func whitespaceOnlyCreateSurfacesStableEmptyIdentityWithoutPersistence() async throws {
        let (model, repository) = makeTagModel()

        let created = await model.create(name: "\u{2003}\u{00A0}")

        #expect(created == nil)
        #expect(model.actionError == .emptyName)
        #expect(await repository.fetchCompleteSnapshot().tags.isEmpty)
    }

    @MainActor
    @Test func renameAndDeleteUseTask11IdentityPreservingMutations() async throws {
        let (model, _) = makeTagModel()
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
    @Test func removingAnOrphanedAssociationDeletesTheTagPresentationImmediately() async throws {
        let repository = TagPresentationRepository()
        let refresh = TagAssociationRefreshRecorder()
        let model = TagManagementModel(
            repository: repository,
            useCase: TagManagementUseCase(
                repository: repository,
                normalizer: TagNameNormalizerV1()
            ),
            associationRemovalCommitted: {
                await refresh.record()
            }
        )
        let created = try #require(await model.create(name: "Travel"))

        let outcome = await model.removeAssociation(
            tagID: created.id,
            from: nil
        )

        #expect(outcome == .tagDeleted)
        #expect(model.tags.isEmpty)
        #expect(model.actionError == nil)
        #expect(await refresh.callCount == 1)
    }

    @MainActor
    @Test func removingASharedAssociationKeepsTheTagAvailableForAddingAgain() async throws {
        let tag = tagFixture(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            name: "Travel"
        )
        let repository = TagPresentationRepository(
            tags: [tag],
            associationRemovalOutcome: .tagRetained
        )
        let model = makeTagModel(repository: repository, initialTags: [tag])

        let outcome = await model.removeAssociation(
            tagID: tag.id,
            from: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        )

        #expect(outcome == .tagRetained)
        #expect(model.tags == [tag])
        #expect(model.actionError == nil)
    }

    @MainActor
    @Test func missingRenameMapsToStableNotFoundIdentity() async throws {
        let (model, _) = makeTagModel()
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

    @Test func pickerSuggestionsRankMatchesAndOfferCreationOnlyWithoutAnExactDisplayName() {
        let workUpper = tagFixture(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            name: "Work"
        )
        let homework = tagFixture(
            id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            name: "Homework"
        )
        let afterWork = tagFixture(
            id: "cccccccc-cccc-cccc-cccc-cccccccccccc",
            name: "AfterWork"
        )
        let travel = tagFixture(
            id: "dddddddd-dddd-dddd-dddd-dddddddddddd",
            name: "Travel"
        )

        let state = TagPickerSuggestionState(
            tags: [travel, afterWork, homework, workUpper],
            query: "  work  "
        )

        #expect(state.matches.map(\.name) == ["Work", "AfterWork", "Homework"])
        #expect(state.trimmedQuery == "work")
        #expect(state.creationName == "work")
        #expect(state.exactMatch == nil)
    }

    @Test func pickerSuggestionsUseCaseSensitiveExactDisplayNameToSuppressCreation() {
        let workUpper = tagFixture(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            name: "Work"
        )
        let workLower = tagFixture(
            id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            name: "work"
        )

        let exact = TagPickerSuggestionState(tags: [workUpper, workLower], query: "work")

        #expect(exact.matches.map(\.name) == ["Work", "work"])
        #expect(exact.exactMatch?.id == workLower.id)
        #expect(exact.creationName == nil)
    }

    @Test func pickerSuggestionsLeaveEmptyQueriesUnfilteredWithoutCreation() {
        let work = tagFixture(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            name: "Work"
        )
        let travel = tagFixture(
            id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            name: "Travel"
        )

        let empty = TagPickerSuggestionState(tags: [travel, work], query: "")
        let whitespace = TagPickerSuggestionState(tags: [travel, work], query: " \u{2003}\u{00A0} ")

        #expect(empty.matches.map(\.id) == [travel.id, work.id])
        #expect(empty.trimmedQuery.isEmpty)
        #expect(empty.creationName == nil)
        #expect(empty.exactMatch == nil)
        #expect(whitespace.matches.map(\.id) == [travel.id, work.id])
        #expect(whitespace.trimmedQuery.isEmpty)
        #expect(whitespace.creationName == nil)
        #expect(whitespace.exactMatch == nil)
    }

    @Test func pickerSuggestionsIncludeMiddleAndSuffixMatches() {
        let homework = tagFixture(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            name: "Homework"
        )
        let afterWork = tagFixture(
            id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            name: "AfterWork"
        )
        let travel = tagFixture(
            id: "cccccccc-cccc-cccc-cccc-cccccccccccc",
            name: "Travel"
        )

        let middle = TagPickerSuggestionState(tags: [travel, afterWork, homework], query: "ter")
        let suffix = TagPickerSuggestionState(tags: [travel, afterWork, homework], query: "vel")

        #expect(middle.matches.map(\.name) == ["AfterWork"])
        #expect(suffix.matches.map(\.name) == ["Travel"])
    }

    @Test func pickerSuggestionsBreakEqualMatchesByNormalizedNameDisplayNameThenUUID() {
        let nameLater = tagFixture(
            id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            name: "Work"
        )
        let nameEarlier = tagFixture(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            name: "Work"
        )
        let lowercase = tagFixture(
            id: "cccccccc-cccc-cccc-cccc-cccccccccccc",
            name: "work"
        )

        let state = TagPickerSuggestionState(
            tags: [nameLater, lowercase, nameEarlier],
            query: "work"
        )

        #expect(state.matches.map(\.id) == [nameEarlier.id, nameLater.id, lowercase.id])
    }

    @MainActor
    @Test func pickerDelayedCreatePreservesNewerQuery() async {
        let createdID = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!
        let creation = DelayedTagCreation(createdID: createdID)
        let state = TagPickerCreateTestState(query: "  work  ")
        let submission = TagPickerCreateSubmission(
            name: "work",
            rawQuery: state.query
        )

        let createTask = Task { @MainActor in
            let tagID = await creation.create()
            let completion = submission.completion(
                createdTagID: tagID,
                currentQuery: state.query,
                selectedTagIDs: state.selectedTagIDs
            )
            state.query = completion.query
            state.selectedTagIDs = completion.selectedTagIDs
        }

        await creation.waitUntilStarted()
        state.query = "travel"
        await creation.release()
        await createTask.value

        #expect(state.query == "travel")
        #expect(state.selectedTagIDs == [createdID])
    }

    @MainActor
    @Test func failedCompleteSnapshotLoadPreservesDraftTagIDs() async {
        let existing = tagFixture(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            name: "Existing"
        )
        let draftID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let repository = ControlledTagSnapshotRepository(
            snapshot: CompleteReminderSnapshot(reminders: [], tags: [existing]),
            behavior: .fail
        )
        let model = makeTagModel(repository: repository, initialTags: [existing])

        let outcome = await model.load()
        let selection = TagPickerSelection.reconciled(
            selectedIDs: [existing.id, draftID],
            availableIDs: Set(model.tags.map(\.id)),
            after: outcome
        )

        #expect(outcome == .notAccepted)
        #expect(selection == [existing.id, draftID])
    }

    @MainActor
    @Test func busyLoadPreservesDraftIDsUntilAcceptedCompleteSnapshotPrunesThem() async {
        let existing = tagFixture(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            name: "Existing"
        )
        let draftID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let repository = ControlledTagSnapshotRepository(
            snapshot: CompleteReminderSnapshot(reminders: [], tags: [existing]),
            behavior: .blockFirst
        )
        let model = makeTagModel(repository: repository, initialTags: [existing])
        let initialSelection: Set<UUID> = [existing.id, draftID]

        let acceptedLoad = Task { @MainActor in await model.load() }
        await repository.waitUntilFirstFetchStarts()
        let droppedLoad = await model.load()
        let whileBusy = TagPickerSelection.reconciled(
            selectedIDs: initialSelection,
            availableIDs: Set(model.tags.map(\.id)),
            after: droppedLoad
        )

        #expect(droppedLoad == .notAccepted)
        #expect(whileBusy == initialSelection)

        await repository.releaseFirstFetch()
        let acceptedOutcome = await acceptedLoad.value
        let afterAcceptedLoad = TagPickerSelection.reconciled(
            selectedIDs: whileBusy,
            availableIDs: Set(model.tags.map(\.id)),
            after: acceptedOutcome
        )

        #expect(acceptedOutcome == .acceptedCompleteSnapshot(generation: 1))
        #expect(afterAcceptedLoad == [existing.id])
    }

    @MainActor
    private func makeTagModel() -> (
        TagManagementModel,
        TagPresentationRepository
    ) {
        let repository = TagPresentationRepository()
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

    @MainActor
    private func makeTagModel(
        repository: any ReminderRepository,
        initialTags: [TagSnapshot]
    ) -> TagManagementModel {
        TagManagementModel(
            repository: repository,
            useCase: TagManagementUseCase(
                repository: repository,
                normalizer: TagNameNormalizerV1(),
                now: { Date(timeIntervalSince1970: 1_786_003_200) }
            ),
            initialTags: initialTags
        )
    }

    private func tagFixture(id: String, name: String) -> TagSnapshot {
        let timestamp = Date(timeIntervalSince1970: 1_786_003_200)
        guard let tagID = UUID(uuidString: id) else {
            preconditionFailure("Invalid tag UUID fixture: \(id)")
        }
        return TagSnapshot(
            id: tagID,
            name: name,
            normalizedName: name.lowercased(),
            createdAt: timestamp,
            updatedAt: timestamp
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
            localizer: LocalizedTextProvider { key, locale in
                #expect(key == "reminder.source-wall-clock.presentation")
                #expect(["en_US", "ja_JP", "ar"].contains(locale.identifier))
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

    @Test func dstGapWallClockKeepsNominalCivilComponentsAcrossLocales() throws {
        let formatter = SourceDateTimePresentationFormatter(
            localizer: LocalizedTextProvider { key, _ in
                #expect(
                    [
                        "reminder.source-wall-clock.presentation",
                        "reminder.source-instant.presentation"
                    ].contains(key))
                return "%1$@ · %2$@"
            }
        )
        let gap = SourceWallClock(
            year: 2026,
            month: 3,
            day: 8,
            hour: 2,
            minute: 30,
            timeZoneIdentifier: "America/New_York"
        )

        #expect(
            formatter.wallClock(gap, locale: Locale(identifier: "en_US"))
                == "3/8/2026, 2:30\u{202F}AM · \u{2066}America/New_York\u{2069}"
        )
        #expect(
            formatter.wallClock(gap, locale: Locale(identifier: "ja_JP"))
                == "2026/3/8 2:30 · \u{2066}America/New_York\u{2069}"
        )

        let resolvedInstant = try SourceWallClockResolver().resolve(
            gap,
            environment: FoundationRecurrenceEnvironment()
        )
        #expect(
            formatter.instant(
                resolvedInstant,
                timeZoneIdentifier: gap.timeZoneIdentifier,
                locale: Locale(identifier: "en_US")
            ) == "3/8/2026, 3:30\u{202F}AM · \u{2066}America/New_York\u{2069}"
        )
    }
}

@Suite("Localized notification reason presentation")
struct NotificationReasonPresentationTests {
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

    @Test func notificationSourceSentenceKeepsSavedDSTGapTime() {
        let formatter = LocalizedRepeatFormatter(
            localizer: LocalizedTextProvider { key, locale in
                #expect(key == "localization.source-time.sentence")
                return locale.language.languageCode == .japanese
                    ? "基準時刻：%1$@（%2$@）。"
                    : "Source time: %1$@ (%2$@)."
            }
        )
        let gap = SourceWallClock(
            year: 2026,
            month: 3,
            day: 8,
            hour: 2,
            minute: 30,
            timeZoneIdentifier: "America/New_York"
        )

        #expect(
            formatter.sourceTime(for: gap, locale: Locale(identifier: "en_US"))
                == "Source time: 2:30\u{202F}AM (\u{2066}America/New_York\u{2069})."
        )
        #expect(
            formatter.sourceTime(for: gap, locale: Locale(identifier: "ja_JP"))
                == "基準時刻：2:30（\u{2066}America/New_York\u{2069}）。"
        )
    }
}

@Suite("Accessibility error announcement identity")
struct AccessibilityErrorAnnouncementTests {
    @Test func identitiesKeepRawIdentityWhileExposingOwnedLocalizationTable() {
        let fixtures:
            [(
                identity: AccessibilityErrorIdentity,
                rawValue: String,
                table: LocalizationTable
            )] = [
                (
                    .reminderTitleRequired,
                    "reminder.form.error.title-required",
                    .reminderForm
                ),
                (
                    .reminderEnabledChangeFailed,
                    "reminder.action.enabled-change-failed",
                    .reminder
                ),
                (
                    .settingsPendingCleanup,
                    "settings.error.pending-cleanup",
                    .settings
                ),
                (
                    .settingsAppIconChangeFailed,
                    "settings.error.app-icon-change-failed",
                    .settings
                ),
                (
                    .tagDuplicateName,
                    "tags.error.duplicate-name",
                    .tags
                ),
                (
                    .dataUnavailable,
                    "recovery.error.data-unavailable",
                    .recovery
                )
            ]

        for fixture in fixtures {
            #expect(fixture.identity.rawValue == fixture.rawValue)
            #expect(fixture.identity.localizationTable == fixture.table)
        }
    }

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

private actor RetryCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private actor BlockingRetryAction {
    private(set) var callCount = 0
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func run() async {
        callCount += 1
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
private final class TagPickerCreateTestState {
    var query: String
    var selectedTagIDs: Set<UUID> = []

    init(query: String) {
        self.query = query
    }
}

private actor DelayedTagCreation {
    private let createdID: UUID
    private var isStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(createdID: UUID) {
        self.createdID = createdID
    }

    func create() async -> UUID {
        isStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        return createdID
    }

    func waitUntilStarted() async {
        guard !isStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private enum ControlledTagSnapshotRepositoryError: Error {
    case fetchFailed
    case unsupportedMutation
}

private enum TagPresentationRepositoryError: Error {
    case unsupportedReminderMutation
}

private actor TagAssociationRefreshRecorder {
    private(set) var callCount = 0

    func record() {
        callCount += 1
    }
}

private actor TagPresentationRepository: ReminderRepository {
    private var tags: [UUID: TagSnapshot]
    private let associationRemovalOutcome: TagAssociationRemovalOutcome

    init(
        tags: [TagSnapshot] = [],
        associationRemovalOutcome: TagAssociationRemovalOutcome = .tagDeleted
    ) {
        self.tags = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        self.associationRemovalOutcome = associationRemovalOutcome
    }

    func fetchCompleteSnapshot() -> CompleteReminderSnapshot {
        CompleteReminderSnapshot(
            reminders: [],
            tags: tags.values.sorted {
                if $0.normalizedName != $1.normalizedName {
                    return $0.normalizedName < $1.normalizedName
                }
                return $0.id.uuidString < $1.id.uuidString
            }
        )
    }

    func reminder(id: UUID) -> ReminderSnapshot? { nil }

    func save(_ mutation: EncodedReminderMutation) throws -> ReminderSnapshot {
        throw TagPresentationRepositoryError.unsupportedReminderMutation
    }

    func delete(id: UUID) throws {
        throw TagPresentationRepositoryError.unsupportedReminderMutation
    }

    func saveTag(_ mutation: EncodedTagMutation) throws -> TagSnapshot {
        switch mutation.command {
        case .create:
            guard tags[mutation.id] == nil else {
                throw TagRepositoryError.duplicateID(mutation.id)
            }
        case .update:
            guard tags[mutation.id] != nil else {
                throw TagRepositoryError.notFound(mutation.id)
            }
        }
        guard
            !tags.values.contains(where: {
                $0.id != mutation.id
                    && TagNameNormalizerV1.trimmedDisplayName($0.name)
                        == TagNameNormalizerV1.trimmedDisplayName(mutation.name)
            })
        else {
            throw TagRepositoryError.duplicateName(
                TagNameNormalizerV1.trimmedDisplayName(mutation.name))
        }
        let tag = TagSnapshot(
            id: mutation.id,
            name: mutation.name,
            normalizedName: mutation.normalizedName,
            normalizationVersion: mutation.normalizationVersion,
            createdAt: mutation.createdAt,
            updatedAt: mutation.updatedAt
        )
        tags[tag.id] = tag
        return tag
    }

    func deleteTag(id: UUID) throws {
        guard tags[id] != nil else { throw TagRepositoryError.notFound(id) }
        tags[id] = nil
    }

    func removeTagAssociation(
        tagID: UUID,
        from reminderID: UUID?
    ) throws -> TagAssociationRemovalOutcome {
        guard tags[tagID] != nil else { throw TagRepositoryError.notFound(tagID) }
        if associationRemovalOutcome == .tagDeleted {
            tags[tagID] = nil
        }
        return associationRemovalOutcome
    }
}

private actor ControlledTagSnapshotRepository: ReminderRepository {
    enum Behavior: Sendable {
        case succeed
        case fail
        case blockFirst
    }

    private let snapshot: CompleteReminderSnapshot
    private let behavior: Behavior
    private var fetchCount = 0
    private var firstFetchStarted = false
    private var firstFetchStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstFetchRelease: CheckedContinuation<Void, Never>?

    init(snapshot: CompleteReminderSnapshot, behavior: Behavior) {
        self.snapshot = snapshot
        self.behavior = behavior
    }

    func fetchCompleteSnapshot() async throws -> CompleteReminderSnapshot {
        fetchCount += 1
        switch behavior {
        case .succeed:
            return snapshot
        case .fail:
            throw ControlledTagSnapshotRepositoryError.fetchFailed
        case .blockFirst:
            guard fetchCount == 1 else { return snapshot }
            firstFetchStarted = true
            let waiters = firstFetchStartWaiters
            firstFetchStartWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
            await withCheckedContinuation { continuation in
                firstFetchRelease = continuation
            }
            return snapshot
        }
    }

    func waitUntilFirstFetchStarts() async {
        guard !firstFetchStarted else { return }
        await withCheckedContinuation { continuation in
            firstFetchStartWaiters.append(continuation)
        }
    }

    func releaseFirstFetch() {
        firstFetchRelease?.resume()
        firstFetchRelease = nil
    }

    func reminder(id: UUID) async throws -> ReminderSnapshot? {
        throw ControlledTagSnapshotRepositoryError.unsupportedMutation
    }

    func save(_ mutation: EncodedReminderMutation) async throws -> ReminderSnapshot {
        throw ControlledTagSnapshotRepositoryError.unsupportedMutation
    }

    func delete(id: UUID) async throws {
        throw ControlledTagSnapshotRepositoryError.unsupportedMutation
    }

    func saveTag(_ mutation: EncodedTagMutation) async throws -> TagSnapshot {
        throw ControlledTagSnapshotRepositoryError.unsupportedMutation
    }

    func deleteTag(id: UUID) async throws {
        throw ControlledTagSnapshotRepositoryError.unsupportedMutation
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

extension NotificationAuthorizationSnapshot {
    fileprivate static func fixture(rawValue: Int) -> NotificationAuthorizationSnapshot {
        NotificationAuthorizationService.map(rawValue: rawValue)
    }
}
