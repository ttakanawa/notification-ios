import Foundation
import NotificationManagerDomain
import Testing

@testable import NotificationManagerApplication

@Suite("CustomRepeatInputResolver")
struct CustomRepeatInputResolverTests {
    @Test func confirmingCustomRepeatPreservesConfiguredRangeDuration() async throws {
        let assisted = AssistedRepeatInterpreterSpy(availability: .available, candidate: .daily)
        let resolver = CustomRepeatInputResolver(
            source: Self.source,
            end: .never,
            early: nil,
            durationSeconds: 3_600,
            assistedInterpreter: assisted
        )
        let session = CustomRepeatSession(
            resolver: resolver,
            reminderID: UUID(),
            now: { Self.previewNow },
            recurrenceEnvironment: FoundationRecurrenceEnvironment()
        )
        _ = try await session.submit("Every day")
        let confirmed = try #require(await session.confirm())

        #expect(confirmed.rule == .daily(interval: 1))
        #expect(confirmed.durationSeconds == 3_600)
    }

    @Test func deterministicEnglishSuccessBypassesAssistedAvailabilityAndInterpretation() async {
        let assisted = AssistedRepeatInterpreterSpy(
            availability: .unavailable(.deviceNotEligible),
            candidate: .daily
        )
        let resolution = await makeResolver(assisted: assisted).resolve("Every 2 weeks")

        guard case .resolved(let value) = resolution else {
            Issue.record("Expected deterministic English resolution, got \(resolution)")
            return
        }
        #expect(value.route == .deterministicEnglish)
        #expect(
            value.rule
                == .weekly(
                    interval: 2,
                    weekdaySetKind: .explicit,
                    weekdays: [.friday]
                ))
        #expect(await assisted.events.isEmpty)
    }

    @Test func deterministicEnglishSuggestionWaitsForExplicitSelection() async throws {
        let assisted = AssistedRepeatInterpreterSpy(
            availability: .available,
            candidate: .daily
        )
        let resolver = makeResolver(assisted: assisted)

        let resolution = await resolver.resolve("Every Tuseday")

        #expect(resolution == .suggested(["Every Tuesday"]))
        #expect(await assisted.events.isEmpty)

        let session = CustomRepeatSession(
            resolver: resolver,
            reminderID: UUID(uuidString: "13131313-1313-1313-1313-131313131313")!,
            now: { Self.previewNow },
            recurrenceEnvironment: FoundationRecurrenceEnvironment()
        )

        let outcome = try await session.submit("Every Tuseday")

        #expect(outcome == .applied(.awaitingSuggestions(["Every Tuesday"])))
        #expect(await session.confirm() == nil)
    }

    @Test func candidatesStopAutomaticResolutionBeforeAI() async {
        let assisted = AssistedRepeatInterpreterSpy(availability: .available, candidate: .daily)
        let resolution = await makeResolver(assisted: assisted)
            .resolve("Every mont", mode: .automatic)
        #expect(resolution == .suggested(["Every Monday", "Every month"]))
        #expect(await assisted.events.isEmpty)
    }

    @Test func structuralShorthandCandidatesStopAutomaticResolutionBeforeAI() async {
        let assisted = AssistedRepeatInterpreterSpy(availability: .available, candidate: .daily)
        let resolver = makeResolver(assisted: assisted)

        let bareOrdinal = await resolver.resolve("Every 1st Friday", mode: .automatic)
        let missingPreposition = await resolver.resolve(
            "Every month 1st Friday",
            mode: .automatic
        )

        #expect(bareOrdinal == .suggested(["Every Friday"]))
        #expect(missingPreposition == .suggested(["Every month on the 1st Friday"]))
        #expect(await assisted.events.isEmpty)
    }

    @Test func noCandidatesAutomaticallyUseAssistance() async {
        let assisted = AssistedRepeatInterpreterSpy(
            availability: .available,
            candidate: .weeklyMonday
        )
        _ = await makeResolver(assisted: assisted)
            .resolve("Remind me on alternate Mondays", mode: .automatic)
        #expect(
            await assisted.events == [
                .availability, .interpret("Remind me on alternate Mondays")
            ])
    }

    @Test func assistedOnlyBypassesAValidDeterministicCandidate() async {
        let assisted = AssistedRepeatInterpreterSpy(availability: .available, candidate: .daily)
        _ = await makeResolver(assisted: assisted)
            .resolve("Every mont", mode: .assistedOnly)
        #expect(await assisted.events == [.availability, .interpret("Every mont")])
    }

    @Test func parserFailureChecksAvailabilityBeforeInterpretation() async {
        let assisted = AssistedRepeatInterpreterSpy(
            availability: .available,
            candidate: .weeklyMonday
        )
        let resolution = await makeResolver(assisted: assisted).resolve("毎週月曜日")

        guard case .resolved(let value) = resolution else {
            Issue.record("Expected assisted resolution, got \(resolution)")
            return
        }
        #expect(value.route == .assisted)
        #expect(
            value.rule
                == .weekly(
                    interval: 1,
                    weekdaySetKind: .explicit,
                    weekdays: [.monday]
                ))
        #expect(await assisted.events == [.availability, .interpret("毎週月曜日")])
    }

    @Test(arguments: [
        AssistedRepeatUnavailableReason.platformUnsupported,
        .deviceNotEligible,
        .appleIntelligenceNotEnabled,
        .modelNotReady
    ])
    func eachUnavailableReasonIsPreservedAsAFieldError(
        reason: AssistedRepeatUnavailableReason
    ) async {
        let assisted = AssistedRepeatInterpreterSpy(
            availability: .unavailable(reason),
            candidate: .weeklyMonday
        )

        let resolution = await makeResolver(assisted: assisted).resolve("毎週月曜日")

        #expect(resolution.error == .assistanceUnavailable(reason))
        #expect(await assisted.events == [.availability])
    }

    @Test func generatedCandidateAlwaysPassesThroughTheDeterministicValidator() async {
        let assisted = AssistedRepeatInterpreterSpy(
            availability: .available,
            candidate: RepeatCandidate(frequency: .daily, interval: 0)
        )

        let resolution = await makeResolver(assisted: assisted).resolve("毎日")

        #expect(resolution.error == .validation(.intervalOutOfRange))
    }

    @Test func generatedUnsupportedResultCannotBecomeASchedule() async {
        let assisted = AssistedRepeatInterpreterSpy(
            availability: .available,
            candidate: RepeatCandidate(isSupported: false, frequency: .daily, interval: 1)
        )

        let resolution = await makeResolver(assisted: assisted).resolve("来週にして")

        #expect(resolution.error == .validation(.unsupported))
    }

    @Test(arguments: [
        AssistedExclusionScenario(
            input: "Every Monday except first Monday",
            mode: .automatic
        ),
        AssistedExclusionScenario(
            input: "Every Monday except first Monday",
            mode: .assistedOnly
        ),
        AssistedExclusionScenario(
            input: "Every Monday except first Monday.",
            mode: .automatic
        ),
        AssistedExclusionScenario(
            input: "Every Monday except first Monday.",
            mode: .assistedOnly
        ),
        AssistedExclusionScenario(
            input: "毎週 except first Monday",
            mode: .automatic
        ),
        AssistedExclusionScenario(
            input: "毎週 except first Monday",
            mode: .assistedOnly
        )
    ])
    fileprivate func assistedExclusionCannotCreateASchedule(
        scenario: AssistedExclusionScenario
    ) async {
        let assisted = AssistedRepeatInterpreterSpy(
            availability: .available,
            candidate: .weeklyMonday
        )

        let resolution = await makeResolver(assisted: assisted)
            .resolve(scenario.input, mode: scenario.mode)

        #expect(resolution == .failed(.validation(.unsupported)))
        #expect(await assisted.events == [.availability, .interpret(scenario.input)])
    }

    @Test(arguments: [
        AssistedRepeatInterpretationError.safetyGuard,
        .generation
    ])
    func assistedFailuresKeepSafetyAndGenerationDistinct(
        interpretationError: AssistedRepeatInterpretationError
    ) async {
        let assisted = AssistedRepeatInterpreterSpy(
            availability: .available,
            error: interpretationError
        )

        let resolution = await makeResolver(assisted: assisted).resolve("毎日")

        let expected: CustomRepeatResolutionError =
            switch interpretationError {
            case .unsupportedLanguageOrLocale: .unsupportedLanguageOrLocale
            case .safetyGuard: .safetyGuard
            case .generation: .generation
            }
        #expect(resolution.error == expected)
    }

    @Test func unsupportedLanguageOrLocaleIsNotMappedToGeneration() async {
        let assisted = AssistedRepeatInterpreterSpy(
            availability: .available,
            error: AssistedRepeatInterpretationError.unsupportedLanguageOrLocale
        )

        let resolution = await makeResolver(assisted: assisted).resolve("毎日")

        #expect(resolution.error == CustomRepeatResolutionError.unsupportedLanguageOrLocale)
    }

    @Test func unknownInterpreterFailureMapsToGenerationWithoutLeakingDetails() async {
        let assisted = AssistedRepeatInterpreterSpy(
            availability: .available,
            error: UnknownInterpreterFailure()
        )

        let resolution = await makeResolver(assisted: assisted).resolve("毎日")

        #expect(resolution.error == .generation)
    }

    @Test func confirmationSessionExposesOnlyPreviewUntilTheUserConfirms() async throws {
        let reminderID = UUID(uuidString: "13131313-1313-1313-1313-131313131313")!
        let assisted = AssistedRepeatInterpreterSpy(
            availability: .available,
            candidate: .daily
        )
        let session = CustomRepeatSession(
            resolver: makeResolver(assisted: assisted),
            reminderID: reminderID,
            now: { Self.previewNow },
            recurrenceEnvironment: FoundationRecurrenceEnvironment()
        )

        let outcome = try await session.submit("毎日")

        guard case .applied(.awaitingConfirmation(let preview)) = outcome else {
            Issue.record("Expected a pending confirmation, got \(outcome)")
            return
        }
        #expect(preview.route == .assisted)
        #expect(preview.rule == .daily(interval: 1))
        #expect(preview.canonicalEnglish == "Every day")
        #expect(preview.nextNotifications.notifications.count == 3)

        let confirmed = await session.confirm()
        #expect(
            confirmed
                == ScheduleDefinition(
                    source: Self.source,
                    rule: .daily(interval: 1),
                    end: .never,
                    early: nil
                ))
    }

    @Test func failedSubmissionCannotExposeAScheduleForPersistence() async throws {
        let assisted = AssistedRepeatInterpreterSpy(
            availability: .available,
            candidate: RepeatCandidate(frequency: .monthly, interval: 1)
        )
        let session = CustomRepeatSession(
            resolver: makeResolver(assisted: assisted),
            reminderID: UUID(uuidString: "13131313-1313-1313-1313-131313131313")!,
            now: { Self.previewNow },
            recurrenceEnvironment: FoundationRecurrenceEnvironment()
        )

        let outcome = try await session.submit("毎月")

        #expect(outcome == .applied(.failed(.validation(.invalidCombination))))
        #expect(await session.confirm() == nil)
    }

    @Test func resetDiscardsRawInputGeneratedCandidatePreviewAndConfirmation() async throws {
        let assisted = AssistedRepeatInterpreterSpy(
            availability: .available,
            candidate: .daily
        )
        let session = CustomRepeatSession(
            resolver: makeResolver(assisted: assisted),
            reminderID: UUID(uuidString: "13131313-1313-1313-1313-131313131313")!,
            now: { Self.previewNow },
            recurrenceEnvironment: FoundationRecurrenceEnvironment()
        )
        _ = try await session.submit("毎日")
        #expect(await session.confirm() != nil)

        let resetState = await session.reset()

        #expect(resetState == .idle)
        #expect(await session.confirm() == nil)
    }

    @Test func resetWhileSubmissionIsSuspendedDiscardsItsLaterResolution() async throws {
        let resolver = ControlledCustomRepeatResolver()
        let session = makeControlledSession(resolver: resolver)
        let staleSubmission = Task {
            try await session.submit("A")
        }
        await resolver.waitUntilRequested("A")

        #expect(await session.reset() == .idle)
        await resolver.resume("A", with: Self.dailyResolution)

        let staleOutcome = try await staleSubmission.value
        #expect(staleOutcome == .superseded)
        #expect(await session.confirm() == nil)
    }

    @Test func assistedOnlySubmissionResetDiscardsItsLaterResolution() async throws {
        let resolver = ControlledCustomRepeatResolver()
        let session = makeControlledSession(resolver: resolver)
        let staleSubmission = Task {
            try await session.submit("A", mode: .assistedOnly)
        }
        await resolver.waitUntilRequested("A", mode: .assistedOnly)

        #expect(await session.reset() == .idle)
        await resolver.resume("A", with: Self.dailyResolution)

        let staleOutcome = try await staleSubmission.value
        #expect(staleOutcome == .superseded)
        #expect(await session.confirm() == nil)
    }

    @Test func newerSuccessfulSubmissionCannotBeReplacedByAnOlderSuspendedOne() async throws {
        let resolver = ControlledCustomRepeatResolver(immediate: [
            "B": Self.weeklyMondayResolution
        ])
        let session = makeControlledSession(resolver: resolver)
        let staleSubmission = Task {
            try await session.submit("A")
        }
        await resolver.waitUntilRequested("A")

        let currentOutcome = try await session.submit("B")
        guard case .applied(.awaitingConfirmation(let preview)) = currentOutcome else {
            Issue.record("Expected B to become the current preview, got \(currentOutcome)")
            return
        }
        #expect(preview.rule == Self.weeklyMondaySchedule.rule)

        await resolver.resume("A", with: Self.dailyResolution)

        let staleOutcome = try await staleSubmission.value
        #expect(staleOutcome == .superseded)
        #expect(await session.confirm() == Self.weeklyMondaySchedule)
    }

    @Test func newerFailedSubmissionPreventsAnOlderSuspendedOneFromBeingResurrected() async throws {
        let resolver = ControlledCustomRepeatResolver(immediate: [
            "B": .failed(.generation)
        ])
        let session = makeControlledSession(resolver: resolver)
        let staleSubmission = Task {
            try await session.submit("A")
        }
        await resolver.waitUntilRequested("A")

        let currentOutcome = try await session.submit("B")
        #expect(currentOutcome == .applied(.failed(.generation)))
        await resolver.resume("A", with: Self.dailyResolution)

        let staleOutcome = try await staleSubmission.value
        #expect(staleOutcome == .superseded)
        #expect(await session.confirm() == nil)
    }

    private func makeResolver(
        assisted: some AssistedRepeatInterpreting
    ) -> CustomRepeatInputResolver {
        CustomRepeatInputResolver(
            source: Self.source,
            end: .never,
            early: nil,
            assistedInterpreter: assisted
        )
    }

    private func makeControlledSession(
        resolver: ControlledCustomRepeatResolver
    ) -> CustomRepeatSession {
        CustomRepeatSession(
            resolver: resolver,
            reminderID: UUID(uuidString: "13131313-1313-1313-1313-131313131313")!,
            now: { Self.previewNow },
            recurrenceEnvironment: FoundationRecurrenceEnvironment()
        )
    }

    private static let source = SourceWallClock(
        year: 2040,
        month: 8,
        day: 31,
        hour: 9,
        minute: 30,
        timeZoneIdentifier: "America/New_York"
    )

    private static let previewNow: Date = {
        let value = "2040-08-30T00:00:00Z"
        guard let date = ISO8601DateFormatter().date(from: value) else {
            preconditionFailure("Invalid ISO-8601 test fixture: \(value)")
        }
        return date
    }()

    private static let dailySchedule = ScheduleDefinition(
        source: source,
        rule: .daily(interval: 1),
        end: .never,
        early: nil
    )

    private static let dailyResolution = CustomRepeatResolution.resolved(
        ResolvedCustomRepeat(
            route: .assisted,
            candidate: .daily,
            schedule: dailySchedule
        )
    )

    private static let weeklyMondaySchedule = ScheduleDefinition(
        source: source,
        rule: .weekly(
            interval: 1,
            weekdaySetKind: .explicit,
            weekdays: [.monday]
        ),
        end: .never,
        early: nil
    )

    private static let weeklyMondayResolution = CustomRepeatResolution.resolved(
        ResolvedCustomRepeat(
            route: .assisted,
            candidate: .weeklyMonday,
            schedule: weeklyMondaySchedule
        )
    )
}

