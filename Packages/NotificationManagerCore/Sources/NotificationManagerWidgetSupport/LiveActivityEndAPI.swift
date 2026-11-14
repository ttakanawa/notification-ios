import CryptoKit
import Foundation

public enum LiveActivityEndAPIEnvironment: String, Codable, Sendable {
    case development
    case production
}

public struct LiveActivityEndAPIConfiguration: Sendable {
    public let origin: URL
    public let environment: LiveActivityEndAPIEnvironment
    public let attestationEnvironment: LiveActivityEndAPIEnvironment

    /// Keys, assertions and job revisions belong to exactly one deployment.
    public var storageNamespace: String {
        let authority = "\(origin.host?.lowercased() ?? ""):\(origin.port ?? 443)"
        return LiveActivityEndAPISigning.hex(
            LiveActivityEndAPISigning.sha256(
                Data(
                    "https://\(authority)/\(environment.rawValue)/\(attestationEnvironment.rawValue)"
                        .utf8)))
    }

    public init(
        origin: URL, environment: LiveActivityEndAPIEnvironment,
        attestationEnvironment: LiveActivityEndAPIEnvironment? = nil
    ) throws {
        guard origin.scheme == "https", origin.host != nil,
            origin.user == nil, origin.password == nil, origin.query == nil,
            origin.fragment == nil, origin.path.isEmpty || origin.path == "/"
        else { throw LiveActivityEndAPIError.invalidConfiguration }
        self.origin = origin
        self.environment = environment
        self.attestationEnvironment = attestationEnvironment ?? environment
    }
}

public struct LiveActivityEndTiming: Codable, Equatable, Sendable {
    public let startsAt: Date
    public let notificationAt: Date
    public let endsAt: Date
    public let activityEndsAt: Date

    public init(event: ReminderLiveActivityEvent) {
        startsAt = Self.seconds(event.startDate)
        notificationAt = Self.seconds(event.notificationDate)
        endsAt = Self.seconds(event.endDate)
        activityEndsAt = Self.seconds(event.activityEndDate)
    }

    private static func seconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
    }
}

public struct LiveActivityEndAPIRequest: Codable, Equatable, Sendable {
    public enum Operation: String, Codable, Sendable {
        case put
        case token
        case cancel
        case get

        public var method: String {
            switch self {
            case .put: "PUT"
            case .token: "PATCH"
            case .cancel: "DELETE"
            case .get: "GET"
            }
        }
    }

    public let jobID: UUID
    public let revision: UInt64
    public let operation: Operation
    /// Persist these exact bytes, including across authenticated retries.
    public let body: Data

    public var path: String {
        let resource = "/v1/end-jobs/\(jobID.uuidString.lowercased())"
        return operation == .token ? resource + "/push-token" : resource
    }

    public static func put(
        jobID: UUID, revision: UInt64, token: String, timing: LiveActivityEndTiming
    ) throws -> Self {
        struct Payload: Encodable {
            let revision: String
            let pushToken: String
            let startsAt: Date
            let notificationAt: Date
            let endsAt: Date
            let activityEndsAt: Date
            let contentStateVersion = 1
        }
        return try make(
            jobID: jobID, revision: revision, operation: .put,
            payload: Payload(
                revision: String(revision), pushToken: token,
                startsAt: timing.startsAt, notificationAt: timing.notificationAt,
                endsAt: timing.endsAt, activityEndsAt: timing.activityEndsAt))
    }

    public static func token(jobID: UUID, revision: UInt64, token: String) throws -> Self {
        struct Payload: Encodable {
            let revision: String
            let pushToken: String
        }
        return try make(
            jobID: jobID, revision: revision, operation: .token,
            payload: Payload(revision: String(revision), pushToken: token))
    }

    public static func cancel(jobID: UUID, revision: UInt64) throws -> Self {
        struct Payload: Encodable { let revision: String }
        return try make(
            jobID: jobID, revision: revision, operation: .cancel,
            payload: Payload(revision: String(revision)))
    }

    public static func get(jobID: UUID) -> Self {
        Self(jobID: jobID, revision: 0, operation: .get, body: Data())
    }

    private static func make<T: Encodable>(
        jobID: UUID, revision: UInt64, operation: Operation, payload: T
    ) throws -> Self {
        guard revision > 0 else { throw LiveActivityEndAPIError.invalidRevision }
        return try Self(
            jobID: jobID, revision: revision, operation: operation,
            body: LiveActivityEndAPIJSON.encoder().encode(payload))
    }
}

public struct LiveActivityEndJobResponse: Decodable, Sendable {
    public let jobId: UUID
    public let revision: String
    public let status: String
    public let activityEndsAt: Date?
    public let delivery: Delivery

    public struct Delivery: Decodable, Sendable {
        public let state: String
        public let attemptCount: Int
        public let acceptedAt: Date?
        public let mayHaveBeenSent: Bool
    }

