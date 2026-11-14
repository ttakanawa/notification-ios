import CloudKit
import CryptoKit
import Foundation
import NotificationManagerDomain

/// Portable copies include asset contents rather than temporary CKAsset URLs.
public struct LegacyCloudRecord: Codable, Sendable, Equatable {
    public let name: String
    public let type: String
    public let fields: [String: LegacyCloudValue]

    public init(record: CKRecord) throws {
        name = record.recordID.recordName
        type = record.recordType
        var values: [String: LegacyCloudValue] = [:]
        for key in record.allKeys() {
            if let value = record.encryptedValues[key] ?? record[key] {
                values[key] = try LegacyCloudValue(value)
            }
        }
        for key in record.encryptedValues.allKeys() {
            if let value = record.encryptedValues[key] { values[key] = try LegacyCloudValue(value) }
        }
        fields = values
    }

    init(name: String, type: String, fields: [String: LegacyCloudValue]) {
        self.name = name
        self.type = type
        self.fields = fields
    }

    func field(_ key: String) -> LegacyCloudValue? { fields["CD_\(key)"] }

    func bytes(_ key: String) -> Data? {
        if case .data(let data) = field(key) { return data }
        if case .data(let data) = field("\(key)_ckAsset") { return data }
        return nil
    }

    func string(_ key: String) -> String? {
        if case .string(let text) = field(key) { return text }
        if let data = bytes(key) { return String(data: data, encoding: .utf8) }
        return nil
    }

    var uuid: UUID? {
        if let text = string("id") { return UUID(uuidString: text) }
        if let data = bytes("id"), data.count == 16 {
            return data.withUnsafeBytes { bytes in
                UUID(uuid: bytes.loadUnaligned(as: uuid_t.self))
            }
        }
        return nil
    }

    func date(_ key: String) -> Date? {
        if case .date(let date) = field(key) { return date }
        return nil
    }
}

public indirect enum LegacyCloudValue: Codable, Sendable, Equatable {
    case string(String)
    case data(Data)
    case number(Double)
    case date(Date)
    case reference(String)
    case array([LegacyCloudValue])

    init(_ value: Any) throws {
        switch value {
        case let value as String: self = .string(value)
        case let value as Data: self = .data(value)
        case let value as Date: self = .date(value)
        case let value as NSNumber: self = .number(value.doubleValue)
        case let value as CKRecord.Reference: self = .reference(value.recordID.recordName)
        case let value as CKAsset:
            guard let url = value.fileURL else { throw RetainedStoreError.invalidRevision }
            self = .data(try Data(contentsOf: url))
        case let values as [Any]: self = .array(try values.map(Self.init))
        default: throw RetainedStoreError.invalidRevision
        }
    }
}

extension RetainedReminderRepository {
    public func legacyToken(account: String) -> Data? { archive.legacyTokens[account] }

    /// The page, raw recovery copies, decoded versions and token commit in one local write.
    public func importLegacyPage(
        records: [LegacyCloudRecord], deletedNames: [String], token: Data, account: String
    ) throws {
        guard currentAccount == account, phase == .syncing else {
            throw RetainedStoreError.staleAccount
        }
        var next = archive
        var cache = next.legacyCurrent[account, default: [:]]
        for record in records {
            let data = try RetainedCoding.encode(record)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            next.legacyRecords["\(account)/\(record.name)/\(digest)"] = data
            cache[record.name] = data
        }
        for name in deletedNames {
            if let data = cache[name],
                let removed = try? JSONDecoder().decode(LegacyCloudRecord.self, from: data),
                let id = removed.uuid,
                removed.type == "CD_ReminderRecordV1" || removed.type == "CD_TagRecordV1"
            {
                let kind = removed.type == "CD_ReminderRecordV1" ? "reminder" : "tag"
                let key = "\(kind)/\(id.uuidString)"
                let previous = next.legacyHeads[account]?[key].flatMap(UUID.init(uuidString:))
                let tombstone = RetainedCloudRevision(
                    entityKey: key, parents: previous.map { [$0] } ?? [], payload: nil)
                next.revisions[tombstone.id.uuidString] = tombstone
                next.legacyHeads[account, default: [:]][key] = tombstone.id.uuidString
                next.legacyCommitted[account, default: [:]][tombstone.id.uuidString] =
                    tombstone.fingerprint
            }
            cache.removeValue(forKey: name)
        }
        next.legacyCurrent[account] = cache
        let values = try cache.values.map {
            try JSONDecoder().decode(LegacyCloudRecord.self, from: $0)
        }
        let byName = Dictionary(uniqueKeysWithValues: values.map { ($0.name, $0) })
        var associations: [UUID: Set<UUID>] = [:]
        for relationship in values where relationship.type == "CDMR" {
            guard let names = relationship.string("recordNames")?.components(separatedBy: ":"),
                names.count == 2,
                let first = byName[names[0]], let second = byName[names[1]]
            else { continue }
            let reminder = first.type == "CD_ReminderRecordV1" ? first : second
            let tag = first.type == "CD_TagRecordV1" ? first : second
            if reminder.type == "CD_ReminderRecordV1", tag.type == "CD_TagRecordV1",
                let reminderID = reminder.uuid, let tagID = tag.uuid
            {
                associations[reminderID, default: []].insert(tagID)
            }
        }
        for record in values {
            guard let id = record.uuid else { continue }
            let key: String
            let payload: Data
            if record.type == "CD_TagRecordV1" {
                guard let name = record.string("name"),
                    let normalized = record.string("normalizedName"),
                    let version = record.string("normalizationVersion"),
                    let created = record.date("createdAt"),
                    let updated = record.date("updatedAt")
                else { continue }  // Raw records remain available for future schema decoders.
                key = "tag/\(id.uuidString)"
                payload = try RetainedCoding.encode(
                    RetainedTagValue(
                        TagSnapshot(
                            id: id, name: name, normalizedName: normalized,
                            normalizationVersion: version,
                            createdAt: created, updatedAt: updated
                        )))
            } else if record.type == "CD_ReminderRecordV1" {
                guard let title = record.string("title"),
                    let schedule = record.bytes("scheduleData"),
                    let created = record.date("createdAt"), let updated = record.date("updatedAt"),
                    case .number(let enabled) = record.field("enabled")
                else { continue }
                key = "reminder/\(id.uuidString)"
                payload = try RetainedCoding.encode(
                    RetainedReminderValue(
                        ReminderSnapshot(
                            id: id, title: title, notes: record.string("notes"),
                            urlString: record.string("urlString"),
                            enabled: enabled != 0,
                            schedule: SchedulePayloadCodec().decode(schedule),
                            tagIDs: associations[id, default: []], createdAt: created,
                            updatedAt: updated
                        )))
            } else {
                continue
            }
            let previousID = next.legacyHeads[account]?[key]
            if let previousID, next.revisions[previousID]?.payload == payload { continue }
            let revision = RetainedCloudRevision(
                entityKey: key,
                parents: previousID.flatMap(UUID.init(uuidString:)).map { [$0] } ?? [],
                payload: payload
            )
            next.revisions[revision.id.uuidString] = revision
            next.legacyHeads[account, default: [:]][key] = revision.id.uuidString
            // Legacy cloud data is committed, but the immutable V1 copy must also be sent.
            next.legacyCommitted[account, default: [:]][revision.id.uuidString] =
                revision.fingerprint
        }
        next.legacyTokens[account] = token
        try commit(next)
    }
}
