import Foundation
import SwiftData

@Model
public final class TagRecordV1 {
    public var id: UUID = UUID()
    @Attribute(.allowsCloudEncryption) public var name: String = ""
    @Attribute(.allowsCloudEncryption) public var normalizedName: String = ""
    public var normalizationVersion: String = "tag-name-normalization-v1"
    public var createdAt: Date = Date(timeIntervalSince1970: 0)
    public var updatedAt: Date = Date(timeIntervalSince1970: 0)
    public var reminders: [ReminderRecordV1]?

    public init(
        id: UUID,
        name: String,
        normalizedName: String,
        normalizationVersion: String,
        createdAt: Date,
        updatedAt: Date,
        reminders: [ReminderRecordV1]? = nil
    ) {
        self.id = id
        self.name = name
        self.normalizedName = normalizedName
        self.normalizationVersion = normalizationVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.reminders = reminders
    }
}
