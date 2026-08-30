import Foundation

public enum WidgetSnapshotCodecError: Error, Sendable, Equatable {
    case invalidDocument
    case unsupportedSchemaVersion(Int)
    case invalidSnapshot(WidgetSnapshotError)
    case contentRevisionMismatch
}

public struct WidgetSnapshotCodec: Sendable {
    public init() {}

    public func encode(_ snapshot: WidgetSnapshot) throws -> Data {
        try WidgetSnapshotJSON.makeEncoder().encode(snapshot)
    }

    public func decode(_ data: Data) throws -> WidgetSnapshot {
        let version: Int
        do {
            version = try JSONDecoder().decode(SchemaVersionEnvelope.self, from: data).schemaVersion
        } catch {
            throw WidgetSnapshotCodecError.invalidDocument
        }
        guard version == WidgetSnapshotConstants.schemaVersion else {
            throw WidgetSnapshotCodecError.unsupportedSchemaVersion(version)
        }

        let snapshot: WidgetSnapshot
        do {
            snapshot = try WidgetSnapshotJSON.makeDecoder().decode(WidgetSnapshot.self, from: data)
        } catch let error as WidgetSnapshotError {
            throw WidgetSnapshotCodecError.invalidSnapshot(error)
        } catch {
            throw WidgetSnapshotCodecError.invalidDocument
        }

        let expectedRevision: String
        do {
            expectedRevision = try WidgetSnapshot.contentRevision(
                schemaVersion: snapshot.schemaVersion,
                isTruncated: snapshot.isTruncated,
                events: snapshot.events
            )
        } catch {
            throw WidgetSnapshotCodecError.invalidDocument
        }
        guard snapshot.contentRevision == expectedRevision else {
            throw WidgetSnapshotCodecError.contentRevisionMismatch
        }
        return snapshot
    }
}

private struct SchemaVersionEnvelope: Decodable {
    let schemaVersion: Int
}
