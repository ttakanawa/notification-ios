import Dispatch
import Foundation
import Testing

@testable import NotificationManagerWidgetSupport

@Suite("WidgetSnapshotFileStore")
struct WidgetSnapshotFileStoreTests {
    @Test func missingFileIsClassifiedAsMissing() throws {
        let testDirectory = try makeWidgetSnapshotStoreTestDirectory()
        defer { removeWidgetSnapshotStoreTestDirectory(testDirectory) }
        let store = WidgetSnapshotFileStore(
            fileURL: testDirectory.appendingPathComponent("snapshot.json")
        )

        #expect(store.read() == .missing)
    }

    @Test func validFileIsAvailable() throws {
        let testDirectory = try makeWidgetSnapshotStoreTestDirectory()
        defer { removeWidgetSnapshotStoreTestDirectory(testDirectory) }
        let store = WidgetSnapshotFileStore(
            fileURL: testDirectory.appendingPathComponent("snapshot.json")
        )
        let snapshot = try makeWidgetSnapshotStoreSnapshot(title: "First")

        _ = try store.write(snapshot)

        #expect(store.read() == .available(snapshot))
    }

    @Test func inaccessibleFileIsClassifiedAsInvalid() throws {
        let fileManager = FileManager.default
        let testDirectory = try makeWidgetSnapshotStoreTestDirectory()
        defer {
            try? fileManager.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: testDirectory.path
            )
            removeWidgetSnapshotStoreTestDirectory(testDirectory)
        }
        let fileURL = testDirectory.appendingPathComponent("snapshot.json")
        let store = WidgetSnapshotFileStore(fileURL: fileURL)
        let snapshot = try makeWidgetSnapshotStoreSnapshot(title: "Private")

        _ = try store.write(snapshot)
        try fileManager.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: testDirectory.path
        )

        do {
            _ = try Data(contentsOf: fileURL)
            Issue.record("Expected an inaccessible snapshot file to fail reading")
        } catch let error as CocoaError {
            #expect(error.code == .fileReadNoPermission)
        }
        #expect(store.read() == .invalid)
    }

    @Test func corruptFileIsClassifiedAsInvalid() throws {
        let testDirectory = try makeWidgetSnapshotStoreTestDirectory()
        defer { removeWidgetSnapshotStoreTestDirectory(testDirectory) }
        let fileURL = testDirectory.appendingPathComponent("snapshot.json")
        let store = WidgetSnapshotFileStore(fileURL: fileURL)

        try Data("not a snapshot".utf8).write(to: fileURL)

        #expect(store.read() == .invalid)
    }

    @Test func writeReportsSemanticChanges() throws {
        let testDirectory = try makeWidgetSnapshotStoreTestDirectory()
        defer { removeWidgetSnapshotStoreTestDirectory(testDirectory) }
        let store = WidgetSnapshotFileStore(
            fileURL: testDirectory.appendingPathComponent("snapshot.json")
        )
        let first = try makeWidgetSnapshotStoreSnapshot(
            title: "First", generatedAt: Date(timeIntervalSince1970: 1_788_170_400)
        )
        let refreshed = try makeWidgetSnapshotStoreSnapshot(
            title: "First", generatedAt: Date(timeIntervalSince1970: 1_788_170_460)
        )
        let changed = try makeWidgetSnapshotStoreSnapshot(
            title: "Second", generatedAt: Date(timeIntervalSince1970: 1_788_170_520)
        )

        #expect(try store.write(first) == .changed)
        #expect(try store.write(refreshed) == .unchanged)
        #expect(store.read() == .available(first))
        #expect(try store.write(changed) == .changed)
        #expect(store.read() == .available(changed))
    }

    @Test func failedWritePreservesPreviousValidSnapshot() throws {
        let fileManager = FileManager.default
        let testDirectory = try makeWidgetSnapshotStoreTestDirectory()
        defer {
            try? fileManager.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: testDirectory.path
            )
            removeWidgetSnapshotStoreTestDirectory(testDirectory)
        }
        let store = WidgetSnapshotFileStore(
            fileURL: testDirectory.appendingPathComponent("snapshot.json")
        )
        let oldSnapshot = try makeWidgetSnapshotStoreSnapshot(title: "Old")
        let newSnapshot = try makeWidgetSnapshotStoreSnapshot(title: "New")

        _ = try store.write(oldSnapshot)
        try fileManager.setAttributes(
            [.posixPermissions: 0o500], ofItemAtPath: testDirectory.path
        )

        #expect(throws: (any Error).self) {
            try store.write(newSnapshot)
        }
        #expect(store.read() == .available(oldSnapshot))
    }

    @Test func atomicReplacementKeepsEveryReadAsACompleteSnapshot() throws {
        let testDirectory = try makeWidgetSnapshotStoreTestDirectory()
        defer { removeWidgetSnapshotStoreTestDirectory(testDirectory) }
        let store = WidgetSnapshotFileStore(
            fileURL: testDirectory.appendingPathComponent("snapshot.json")
        )
        let oldSnapshot = try makeLargeWidgetSnapshotStoreSnapshot(titleSeed: "old")
        let newSnapshot = try makeLargeWidgetSnapshotStoreSnapshot(titleSeed: "new")
        let finished = DispatchSemaphore(value: 0)
        let writerFailure = WidgetSnapshotStoreWriterFailure()

        _ = try store.write(oldSnapshot)
        DispatchQueue.global(qos: .userInitiated).async {
            defer { finished.signal() }
            do {
                for _ in 0..<20 {
                    _ = try store.write(newSnapshot)
                    _ = try store.write(oldSnapshot)
                }
                _ = try store.write(newSnapshot)
            } catch {
                writerFailure.record()
            }
        }

        var successfulReadCount = 0
        var sawUnavailableRead = false
        var sawUnexpectedSnapshot = false
        while finished.wait(timeout: .now()) == .timedOut {
            switch store.read() {
            case .available(let snapshot):
                successfulReadCount += 1
                if snapshot != oldSnapshot && snapshot != newSnapshot {
                    sawUnexpectedSnapshot = true
                }
            case .missing, .invalid:
                sawUnavailableRead = true
            }
        }

        #expect(!writerFailure.occurred)
        #expect(successfulReadCount > 0)
        #expect(!sawUnavailableRead)
        #expect(!sawUnexpectedSnapshot)
        #expect(store.read() == .available(newSnapshot))
    }
}

