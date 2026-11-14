import CryptoKit
import Foundation
import NotificationManagerDomain
import SwiftData

public enum RetainedStoreError: Error, Sendable, Equatable {
    case unsupportedArchive(Int)
    case invalidRevision
    case immutableRevisionCollision
    case confirmationRequired
    case staleAccount
}

/// Immutable versions form a causal DAG. No device wall clock participates in conflict selection.
public struct RetainedCloudRevision: Codable, Sendable, Equatable, Identifiable {
    public let schemaVersion: Int
    public let id: UUID
    public let entityKey: String
    public let parents: [UUID]
    public let payload: Data?

    public init(id: UUID = UUID(), entityKey: String, parents: [UUID] = [], payload: Data?) {
        schemaVersion = 1
        self.id = id
        self.entityKey = entityKey
        self.parents = parents.sorted { $0.uuidString < $1.uuidString }
        self.payload = payload
    }

    public func encoded() throws -> Data { try RetainedCoding.encode(self) }
    public var fingerprint: String {
        // Encoding this closed value type cannot fail (no floating point or custom encoders).
        SHA256.hash(data: (try? encoded()) ?? Data()).map { String(format: "%02x", $0) }.joined()
    }
}

public struct RetainedReminderValue: Codable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var notes: String?
    public var urlString: String?
    public var enabled: Bool
    public var scheduleData: Data
    public var tagIDs: [UUID]
    public var createdAt: Date
    public var updatedAt: Date
    public var displayCustomizationData: Data?

    public init(_ snapshot: ReminderSnapshot) {
        id = snapshot.id
        title = snapshot.title
        notes = snapshot.notes
        urlString = snapshot.urlString
        enabled = snapshot.enabled
        switch snapshot.schedule {
        case .valid(_, _, let data), .domainInvalid(_, let data, _),
            .unsupportedFuture(_, let data), .corrupt(let data):
            scheduleData = data
        }
        tagIDs = snapshot.tagIDs.sorted { $0.uuidString < $1.uuidString }
        createdAt = snapshot.createdAt
        updatedAt = snapshot.updatedAt
        displayCustomizationData = snapshot.displayCustomizationData
    }

    public func snapshot() -> ReminderSnapshot {
        ReminderSnapshot(
            id: id, title: title, notes: notes, urlString: urlString, enabled: enabled,
            schedule: SchedulePayloadCodec().decode(scheduleData), tagIDs: Set(tagIDs),
            createdAt: createdAt, updatedAt: updatedAt,
            displayCustomizationData: displayCustomizationData
        )
    }
}

struct RetainedTagValue: Codable, Sendable, Equatable {
    let id: UUID
    let name: String
    let normalizedName: String
    let normalizationVersion: String
    let createdAt: Date
    let updatedAt: Date

    init(_ tag: TagSnapshot) {
        id = tag.id
        name = tag.name
        normalizedName = tag.normalizedName
        normalizationVersion = tag.normalizationVersion
        createdAt = tag.createdAt
        updatedAt = tag.updatedAt
    }

    func snapshot() -> TagSnapshot {
        TagSnapshot(
            id: id, name: name, normalizedName: normalizedName,
            normalizationVersion: normalizationVersion, createdAt: createdAt, updatedAt: updatedAt
        )
    }
}

public struct RetainedLegacySnapshot: Sendable {
    public let revisions: [RetainedCloudRevision]

    /// Read raw values before ever attaching an account-bound CloudKit mirror.
    @MainActor
    public init(container: ModelContainer) throws {
        let context = ModelContext(container)
        let reminders = try context.fetch(FetchDescriptor<ReminderRecordV1>())
        let tags = try context.fetch(FetchDescriptor<TagRecordV1>())
        revisions =
            try tags.map { tag in
                RetainedCloudRevision(
                    entityKey: "tag/\(tag.id.uuidString)",
                    payload: try RetainedCoding.encode(
                        RetainedTagValue(
                            RecordMapper(scheduleCodec: SchedulePayloadCodec()).tag(tag)))
                )
            }
            + reminders.map { reminder in
                RetainedCloudRevision(
                    entityKey: "reminder/\(reminder.id.uuidString)",
                    payload: try RetainedCoding.encode(
                        RetainedReminderValue(
                            RecordMapper(scheduleCodec: SchedulePayloadCodec()).reminder(reminder))
                    )
                )
            }
    }
}

public enum RetainedSyncPhase: String, Codable, Sendable {
    case off, checking, unavailable, confirmationRequired, syncing, failed
}

public struct RetainedSyncStatus: Sendable, Equatable {
    public let isEnabled: Bool
    public let phase: RetainedSyncPhase
    public let recoveryCopyCount: Int
    public let pendingRevisionCount: Int
}

enum RetainedSyncPreference: String, Codable, Sendable {
    case unspecified, enabled, off
}

struct RetainedArchive: Codable, Sendable {
    var schemaVersion = 1
    var revisions: [String: RetainedCloudRevision] = [:]
    var acknowledgments: [String: [String: String]] = [:]
    var syncPreference: RetainedSyncPreference = .unspecified
    var acceptedAccount: String?
    var originAccount: String?
    var legacyImported = false
    var engineStates: [String: Data] = [:]
    var legacyRecords: [String: Data] = [:]
    var legacyCurrent: [String: [String: Data]] = [:]
    var legacyHeads: [String: [String: String]] = [:]
    var legacyCommitted: [String: [String: String]] = [:]
    var legacyTokens: [String: Data] = [:]
}

enum RetainedCoding {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}
