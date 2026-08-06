import Foundation
import SwiftData

@Model
public final class ReminderRecordV1 {
    public var id: UUID = UUID()
    @Attribute(.allowsCloudEncryption) public var title: String = ""
    @Attribute(.allowsCloudEncryption) public var notes: String?
    @Attribute(.allowsCloudEncryption) public var urlString: String?
    public var enabled: Bool = true
    @Attribute(.allowsCloudEncryption) public var scheduleData: Data = Data()
    public var createdAt: Date = Date(timeIntervalSince1970: 0)
    public var updatedAt: Date = Date(timeIntervalSince1970: 0)
    @Relationship(deleteRule: .nullify, inverse: \TagRecordV1.reminders)
    public var tags: [TagRecordV1]?

    public init(
        id: UUID,
        title: String,
        notes: String?,
        urlString: String?,
        enabled: Bool,
        scheduleData: Data,
        createdAt: Date,
        updatedAt: Date,
        tags: [TagRecordV1]? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.urlString = urlString
        self.enabled = enabled
        self.scheduleData = scheduleData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
    }
}
