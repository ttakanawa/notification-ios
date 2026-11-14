import Foundation

public struct DisplayTemplate: Codable, Equatable, Sendable {
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public struct DisplayCustomization: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var notification: DisplayTemplate?
    public var liveActivity: DisplayTemplate?

    public init(
        schemaVersion: Int = 1,
        notification: DisplayTemplate? = nil,
        liveActivity: DisplayTemplate? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.notification = notification
        self.liveActivity = liveActivity
    }

    /// Unsupported or corrupt data must remain opaque in persistence, never be replaced by this result.
    public static func decodeSupported(_ data: Data?) -> DisplayCustomization? {
        guard let data, let value = try? JSONDecoder().decode(Self.self, from: data),
            value.schemaVersion == 1
        else { return nil }
        return value
    }
}