    public var isTerminal: Bool {
        ["apns_accepted", "cancelled", "failed", "expired"].contains(status)
    }
}

public enum LiveActivityEndAPIError: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidRevision
    case unsupportedAttestation
    case invalidAttestationKey
    case invalidResponse
    case challengeExpired
    case server(status: Int, code: String, currentRevision: UInt64?, retryAfter: TimeInterval?)
}

public enum LiveActivityEndAPIJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum LiveActivityEndAPISigning {
    public static func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }

    public static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    public static func message(
        environment: LiveActivityEndAPIEnvironment,
        keyID: String, challengeID: String, challenge: String,
        method: String, path: String, body: Data
    ) -> Data {
        let fields = [
            "punctual-api-v1", environment.rawValue, keyID, challengeID, challenge,
            method, path, hex(sha256(body))
        ]
        return Data((fields.joined(separator: "\n") + "\n").utf8)
    }
}

public protocol LiveActivityEndJobSending: Sendable {
    func send(_ request: LiveActivityEndAPIRequest) async throws -> LiveActivityEndJobResponse
}

public protocol LiveActivityAppAttesting: Sendable {
    var isSupported: Bool { get async }
    func generateKey() async throws -> String
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data
    func assertion(_ keyID: String, clientDataHash: Data) async throws -> Data
}

public struct LiveActivityEndAPICredentials: Codable, Sendable {
    public var keyID: String?
    public var installationID: UUID?
    public var registrationConfirmed = false
    public var pendingAttestation: Data?

    public init() {}
}

public protocol LiveActivityEndCredentialStoring: Sendable {
    func load() async throws -> LiveActivityEndAPICredentials
    func save(_ credentials: LiveActivityEndAPICredentials) async throws
}

