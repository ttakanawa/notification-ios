import Foundation
import Testing

@testable import NotificationManagerWidgetSupport

@Suite("WidgetSnapshotCodec")
struct WidgetSnapshotCodecTests {
    @Test func roundTripPreservesCanonicalSnapshot() throws {
        let event = WidgetReminderEvent(
            reminderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            title: "Renew passport",
            fireDate: Date(timeIntervalSince1970: 1_788_256_800)
        )
        let snapshot = try WidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_788_170_400),
            isTruncated: false,
            events: [event]
        )

        let data = try WidgetSnapshotCodec().encode(snapshot)

        #expect(try WidgetSnapshotCodec().decode(data) == snapshot)
    }

    @Test func snapshotRejectsEventsOutOfCanonicalOrder() {
        let later = makeEvent(
            id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", fireDate: "2026-09-01T11:00:00Z")
        let earlier = makeEvent(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", fireDate: "2026-09-01T10:00:00Z")

        #expect(throws: WidgetSnapshotError.eventsNotInCanonicalOrder) {
            _ = try WidgetSnapshot(
                generatedAt: date("2026-09-01T09:00:00Z"), isTruncated: false,
                events: [later, earlier])
        }
    }

    @Test func snapshotRejectsDuplicatePhysicalEvents() {
        let event = makeEvent(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", fireDate: "2026-09-01T10:00:00Z")

        #expect(throws: WidgetSnapshotError.duplicateEvent) {
            _ = try WidgetSnapshot(
                generatedAt: date("2026-09-01T09:00:00Z"), isTruncated: false,
                events: [event, event])
        }
    }

    @Test func snapshotRejectsNonfiniteDates() {
        let event = WidgetReminderEvent(
            reminderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            title: "Renew passport",
            fireDate: Date(timeIntervalSince1970: .infinity)
        )

        #expect(throws: WidgetSnapshotError.invalidDate) {
            _ = try WidgetSnapshot(
                generatedAt: date("2026-09-01T09:00:00Z"), isTruncated: false, events: [event])
        }
    }

    @Test func snapshotRejectsNonfiniteGeneratedAtDate() {
        #expect(throws: WidgetSnapshotError.invalidDate) {
            _ = try WidgetSnapshot(
                generatedAt: Date(timeIntervalSince1970: .infinity),
                isTruncated: false,
                events: []
            )
        }
    }

    @Test func contentRevisionExcludesGeneratedAt() throws {
        let event = makeEvent(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            fireDate: "2026-09-01T10:00:00Z"
        )

        let first = try WidgetSnapshot(
            generatedAt: date("2026-09-01T09:00:00Z"),
            isTruncated: false,
            events: [event]
        )
        let second = try WidgetSnapshot(
            generatedAt: date("2026-09-01T09:01:00Z"),
            isTruncated: false,
            events: [event]
        )

        #expect(first.contentRevision == second.contentRevision)
    }

    @Test func decoderRejectsMalformedDate() {
        let data = Data(
            #"{"contentRevision":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","events":[],"generatedAt":"not-a-date","isTruncated":false,"schemaVersion":1}"#
                .utf8
        )

        #expect(throws: WidgetSnapshotCodecError.invalidDocument) {
            try WidgetSnapshotCodec().decode(data)
        }
    }

    @Test func decoderRejectsMismatchedDigest() {
        let data = Data(
            #"{"contentRevision":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","events":[],"generatedAt":"2026-09-01T00:00:00.000Z","isTruncated":false,"schemaVersion":1}"#
                .utf8
        )

        #expect(throws: WidgetSnapshotCodecError.contentRevisionMismatch) {
            try WidgetSnapshotCodec().decode(data)
        }
    }

    @Test func decoderRejectsUnknownSchemaVersion() {
        let data = Data(
            """
            {"schemaVersion":2,"generatedAt":"2026-09-01T00:00:00Z",
             "isTruncated":false,"contentRevision":"invalid","events":[]}
            """.utf8
        )

        #expect(throws: WidgetSnapshotCodecError.unsupportedSchemaVersion(2)) {
            try WidgetSnapshotCodec().decode(data)
        }
    }
}

func date(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let parsed = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    else {
        fatalError("Invalid test date: \(value)")
    }
    return parsed
}

func makeEvent(id: String, fireDate: String) -> WidgetReminderEvent {
    guard let reminderID = UUID(uuidString: id) else {
        fatalError("Invalid test reminder ID: \(id)")
    }
    return WidgetReminderEvent(
        reminderID: reminderID,
        title: "Reminder \(id)",
        fireDate: date(fireDate)
    )
}
