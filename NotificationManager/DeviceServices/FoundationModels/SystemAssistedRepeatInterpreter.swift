#if canImport(FoundationModels)
    import Foundation
    import FoundationModels
    import NotificationManagerApplication
    import NotificationManagerDomain

    @available(iOS 26.0, *)
    enum FoundationLanguageModelStatus: Sendable, Equatable {
        case available
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
    }

    @available(iOS 26.0, *)
    protocol FoundationModelsRuntime: Sendable {
        func modelStatus() async -> FoundationLanguageModelStatus
        func supportsLocale(_ locale: Locale) async -> Bool
        func generateCandidate(from input: String) async throws -> FoundationRepeatCandidate
    }

    @available(iOS 26.0, *)
    struct LiveFoundationModelsRuntime: FoundationModelsRuntime, Sendable {
        private let model: SystemLanguageModel

        init(model: SystemLanguageModel = .default) {
            self.model = model
        }

        func modelStatus() async -> FoundationLanguageModelStatus {
            guard !model.isAvailable else { return .available }

            return switch model.availability {
            case .available:
                .modelNotReady
            case .unavailable(.deviceNotEligible):
                .deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled):
                .appleIntelligenceNotEnabled
            case .unavailable(.modelNotReady):
                .modelNotReady
            case .unavailable:
                .modelNotReady
            }
        }

        func supportsLocale(_ locale: Locale) async -> Bool {
            model.supportsLocale(locale)
        }

        func generateCandidate(from input: String) async throws -> FoundationRepeatCandidate {
            let session = LanguageModelSession(
                model: model,
                instructions: """
                    Interpret only recurrence rules. Never infer a time, time zone, end condition, title, \
                    reminder text, or spelling correction. Mark unsupported input as unsupported. Return \
                    only the structured schema supplied by the app.
                    """
            )
            let response = try await session.respond(generating: FoundationRepeatCandidate.self) {
                "Interpret this repeat-rule input exactly as written:"
                input
            }
            return response.content
        }
    }

    @available(iOS 26.0, *)
    public struct SystemAssistedRepeatInterpreter: AssistedRepeatInterpreting, Sendable {
        private let runtime: any FoundationModelsRuntime

        public init() {
            runtime = LiveFoundationModelsRuntime()
        }

        init(runtime: any FoundationModelsRuntime) {
            self.runtime = runtime
        }

        public func availability() async -> AssistedRepeatAvailability {
            switch await runtime.modelStatus() {
            case .deviceNotEligible:
                return .unavailable(.deviceNotEligible)
            case .appleIntelligenceNotEnabled:
                return .unavailable(.appleIntelligenceNotEnabled)
            case .modelNotReady:
                return .unavailable(.modelNotReady)
            case .available:
                break
            }

            let japanese = Locale(identifier: "ja")
            guard await runtime.supportsLocale(japanese) else {
                return .unavailable(.japaneseLocaleUnsupported)
            }
            return .available
        }

        public func interpret(_ input: String) async throws -> RepeatCandidate {
            do {
                return try await runtime.generateCandidate(from: input).repeatCandidate
            } catch let error as LanguageModelSession.GenerationError {
                switch error {
                case .guardrailViolation, .refusal:
                    throw AssistedRepeatInterpretationError.safetyGuard
                default:
                    throw AssistedRepeatInterpretationError.generation
                }
            } catch let error as AssistedRepeatInterpretationError {
                throw error
            } catch {
                throw AssistedRepeatInterpretationError.generation
            }
        }
    }
#endif
