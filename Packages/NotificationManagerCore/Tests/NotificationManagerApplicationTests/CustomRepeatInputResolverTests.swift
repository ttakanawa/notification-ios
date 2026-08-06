import Foundation
import NotificationManagerDomain
import Testing
@testable import NotificationManagerApplication

@Suite("CustomRepeatInputResolver")
struct CustomRepeatInputResolverTests {
    @Test func deterministicEnglishSuccessBypassesAssistedAvailabilityAndInterpretation() async {
        let assisted = AssistedRepeatInterpreterSpy(
            availability: .unavailable(.deviceNotEligible),
            candidate: .daily
        )
        let resolution = await makeResolver(assisted: assisted).resolve("Every 2 weeks")

        guard case let .resolved(value) = resolution else {
            Issue.record("Expected deterministic English resolution, got \(resolution)")
            return
        }
        #expect(value.route == .deterministicEnglish)
        #expect(value.rule == .weekly(
            interval: 2,
            weekdaySetKind: .explicit,
            weekdays: [.friday]
        ))
        #expect(await assisted.events.isEmpty)
    }

    @Test func parserFailureChecksAvailabilityBeforeInterpretation() async {
        let assisted = AssistedRepeatInterpreterSpy(
            availability: .available,
            candidate: .weeklyMonday
        )
        let resolution = await makeResolver(assisted: assisted).resolve("毎週月曜日")

        guard case let .resolved(value) = resolution else {
            Issue.record("Expected assisted resolution, got \(resolution)")
            return
        }
        #expect(value.route == .japaneseAssisted)
        #expect(value.rule == .weekly(
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
        .modelNotReady,
        .japaneseLocaleUnsupported
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

    @Test func japaneseAvailabilityDoesNotDependOnTheUILocale() async {
        let assisted = AssistedRepeatInterpreterSpy(
            availability: .unavailable(.japaneseLocaleUnsupported),
            candidate: .weeklyMonday
        )
        let resolver = CustomRepeatInputResolver(
            source: Self.source,
            end: .never,
            early: nil,
            assistedInterpreter: assisted
        )

        let resolution = await resolver.resolve("毎週月曜日")

        #expect(resolution.error == .assistanceUnavailable(.japaneseLocaleUnsupported))
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

        let expected: CustomRepeatResolutionError = switch interpretationError {
        case .safetyGuard: .safetyGuard
        case .generation: .generation
        }
        #expect(resolution.error == expected)
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

        let state = try await session.submit("毎日")

        guard case let .awaitingConfirmation(preview) = state else {
            Issue.record("Expected a pending confirmation, got \(state)")
            return
        }
        #expect(preview.route == .japaneseAssisted)
        #expect(preview.rule == .daily(interval: 1))
        #expect(preview.canonicalEnglish == "Every day")
        #expect(preview.nextNotifications.notifications.count == 3)

        let confirmed = await session.confirm()
        #expect(confirmed == ScheduleDefinition(
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

        let state = try await session.submit("毎月")

        #expect(state == .failed(.validation(.invalidCombination)))
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

    private static let source = SourceWallClock(
        year: 2040,
        month: 8,
        day: 31,
        hour: 9,
        minute: 30,
        timeZoneIdentifier: "America/New_York"
    )

    private static let previewNow = ISO8601DateFormatter().date(
        from: "2040-08-30T00:00:00Z"
    )!
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

private extension RepeatCandidate {
    static let daily = RepeatCandidate(frequency: .daily, interval: 1)

    static let weeklyMonday = RepeatCandidate(
        frequency: .weekly,
        interval: 1,
        weekdaySetKind: .explicit,
        weekdays: [.monday]
    )
}
