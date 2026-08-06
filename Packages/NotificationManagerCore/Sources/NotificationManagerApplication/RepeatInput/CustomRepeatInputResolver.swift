import NotificationManagerDomain

public enum CustomRepeatResolutionRoute: Sendable, Equatable {
    case deterministicEnglish
    case japaneseAssisted
}

public enum CustomRepeatResolutionError: Error, Sendable, Equatable {
    case assistanceUnavailable(AssistedRepeatUnavailableReason)
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
    case failed(CustomRepeatResolutionError)

    public var isValid: Bool {
        if case .resolved = self { true } else { false }
    }

    public var error: CustomRepeatResolutionError? {
        if case let .failed(error) = self { error } else { nil }
    }
}

public protocol CustomRepeatInputResolving: Sendable {
    func resolve(_ input: String) async -> CustomRepeatResolution
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

    public func resolve(_ input: String) async -> CustomRepeatResolution {
        switch EnglishRepeatParser().parse(input) {
        case let .success(candidate):
            return validate(candidate, route: .deterministicEnglish)
        case .failure:
            break
        }

        switch await assistedInterpreter.availability() {
        case .available:
            break
        case let .unavailable(reason):
            return .failed(.assistanceUnavailable(reason))
        }

        do {
            let candidate = try await assistedInterpreter.interpret(input)
            return validate(candidate, route: .japaneseAssisted)
        } catch let error as AssistedRepeatInterpretationError {
            return switch error {
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
            return .resolved(ResolvedCustomRepeat(
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
