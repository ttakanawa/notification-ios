import CryptoKit
import Foundation

public enum WidgetSnapshotConstants {
    public static let schemaVersion = 1
    public static let maximumEventCount = 60
    public static let appGroupIdentifier = "group.org.tknw.punctual"
    public static let fileName = "upcoming-reminders-v1.json"
    public static let widgetKind = "org.tknw.punctual.upcoming-reminders"
}

public enum WidgetSnapshotError: Error, Sendable, Equatable {
    case invalidDate
    case eventsNotInCanonicalOrder
    case duplicateEvent
    case tooManyEvents
    case invalidContentRevision
}

public struct WidgetReminderEvent: Codable, Sendable, Equatable, Hashable {
    public let reminderID: UUID
    public let title: String
    public let fireDate: Date

    public init(reminderID: UUID, title: String, fireDate: Date) {
        self.reminderID = reminderID
        self.title = title
        self.fireDate = fireDate
    }
}

public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let isTruncated: Bool
    public let contentRevision: String
    public let events: [WidgetReminderEvent]

    public init(generatedAt: Date, isTruncated: Bool, events: [WidgetReminderEvent]) throws {
        try self.init(
            schemaVersion: WidgetSnapshotConstants.schemaVersion,
            generatedAt: generatedAt,
            isTruncated: isTruncated,
            contentRevision: nil,
            events: events
        )
    }

    private init(
        schemaVersion: Int,
        generatedAt: Date,
        isTruncated: Bool,
        contentRevision: String?,
        events: [WidgetReminderEvent]
    ) throws {
        try Self.validate(generatedAt: generatedAt, events: events)
        let revision: String
        if let contentRevision {
            revision = contentRevision
        } else {
            revision = try Self.contentRevision(
                schemaVersion: schemaVersion,
                isTruncated: isTruncated,
                events: events
            )
        }
        guard Self.isCanonicalDigest(revision) else {
            throw WidgetSnapshotError.invalidContentRevision
        }

        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.isTruncated = isTruncated
        self.contentRevision = revision
        self.events = events
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generatedAt
        case isTruncated
        case contentRevision
        case events
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            generatedAt: try container.decode(Date.self, forKey: .generatedAt),
            isTruncated: try container.decode(Bool.self, forKey: .isTruncated),
            contentRevision: try container.decode(String.self, forKey: .contentRevision),
            events: try container.decode([WidgetReminderEvent].self, forKey: .events)
        )
    }

    static func contentRevision(
        schemaVersion: Int,
        isTruncated: Bool,
        events: [WidgetReminderEvent]
    ) throws -> String {
        let payload = CanonicalPayload(
            schemaVersion: schemaVersion,
            isTruncated: isTruncated,
            events: events.map(CanonicalEvent.init)
        )
        let data = try WidgetSnapshotJSON.makeEncoder().encode(payload)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func isCanonicalDigest(_ value: String) -> Bool {
        value.utf8.count == 64
            && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static func validate(generatedAt: Date, events: [WidgetReminderEvent]) throws {
        guard generatedAt.timeIntervalSinceReferenceDate.isFinite,
            events.allSatisfy({ $0.fireDate.timeIntervalSinceReferenceDate.isFinite })
        else {
            throw WidgetSnapshotError.invalidDate
        }
        guard events.count <= WidgetSnapshotConstants.maximumEventCount else {
            throw WidgetSnapshotError.tooManyEvents
        }
        guard events == events.sorted(by: canonicalOrder) else {
            throw WidgetSnapshotError.eventsNotInCanonicalOrder
        }
        var seen = Set<EventKey>()
        for event in events {
            guard
                seen.insert(EventKey(reminderID: event.reminderID, fireDate: event.fireDate))
                    .inserted
            else {
                throw WidgetSnapshotError.duplicateEvent
            }
        }
    }

    private static func canonicalOrder(_ lhs: WidgetReminderEvent, _ rhs: WidgetReminderEvent)
        -> Bool
    {
        if lhs.fireDate != rhs.fireDate {
            return lhs.fireDate < rhs.fireDate
        }
        return lhs.reminderID.uuidString.lowercased() < rhs.reminderID.uuidString.lowercased()
    }
}

private struct EventKey: Hashable {
    let reminderID: UUID
    let fireDate: Date
}

private struct CanonicalPayload: Encodable {
    let schemaVersion: Int
    let isTruncated: Bool
    let events: [CanonicalEvent]
}

private struct CanonicalEvent: Encodable {
    let reminderID: String
    let title: String
    let fireDate: Date

    init(_ event: WidgetReminderEvent) {
        reminderID = event.reminderID.uuidString.lowercased()
        title = event.title
        fireDate = event.fireDate
    }
}

enum WidgetSnapshotJSON {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso8601String(from: date))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = iso8601Date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Invalid ISO-8601 date")
            }
            return date
        }
        return decoder
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func iso8601Date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
