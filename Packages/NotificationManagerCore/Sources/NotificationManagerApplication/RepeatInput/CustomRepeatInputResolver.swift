import NotificationManagerDomain

public enum CustomRepeatResolutionRoute: Sendable, Equatable {
    case deterministicEnglish
    case assisted
}

public enum CustomRepeatResolutionMode: Sendable, Equatable {
    case automatic
    case assistedOnly
}

public enum CustomRepeatResolutionError: Error, Sendable, Equatable {
    case assistanceUnavailable(AssistedRepeatUnavailableReason)
    case unsupportedLanguageOrLocale
    case safetyGuard
    case generation
    case validation(RepeatCandidateValidationError)
}

public struct ResolvedCustomRepeat: Sendable, Equatable {
    public let route: CustomRepeatResolutionRoute
    public let rule: RepeatRule

    let candidate: RepeatCandidate
    let schedule: ScheduleDefinition

    init(
        route: CustomRepeatResolutionRoute,
        candidate: RepeatCandidate,
        schedule: ScheduleDefinition
    ) {
        self.route = route
        self.candidate = candidate
        self.schedule = schedule
        rule = schedule.rule
    }
}

public enum CustomRepeatResolution: Sendable, Equatable {
    case resolved(ResolvedCustomRepeat)
    case suggested([String])
    case failed(CustomRepeatResolutionError)

    public var isValid: Bool {
        if case .resolved = self { true } else { false }
    }

    public var error: CustomRepeatResolutionError? {
        if case .failed(let error) = self { error } else { nil }
    }
}

public protocol CustomRepeatInputResolving: Sendable {
    func resolve(
        _ input: String,
        mode: CustomRepeatResolutionMode
    ) async -> CustomRepeatResolution
}

extension CustomRepeatInputResolving {
    public func resolve(_ input: String) async -> CustomRepeatResolution {
        await resolve(input, mode: .automatic)
    }
}

public struct CustomRepeatInputResolver: CustomRepeatInputResolving, Sendable {
    private let source: SourceWallClock
    private let end: RepeatEnd
    private let early: EarlyReminder?
    private let assistedInterpreter: any AssistedRepeatInterpreting

    public init(
        source: SourceWallClock,
        end: RepeatEnd,
        early: EarlyReminder?,
        assistedInterpreter: any AssistedRepeatInterpreting
    ) {
        self.source = source
        self.end = end
        self.early = early
        self.assistedInterpreter = assistedInterpreter
    }

    public func resolve(
        _ input: String,
        mode: CustomRepeatResolutionMode
    ) async -> CustomRepeatResolution {
        if mode == .automatic {
            switch EnglishRepeatParser().parse(input) {
            case .success(let candidate):
                return validate(candidate, route: .deterministicEnglish)
            case .failure:
                let suggestions = EnglishRepeatCandidateGenerator().suggestions(for: input)
                if !suggestions.isEmpty {
                    return .suggested(suggestions)
                }
            }
        }

        switch await assistedInterpreter.availability() {
        case .available:
            break
        case .unavailable(let reason):
            return .failed(.assistanceUnavailable(reason))
        }

        do {
            let candidate = try await assistedInterpreter.interpret(input)
            guard
                !EnglishRepeatLexicalSafety()
                    .containsUnsupportedSemanticOperator(in: input)
            else {
                return .failed(.validation(.unsupported))
            }
            return validate(candidate, route: .assisted)
        } catch let error as AssistedRepeatInterpretationError {
            return switch error {
            case .unsupportedLanguageOrLocale: .failed(.unsupportedLanguageOrLocale)
            case .safetyGuard: .failed(.safetyGuard)
            case .generation: .failed(.generation)
            }
        } catch {
            return .failed(.generation)
        }
    }

    private func validate(
        _ candidate: RepeatCandidate,
        route: CustomRepeatResolutionRoute
    ) -> CustomRepeatResolution {
        do {
            let rule = try RepeatRuleValidator().validate(candidate, source: source)
            let schedule = ScheduleDefinition(
                source: source,
                rule: rule,
                end: end,
                early: early
            )
            return .resolved(
                ResolvedCustomRepeat(
                    route: route,
                    candidate: candidate,
                    schedule: schedule
                ))
        } catch let error as RepeatCandidateValidationError {
            return .failed(.validation(error))
        } catch {
            return .failed(.generation)
        }
    }
}
