import NotificationManagerApplication
import NotificationManagerDomain

public struct UnavailableAssistedRepeatInterpreter: AssistedRepeatInterpreting, Sendable {
    public init() {}

    public func availability() async -> AssistedRepeatAvailability {
        .unavailable(.platformUnsupported)
    }

    public func interpret(_ input: String) async throws -> RepeatCandidate {
        throw AssistedRepeatInterpretationError.generation
    }
}