private actor ControlledCustomRepeatResolver: CustomRepeatInputResolving {
    private struct Request: Hashable, Sendable {
        let input: String
        let mode: CustomRepeatResolutionMode
    }

    private var requestedInputs: Set<Request> = []
    private var requestWaiters: [Request: [CheckedContinuation<Void, Never>]] = [:]
    private var resolutionContinuations:
        [String: CheckedContinuation<CustomRepeatResolution, Never>] = [:]
    private let immediate: [String: CustomRepeatResolution]

    init(immediate: [String: CustomRepeatResolution] = [:]) {
        self.immediate = immediate
    }

    func resolve(
        _ input: String,
        mode: CustomRepeatResolutionMode
    ) async -> CustomRepeatResolution {
        let request = Request(input: input, mode: mode)
        requestedInputs.insert(request)
        for waiter in requestWaiters.removeValue(forKey: request) ?? [] {
            waiter.resume()
        }
        if let resolution = immediate[input] {
            return resolution
        }
        return await withCheckedContinuation { continuation in
            resolutionContinuations[input] = continuation
        }
    }

    func waitUntilRequested(
        _ input: String,
        mode: CustomRepeatResolutionMode = .automatic
    ) async {
        let request = Request(input: input, mode: mode)
        guard !requestedInputs.contains(request) else { return }
        await withCheckedContinuation { continuation in
            requestWaiters[request, default: []].append(continuation)
        }
    }

    func resume(_ input: String, with resolution: CustomRepeatResolution) {
        resolutionContinuations.removeValue(forKey: input)?.resume(returning: resolution)
    }
}