private final class WidgetSnapshotStoreWriterFailure: @unchecked Sendable {
    private let lock = NSLock()
    private var didOccur = false

    var occurred: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didOccur
    }

    func record() {
        lock.lock()
        didOccur = true
        lock.unlock()
    }
}

private func makeWidgetSnapshotStoreTestDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "WidgetSnapshotFileStoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true
    )
    return directory
}

private func removeWidgetSnapshotStoreTestDirectory(_ directory: URL) {
    try? FileManager.default.removeItem(at: directory)
}

private func makeWidgetSnapshotStoreSnapshot(
    title: String,
    generatedAt: Date = Date(timeIntervalSince1970: 1_788_170_400)
) throws -> WidgetSnapshot {
    try WidgetSnapshot(
        generatedAt: generatedAt,
        isTruncated: false,
        events: [
            WidgetReminderEvent(
                reminderID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
                title: title,
                fireDate: Date(timeIntervalSince1970: 1_788_256_800)
            )
        ]
    )
}

private func makeLargeWidgetSnapshotStoreSnapshot(titleSeed: String) throws -> WidgetSnapshot {
    let title = String(repeating: titleSeed, count: 20_000)
    let events = try (1...WidgetSnapshotConstants.maximumEventCount).map { index in
        guard
            let reminderID = UUID(
                uuidString: String(format: "00000000-0000-0000-0000-%012d", index)
            )
        else {
            throw WidgetSnapshotStoreTestError.invalidFixtureID
        }
        return WidgetReminderEvent(
            reminderID: reminderID,
            title: "\(index)-\(title)",
            fireDate: Date(timeIntervalSince1970: 1_788_256_800 + Double(index))
        )
    }
    return try WidgetSnapshot(
        generatedAt: Date(timeIntervalSince1970: 1_788_170_400),
        isTruncated: false,
        events: events
    )
}

private enum WidgetSnapshotStoreTestError: Error {
    case invalidFixtureID
}
