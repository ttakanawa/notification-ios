import Foundation
import FoundationModels
import NotificationManagerApplication
import NotificationManagerDomain
import Testing

@testable import NotificationManager

struct UnavailableRepeatInterpreterTests {
    @Test func platformFallbackReportsUnavailableAndNeverProducesACandidate() async {
        let interpreter = UnavailableAssistedRepeatInterpreter()

        #expect(await interpreter.availability() == .unavailable(.platformUnsupported))
        await #expect(throws: AssistedRepeatInterpretationError.generation) {
            _ = try await interpreter.interpret("毎日")
        }
    }
}

@Suite("SystemAssistedRepeatInterpreter")
struct SystemAssistedRepeatInterpreterTests {
    @Test func modelUnavailableReasonsAreExactAndLocaleIsNotQueried() async {
        guard #available(iOS 26.0, *) else { return }
        let fixtures: [(FoundationLanguageModelStatus, AssistedRepeatUnavailableReason)] = [
            (.deviceNotEligible, .deviceNotEligible),
            (.appleIntelligenceNotEnabled, .appleIntelligenceNotEnabled),
            (.modelNotReady, .modelNotReady)
        ]

        for (status, reason) in fixtures {
            let runtime = FoundationModelsRuntimeSpy(status: status)
            let interpreter = SystemAssistedRepeatInterpreter(runtime: runtime)

            #expect(await interpreter.availability() == .unavailable(reason))
            #expect(await runtime.events == [.status])
        }
    }

    @Test func availableModelNeedsNoInputLanguagePreflight() async {
        guard #available(iOS 26.0, *) else { return }
        let runtime = FoundationModelsRuntimeSpy(status: .available)
        let interpreter = SystemAssistedRepeatInterpreter(runtime: runtime)

        #expect(await interpreter.availability() == .available)
        #expect(await runtime.events == [.status])
    }

    @Test func generatedAdapterMapsExplicitlyToLocaleNeutralCandidate() async throws {
        guard #available(iOS 26.0, *) else { return }
        let generated = FoundationRepeatCandidate(
            isSupported: true,
            frequency: .yearly,
            interval: 2,
            weekdaySetKind: .none,
            weekdays: [],
            month: .march,
            selector: .ordinalWeekday(
                FoundationOrdinalWeekday(
                    ordinal: -2,
                    weekday: .monday
                ))
        )
        let runtime = FoundationModelsRuntimeSpy(
            status: .available,
            generated: generated
        )
        let interpreter = SystemAssistedRepeatInterpreter(runtime: runtime)

        let candidate = try await interpreter.interpret("毎年3月の最後から2番目の月曜日")

        #expect(
            candidate
                == RepeatCandidate(
                    frequency: .yearly,
                    interval: 2,
                    month: 3,
                    selector: .ordinalWeekday(ordinal: -2, weekday: .monday)
                ))
        #expect(await runtime.events == [.generate("毎年3月の最後から2番目の月曜日")])
    }

    @Test func schemaRoundTripsEveryGuidedShapeWithoutCanonicalEnglish() throws {
        guard #available(iOS 26.0, *) else { return }
        let generated = FoundationRepeatCandidate(
            isSupported: true,
            frequency: .weekly,
            interval: 1,
            weekdaySetKind: .explicit,
            weekdays: [.monday, .wednesday, .friday],
            month: .none,
            selector: .none
        )

        let decoded = try FoundationRepeatCandidate(generated.generatedContent)

        #expect(decoded == generated)
        #expect(
            decoded.repeatCandidate
                == RepeatCandidate(
                    frequency: .weekly,
                    interval: 1,
                    weekdaySetKind: .explicit,
                    weekdays: [.monday, .wednesday, .friday]
                ))
    }

    @Test func generationSchemaContainsEnumRangeOrdinalAndCollectionGuides() {
        guard #available(iOS 26.0, *) else { return }
        let schema = FoundationRepeatCandidate.generationSchema.debugDescription

        #expect(schema.contains("interval"))
        #expect(schema.contains("9999"))
        #expect(schema.contains("weekdays"))
        #expect(schema.contains("maxItems"))
        #expect(schema.contains("ordinal"))
        #expect(schema.contains("-5"))
        #expect(schema.contains("monday"))
    }

    @Test func guardrailAndRefusalMapToSafety() async {
        guard #available(iOS 26.0, *) else { return }
        for failure in [FoundationModelsRuntimeFailure.guardrail, .refusal] {
            let runtime = FoundationModelsRuntimeSpy(
                status: .available,
                failure: failure
            )
            let interpreter = SystemAssistedRepeatInterpreter(runtime: runtime)

            await #expect(throws: AssistedRepeatInterpretationError.safetyGuard) {
                _ = try await interpreter.interpret("危険な入力")
            }
        }
    }

    @Test func unsupportedLanguageOrLocaleKeepsItsIdentity() async {
        guard #available(iOS 26.0, *) else { return }
        let runtime = FoundationModelsRuntimeSpy(status: .available, failure: .unsupportedLocale)
        let interpreter = SystemAssistedRepeatInterpreter(runtime: runtime)

        await #expect(throws: AssistedRepeatInterpretationError.unsupportedLanguageOrLocale) {
            _ = try await interpreter.interpret("Remind me on alternate Mondays")
        }
    }

    @Test func otherNonSafetyFailuresMapToGeneration() async {
        guard #available(iOS 26.0, *) else { return }
        let failures: [FoundationModelsRuntimeFailure] = [
            .assetsUnavailable,
            .unknown
        ]
        for failure in failures {
            let runtime = FoundationModelsRuntimeSpy(
                status: .available,
                failure: failure
            )
            let interpreter = SystemAssistedRepeatInterpreter(runtime: runtime)

            await #expect(throws: AssistedRepeatInterpretationError.generation) {
                _ = try await interpreter.interpret("毎日")
            }
        }
    }

    @Test(.disabled("Requires a supported physical device with the Japanese on-device model"))
    func physicalJapaneseModelQualityFixture() async throws {
        guard #available(iOS 26.0, *) else { return }
        _ = try await SystemAssistedRepeatInterpreter().interpret("毎週月曜日")
    }
}

