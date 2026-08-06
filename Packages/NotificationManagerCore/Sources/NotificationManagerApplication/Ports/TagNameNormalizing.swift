public enum TagValidationIssue: Error, Sendable, Equatable {
    case nameTooLarge
    case normalizedNameEmpty
    case normalizedNameTooLarge
    case normalizedNameMismatch
    case unsupportedNormalizationVersion
    case invalidCreatedAt
    case invalidUpdatedAt
}

public protocol TagNameNormalizing: Sendable {
    func normalize(_ name: String) throws -> String
}
