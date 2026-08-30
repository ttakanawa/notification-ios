import Foundation
import NotificationManagerWidgetSupport
import Testing

@testable import NotificationManager

@Suite("WidgetSnapshotPublisher")
struct WidgetSnapshotPublisherTests {
    @Test func staleGenerationCannotReplaceAnewerSnapshot() async throws {
        let directory = try makePublisherTestDirectory()
        defer { removePublisherTestDirectory(directory) }
        let store = WidgetSnapshotFileStore(
            fileURL: directory.appendingPathComponent("snapshot.json")
        )
        let reloads = WidgetReloadRecorder()
        let publisher = WidgetSnapshotPublisher(store: store) {
            reloads.record()
        }
        let newer = try makePublisherSnapshot(title: "Newer")
        let stale = try makePublisherSnapshot(title: "Stale")

        await publisher.publish(newer, generation: 2)
        await publisher.publish(stale, generation: 1)

        #expect(store.read() == .available(newer))
        #expect(reloads.count == 1)
    }

    @Test func unchangedRevisionDoesNotReloadOrReplaceStoredGenerationTime() async throws {
        let directory = try makePublisherTestDirectory()
        defer { removePublisherTestDirectory(directory) }
        let store = WidgetSnapshotFileStore(
            fileURL: directory.appendingPathComponent("snapshot.json")
        )
        let stored = try makePublisherSnapshot(
            title: "Same",
            generatedAt: Date(timeIntervalSince1970: 1_788_170_400)
        )
        let refreshed = try makePublisherSnapshot(
            title: "Same",
            generatedAt: Date(timeIntervalSince1970: 1_788_170_460)
        )
        _ = try store.write(stored)
        let reloads = WidgetReloadRecorder()
        let publisher = WidgetSnapshotPublisher(store: store) {
            reloads.record()
        }

        await publisher.publish(refreshed, generation: 1)

        #expect(store.read() == .available(stored))
        #expect(reloads.isEmpty)
    }

    @Test func changedSnapshotWritesThenReloadsOnce() async throws {
        let directory = try makePublisherTestDirectory()
        defer { removePublisherTestDirectory(directory) }
        let store = WidgetSnapshotFileStore(
            fileURL: directory.appendingPathComponent("snapshot.json")
        )
        let reloads = WidgetReloadRecorder()
        let publisher = WidgetSnapshotPublisher(store: store) {
            reloads.record()
        }
        let snapshot = try makePublisherSnapshot(title: "Changed")

        await publisher.publish(snapshot, generation: 1)
        await publisher.publish(snapshot, generation: 2)

        #expect(store.read() == .available(snapshot))
        #expect(reloads.count == 1)
    }

    @Test func transitionToEmptySnapshotWritesThenReloadsOnce() async throws {
        let directory = try makePublisherTestDirectory()
        defer { removePublisherTestDirectory(directory) }
        let store = WidgetSnapshotFileStore(
            fileURL: directory.appendingPathComponent("snapshot.json")
        )
        let oldSnapshot = try makePublisherSnapshot(title: "Old")
        _ = try store.write(oldSnapshot)
        let reloads = WidgetReloadRecorder()
        let publisher = WidgetSnapshotPublisher(store: store) {
            reloads.record()
        }
        let empty = try WidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_788_170_460),
            isTruncated: false,
            events: []
        )

        await publisher.publish(empty, generation: 1)

        #expect(store.read() == .available(empty))
        #expect(reloads.count == 1)
    }

    @Test func failedWritePreservesOldSnapshotAndDoesNotReload() async throws {
        let fileManager = FileManager.default
        let directory = try makePublisherTestDirectory()
        defer {
            try? fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
            removePublisherTestDirectory(directory)
        }
        let store = WidgetSnapshotFileStore(
            fileURL: directory.appendingPathComponent("snapshot.json")
        )
        let oldSnapshot = try makePublisherSnapshot(title: "Old")
        let newSnapshot = try makePublisherSnapshot(title: "New")
        _ = try store.write(oldSnapshot)
        try fileManager.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: directory.path
        )
        let reloads = WidgetReloadRecorder()
        let publisher = WidgetSnapshotPublisher(store: store) {
            reloads.record()
        }

        await publisher.publish(newSnapshot, generation: 1)

        #expect(store.read() == .available(oldSnapshot))
        #expect(reloads.isEmpty)
    }
}

private final class WidgetReloadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0

    var count: Int {
        lock.withLock { storedCount }
    }

    var isEmpty: Bool {
        lock.withLock { storedCount == 0 }
    }

    func record() {
        lock.withLock { storedCount += 1 }
    }
}

private func makePublisherTestDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "WidgetSnapshotPublisherTests-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return directory
}

private func removePublisherTestDirectory(_ directory: URL) {
    try? FileManager.default.removeItem(at: directory)
}

private func makePublisherSnapshot(
    title: String,
    generatedAt: Date = Date(timeIntervalSince1970: 1_788_170_400)
) throws -> WidgetSnapshot {
    guard let reminderID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa") else {
        preconditionFailure("Invalid publisher fixture UUID")
    }
    return try WidgetSnapshot(
        generatedAt: generatedAt,
        isTruncated: false,
        events: [
            WidgetReminderEvent(
                reminderID: reminderID,
                title: title,
                fireDate: Date(timeIntervalSince1970: 1_788_256_800)
            )
        ]
    )
}