@available(iOS 26.0, *)
private actor FoundationModelsRuntimeSpy: FoundationModelsRuntime {
    enum Event: Sendable, Equatable {
        case status
        case generate(String)
    }

    private(set) var events: [Event] = []
    private let statusResult: FoundationLanguageModelStatus
    private let generated: FoundationRepeatCandidate
    private let failure: FoundationModelsRuntimeFailure?

    init(
        status: FoundationLanguageModelStatus,
        generated: FoundationRepeatCandidate = .daily,
        failure: FoundationModelsRuntimeFailure? = nil
    ) {
        statusResult = status
        self.generated = generated
        self.failure = failure
    }

    func modelStatus() async -> FoundationLanguageModelStatus {
        events.append(.status)
        return statusResult
    }

    func generateCandidate(from input: String) async throws -> FoundationRepeatCandidate {
        events.append(.generate(input))
        switch failure {
        case .guardrail:
            throw LanguageModelSession.GenerationError.guardrailViolation(
                .init(debugDescription: "test guardrail")
            )
        case .refusal:
            throw LanguageModelSession.GenerationError.refusal(
                .init(transcriptEntries: []),
                .init(debugDescription: "test refusal")
            )
        case .assetsUnavailable:
            throw LanguageModelSession.GenerationError.assetsUnavailable(
                .init(debugDescription: "test assets")
            )
        case .unsupportedLocale:
            throw LanguageModelSession.GenerationError.unsupportedLanguageOrLocale(
                .init(debugDescription: "test locale")
            )
        case .unknown:
            throw UnknownFoundationModelsRuntimeFailure()
        case nil:
            return generated
        }
    }
}

@available(iOS 26.0, *)
enum FoundationModelsRuntimeFailure: Sendable {
    case guardrail
    case refusal
    case assetsUnavailable
    case unsupportedLocale
    case unknown
}

private struct UnknownFoundationModelsRuntimeFailure: Error, Sendable {}

@available(iOS 26.0, *)
extension FoundationRepeatCandidate {
    fileprivate static let daily = FoundationRepeatCandidate(
        isSupported: true,
        frequency: .daily,
        interval: 1,
        weekdaySetKind: .none,
        weekdays: [],
        month: .none,
        selector: .none
    )
}
