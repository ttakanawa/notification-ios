import Foundation

#if os(iOS) && canImport(DeviceCheck)
    @preconcurrency import DeviceCheck

    public actor SystemLiveActivityAppAttester: LiveActivityAppAttesting {
        public init() {}

        public var isSupported: Bool { DCAppAttestService.shared.isSupported }

        public func generateKey() async throws -> String {
            try await DCAppAttestService.shared.generateKey()
        }

        public func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
            do {
                return try await DCAppAttestService.shared.attestKey(
                    keyID, clientDataHash: clientDataHash)
            } catch let error as DCError where error.code == .invalidKey {
                throw LiveActivityEndAPIError.invalidAttestationKey
            }
        }

        public func assertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
            try await DCAppAttestService.shared.generateAssertion(
                keyID, clientDataHash: clientDataHash)
        }
    }
#endif

public actor FileLiveActivityEndCredentialStore: LiveActivityEndCredentialStoring {
    private let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> LiveActivityEndAPICredentials {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return LiveActivityEndAPICredentials()
        }
        // A damaged or temporarily protected file must not silently reset ownership.
        return try JSONDecoder().decode(
            LiveActivityEndAPICredentials.self, from: Data(contentsOf: url))
    }

    public func save(_ credentials: LiveActivityEndAPICredentials) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(credentials)
        #if os(iOS)
            try data.write(
                to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
            try data.write(to: url, options: .atomic)
        #endif
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var location = url
        try location.setResourceValues(values)
    }
}
