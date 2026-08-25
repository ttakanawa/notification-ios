import NotificationManagerDomain

public enum AssistedRepeatUnavailableReason: Sendable, Equatable, CaseIterable {
    case platformUnsupported
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
}

public enum AssistedRepeatAvailability: Sendable, Equatable {
    case available
    case unavailable(AssistedRepeatUnavailableReason)
}

public enum AssistedRepeatInterpretationError: Error, Sendable, Equatable {
    case unsupportedLanguageOrLocale
    case safetyGuard
    case generation
}

public protocol AssistedRepeatInterpreting: Sendable {
    func availability() async -> AssistedRepeatAvailability
    func interpret(_ input: String) async throws -> RepeatCandidate
}