public actor LiveActivityEndHTTPClient: LiveActivityEndJobSending {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private struct Challenge: Decodable {
        let challengeId: UUID
        let challenge: String
        let expiresAt: Date
    }

    private struct Registration: Decodable {
        let installationId: UUID
        let authScheme: String
    }

    private let configuration: LiveActivityEndAPIConfiguration
    private let attester: any LiveActivityAppAttesting
    private let credentials: any LiveActivityEndCredentialStoring
    private let transport: Transport
    private var sending = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(
        configuration: LiveActivityEndAPIConfiguration,
        attester: any LiveActivityAppAttesting,
        credentials: any LiveActivityEndCredentialStoring,
        transport: @escaping Transport = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw LiveActivityEndAPIError.invalidResponse
            }
            return (data, response)
        }
    ) {
        self.configuration = configuration
        self.attester = attester
        self.credentials = credentials
        self.transport = transport
    }

    public func send(_ request: LiveActivityEndAPIRequest) async throws
        -> LiveActivityEndJobResponse
    {
        await acquire()
        defer { release() }
        guard await attester.isSupported else {
            throw LiveActivityEndAPIError.unsupportedAttestation
        }
        let keyID = try await registeredKey()
        let challenge = try await challenge(purpose: "assertion", keyID: keyID)
        let message = LiveActivityEndAPISigning.message(
            environment: configuration.environment, keyID: keyID,
            challengeID: challenge.challengeId.uuidString.lowercased(),
            challenge: challenge.challenge, method: request.operation.method,
            path: request.path, body: request.body)
        let assertion = try await attester.assertion(
            keyID, clientDataHash: LiveActivityEndAPISigning.sha256(message))
        var http = httpRequest(
            path: request.path, method: request.operation.method, body: request.body)
        http.setValue(keyID, forHTTPHeaderField: "X-App-Attest-Key-Id")
        http.setValue(
            challenge.challengeId.uuidString.lowercased(),
            forHTTPHeaderField: "X-App-Attest-Challenge-Id")
        http.setValue(assertion.base64EncodedString(), forHTTPHeaderField: "X-App-Attest-Assertion")
        let data = try await perform(http)
        let result = try LiveActivityEndAPIJSON.decoder().decode(
            LiveActivityEndJobResponse.self, from: data)
        guard result.jobId == request.jobID, let revision = UInt64(result.revision), revision > 0,
            [
                "scheduled", "dispatching", "retrying", "awaiting_token", "apns_accepted",
                "cancelled", "failed", "expired"
            ]
            .contains(result.status)
        else {
            throw LiveActivityEndAPIError.invalidResponse
        }
        return result
    }

    private func registeredKey() async throws -> String {
        var saved = try await credentials.load()
        if saved.keyID == nil {
            saved.keyID = try await attester.generateKey()
            try await credentials.save(saved)
        }
        guard let keyID = saved.keyID else { throw LiveActivityEndAPIError.invalidResponse }
        if saved.registrationConfirmed || saved.installationID != nil { return keyID }

        // Registration may have succeeded just before a response was lost.
        if saved.pendingAttestation != nil {
            do {
                let data = try await perform(
                    httpRequest(
                        path: "/v1/auth/attestations", method: "POST",
                        body: saved.pendingAttestation))
                let registration = try LiveActivityEndAPIJSON.decoder().decode(
                    Registration.self, from: data)
                guard registration.authScheme == "app-attest-v1" else {
                    throw LiveActivityEndAPIError.invalidResponse
                }
                saved.installationID = registration.installationId
                saved.registrationConfirmed = true
                saved.pendingAttestation = nil
                try await credentials.save(saved)
                return keyID
            } catch {
                guard Self.isRegistrationChallengeFailure(error) else { throw error }
                do {
                    _ = try await challenge(purpose: "assertion", keyID: keyID)
                } catch {
                    guard Self.isUnregisteredKey(error) else { throw error }
                    // An expired attestation cannot be rebound to a fresh nonce.
                    // No business operation was possible before this first registration.
                    try await credentials.save(LiveActivityEndAPICredentials())
                    return try await registeredKey()
                }
                // A registered key may sign requests even if its registration response was lost.
                saved.registrationConfirmed = true
                saved.pendingAttestation = nil
                try await credentials.save(saved)
                return keyID
            }
        }

        let challenge = try await challenge(purpose: "attestation", keyID: keyID)
        guard let nonce = Data(base64Encoded: challenge.challenge), nonce.count == 32 else {
            throw LiveActivityEndAPIError.invalidResponse
        }
        let object: Data
        do {
            object = try await attester.attestKey(
                keyID, clientDataHash: LiveActivityEndAPISigning.sha256(nonce))
        } catch LiveActivityEndAPIError.invalidAttestationKey {
            // An unregistered key has never owned a business job. A key already
            // confirmed by the server is never silently reset by this path.
            try await credentials.save(LiveActivityEndAPICredentials())
            throw LiveActivityEndAPIError.invalidAttestationKey
        }
        let payload = [
            "keyId": keyID,
            "challengeId": challenge.challengeId.uuidString.lowercased(),
            "attestationObject": object.base64EncodedString()
        ]
        let body = try LiveActivityEndAPIJSON.encoder().encode(payload)
        saved.pendingAttestation = body
        try await credentials.save(saved)
        let data = try await perform(
            httpRequest(path: "/v1/auth/attestations", method: "POST", body: body))
        let registration = try LiveActivityEndAPIJSON.decoder().decode(
            Registration.self, from: data)
        guard registration.authScheme == "app-attest-v1" else {
            throw LiveActivityEndAPIError.invalidResponse
        }
        saved.installationID = registration.installationId
        saved.registrationConfirmed = true
        saved.pendingAttestation = nil
        try await credentials.save(saved)
        return keyID
    }

    private static func isRegistrationChallengeFailure(_ error: any Error) -> Bool {
        guard case LiveActivityEndAPIError.server(401, let code, _, _) = error else { return false }
        return ["CHALLENGE_EXPIRED", "CHALLENGE_REPLAYED", "CHALLENGE_USED"].contains(code)
    }

    private static func isUnregisteredKey(_ error: any Error) -> Bool {
        guard case LiveActivityEndAPIError.server(401, "KEY_NOT_REGISTERED", _, _) = error else {
            return false
        }
        return true
    }

    private func challenge(purpose: String, keyID: String) async throws -> Challenge {
        let body = try LiveActivityEndAPIJSON.encoder().encode(["purpose": purpose, "keyId": keyID])
        let data = try await perform(
            httpRequest(path: "/v1/auth/challenges", method: "POST", body: body))
        let result = try LiveActivityEndAPIJSON.decoder().decode(Challenge.self, from: data)
        guard let nonce = Data(base64Encoded: result.challenge), nonce.count == 32 else {
            throw LiveActivityEndAPIError.invalidResponse
        }
        return result
    }

    private func httpRequest(path: String, method: String, body: Data?) -> URLRequest {
        let url = configuration.origin.appending(path: path)
        var request = URLRequest(
            url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method
        request.httpBody = body?.isEmpty == true ? nil : body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await transport(request)
        guard (200..<300).contains(response.statusCode) else {
            let error = try? JSONDecoder().decode(EndAPIErrorEnvelope.self, from: data).error
            throw LiveActivityEndAPIError.server(
                status: response.statusCode, code: error?.code ?? "HTTP_ERROR",
                currentRevision: error?.details?.currentRevision.flatMap(UInt64.init),
                retryAfter: response.value(forHTTPHeaderField: "Retry-After").flatMap(
                    TimeInterval.init))
        }
        return data
    }

    private func acquire() async {
        if sending {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            sending = true
        }
    }

    private func release() {
        if waiters.isEmpty { sending = false } else { waiters.removeFirst().resume() }
    }
}

private struct EndAPIErrorEnvelope: Decodable {
    let error: EndAPIErrorDetails
}

private struct EndAPIErrorDetails: Decodable {
    let code: String
    let details: EndAPIRevisionDetails?
}

private struct EndAPIRevisionDetails: Decodable {
    let currentRevision: String?
}
