import NotificationManagerDomain

public enum AssistedRepeatUnavailableReason: Sendable, Equatable, CaseIterable {
    case platformUnsupported
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case japaneseLocaleUnsupported
}

public enum AssistedRepeatAvailability: Sendable, Equatable {
    case available
    case unavailable(AssistedRepeatUnavailableReason)
}

public enum AssistedRepeatInterpretationError: Error, Sendable, Equatable {
    case safetyGuard
    case generation
}

public protocol AssistedRepeatInterpreting: Sendable {
    func availability() async -> AssistedRepeatAvailability
    func interpret(_ input: String) async throws -> RepeatCandidate
}
