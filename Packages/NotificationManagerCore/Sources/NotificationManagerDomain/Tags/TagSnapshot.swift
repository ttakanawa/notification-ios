import Foundation

public enum TagLimits {
    public static let nameBytes = 256
    public static let normalizedNameBytes = 256
    public static let normalizationVersion = "tag-name-normalization-v1"
}

public struct TagSnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let normalizedName: String
    public let normalizationVersion: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        name: String,
        normalizedName: String,
        normalizationVersion: String = TagLimits.normalizationVersion,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.normalizedName = normalizedName
        self.normalizationVersion = normalizationVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