private actor AssistedRepeatInterpreterSpy: AssistedRepeatInterpreting {
    enum Event: Sendable, Equatable {
        case availability
        case interpret(String)
    }

    private(set) var events: [Event] = []
    private let availabilityResult: AssistedRepeatAvailability
    private let candidate: RepeatCandidate
    private let error: (any Error & Sendable)?

    init(
        availability: AssistedRepeatAvailability,
        candidate: RepeatCandidate = .daily,
        error: (any Error & Sendable)? = nil
    ) {
        availabilityResult = availability
        self.candidate = candidate
        self.error = error
    }

    func availability() async -> AssistedRepeatAvailability {
        events.append(.availability)
        return availabilityResult
    }

    func interpret(_ input: String) async throws -> RepeatCandidate {
        events.append(.interpret(input))
        if let error { throw error }
        return candidate
    }
}

private struct UnknownInterpreterFailure: Error, Sendable {}

private struct AssistedExclusionScenario: Sendable {
    let input: String
    let mode: CustomRepeatResolutionMode
}

extension RepeatCandidate {
    fileprivate static let daily = RepeatCandidate(frequency: .daily, interval: 1)

    fileprivate static let weeklyMonday = RepeatCandidate(
        frequency: .weekly,
        interval: 1,
        weekdaySetKind: .explicit,
        weekdays: [.monday]
    )
}
