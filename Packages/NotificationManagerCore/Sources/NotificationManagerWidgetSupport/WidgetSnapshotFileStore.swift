import Foundation

public enum WidgetSnapshotReadResult: Sendable, Equatable {
    case missing
    case available(WidgetSnapshot)
    case invalid
}

public enum WidgetSnapshotWriteResult: Sendable, Equatable {
    case unchanged
    case changed
}

public struct WidgetSnapshotFileStore: Sendable {
    private let fileURL: URL
    private let codec: WidgetSnapshotCodec

    public init(fileURL: URL, codec: WidgetSnapshotCodec = .init()) {
        self.fileURL = fileURL
        self.codec = codec
    }

    public static func live(
        fileManager: FileManager = .default
    ) -> WidgetSnapshotFileStore? {
        guard
            let containerURL = fileManager.containerURL(
                forSecurityApplicationGroupIdentifier: WidgetSnapshotConstants.appGroupIdentifier
            )
        else {
            return nil
        }
        return WidgetSnapshotFileStore(
            fileURL: containerURL.appendingPathComponent(WidgetSnapshotConstants.fileName)
        )
    }

    public func read() -> WidgetSnapshotReadResult {
        do {
            return .available(try codec.decode(Data(contentsOf: fileURL)))
        } catch {
            let cocoaError = error as NSError
            guard
                cocoaError.domain == NSCocoaErrorDomain,
                cocoaError.code == CocoaError.Code.fileReadNoSuchFile.rawValue
            else {
                return .invalid
            }
            return .missing
        }
    }

    public func write(_ snapshot: WidgetSnapshot) throws -> WidgetSnapshotWriteResult {
        if case .available(let storedSnapshot) = read(),
            storedSnapshot.contentRevision == snapshot.contentRevision
        {
            return .unchanged
        }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try codec.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
        return .changed
    }
}
