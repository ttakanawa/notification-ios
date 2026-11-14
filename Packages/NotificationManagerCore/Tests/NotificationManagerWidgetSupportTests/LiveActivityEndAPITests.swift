import Foundation
import Testing

@testable import NotificationManagerWidgetSupport

struct LiveActivityEndAPITests {
    private let jobID = UUID(uuidString: "8f5b583d-c03a-4c35-9ad7-6c18cda0c063")!
    private let now = Date(timeIntervalSince1970: 1_794_816_000)

    @Test func credentialsAndOutboxAreScopedToOriginAndAttestationEnvironment() throws {
        let first = try LiveActivityEndAPIConfiguration(
            origin: URL(string: "https://example.invalid")!, environment: .development)
        let equivalent = try LiveActivityEndAPIConfiguration(
            origin: URL(string: "https://EXAMPLE.invalid:443/")!, environment: .development)
        let production = try LiveActivityEndAPIConfiguration(
            origin: first.origin, environment: .production)
        let stagingTestFlight = try LiveActivityEndAPIConfiguration(
            origin: first.origin, environment: .development, attestationEnvironment: .production)
        let other = try LiveActivityEndAPIConfiguration(
            origin: URL(string: "https://other.invalid")!, environment: .development)
        #expect(first.storageNamespace == equivalent.storageNamespace)
        #expect(first.storageNamespace != production.storageNamespace)
        #expect(first.storageNamespace != stagingTestFlight.storageNamespace)
        #expect(first.storageNamespace != other.storageNamespace)
    }

    @Test func sharedRustSigningVectorMatchesExactly() throws {
        let vector = try fixture("signing-v1")
        let rawBody = try #require(vector["rawBody"] as? String)
        let message = LiveActivityEndAPISigning.message(
            environment: .development,
            keyID: try #require(vector["keyId"] as? String),
            challengeID: try #require(vector["challengeId"] as? String),
            challenge: try #require(vector["challenge"] as? String),
            method: "PUT", path: try #require(vector["path"] as? String),
            body: Data(rawBody.utf8))

        #expect(String(data: message, encoding: .utf8) == vector["signingMessage"] as? String)
        #expect(
            LiveActivityEndAPISigning.hex(LiveActivityEndAPISigning.sha256(message))
                == vector["clientDataHashHex"] as? String)
        #expect(
            LiveActivityEndAPISigning.hex(LiveActivityEndAPISigning.sha256(Data()))
                == vector["emptyBodySHA256Hex"] as? String)
    }

    @Test func scheduleEncodingMatchesTheSharedFixtureWithoutUserContent() throws {
        let vector = try fixture("signing-v1")
        let end = try fixture("end-content-state-v1")
        let input = try #require(end["request"] as? [String: Any])
        func date(_ name: String) throws -> Date {
            let value = try #require(input[name] as? String)
            return try #require(ISO8601DateFormatter().date(from: value))
        }
        let event = ReminderLiveActivityEvent(
            reminderID: UUID(), title: "Private title", startDate: try date("startsAt"),
            endDate: try date("endsAt"), notificationDate: try date("notificationAt"))
        let request = try LiveActivityEndAPIRequest.put(
            jobID: jobID, revision: 12,
            token: try #require(input["pushToken"] as? String),
            timing: LiveActivityEndTiming(event: event))

        #expect(String(data: request.body, encoding: .utf8) == vector["rawBody"] as? String)
        #expect(String(data: request.body, encoding: .utf8)?.contains("Private title") == false)
        #expect(request.path == "/v1/end-jobs/\(jobID.uuidString.lowercased())")
        let restored = try JSONDecoder().decode(
            LiveActivityEndAPIRequest.self, from: JSONEncoder().encode(request))
        #expect(restored.body == request.body)
    }

    @Test func queryAndCredentialBearingOriginsAreRejected() {
        for value in [
            "http://example.invalid", "https://user:password@example.invalid",
            "https://example.invalid/v1", "https://example.invalid?token=secret"
        ] {
            #expect(throws: LiveActivityEndAPIError.self) {
                try LiveActivityEndAPIConfiguration(
                    origin: try #require(URL(string: value)), environment: .production)
            }
        }
    }

    @Test func unsupportedAttestationNeverSendsAnUnauthenticatedRequest() async throws {
        let context = try makeContext(supported: false)
        await #expect(throws: LiveActivityEndAPIError.unsupportedAttestation) {
            _ = try await context.client.send(.get(jobID: jobID))
        }
        #expect(await context.server.requestCount == 0)
    }

    @Test func invalidInitialAttestationKeyCanRecoverBeforeAnyJobWasRegistered() async throws {
        let context = try makeContext()
        await context.attester.rejectNextAttestation()
        await #expect(throws: LiveActivityEndAPIError.invalidAttestationKey) {
            _ = try await context.client.send(.get(jobID: jobID))
        }
        #expect(await context.credentials.load().keyID == nil)
        _ = try await context.client.send(.get(jobID: jobID))
        #expect(await context.attester.generatedKeys == 2)
        #expect(await context.credentials.load().registrationConfirmed)
    }

    @Test func invalidRegisteredAssertionNeverSilentlyResetsOwnership() async throws {
        let context = try makeContext()
        _ = try await context.client.send(.get(jobID: jobID))
        await context.attester.rejectNextAssertion()
        await #expect(throws: LiveActivityEndAPIError.invalidAttestationKey) {
            _ = try await context.client.send(.get(jobID: jobID))
        }
        #expect(await context.credentials.load().registrationConfirmed)
        #expect(await context.attester.generatedKeys == 1)
    }

    @Test func registrationResponseLossReusesThePersistedAttestation() async throws {
        let context = try makeContext()
        await context.server.loseNextRegistrationResponse()
        await #expect(throws: URLError.self) {
            _ = try await context.client.send(.get(jobID: jobID))
        }
        let pending = try #require(await context.credentials.load().pendingAttestation)

        let result = try await context.client.send(.get(jobID: jobID))

        #expect(result.jobId == jobID)
        let bodies = await context.server.registrationBodies
        #expect(bodies == [pending, pending])
        #expect(await context.attester.generatedKeys == 1)
        #expect(await context.attester.attestations == 1)
        #expect(await context.credentials.load().registrationConfirmed)
    }

    @Test func concurrentSendsAreSerializedAndUseFreshChallenges() async throws {
        let context = try makeContext()
        let request = try LiveActivityEndAPIRequest.cancel(jobID: jobID, revision: 2)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                group.addTask { _ = try await context.client.send(request) }
            }
            try await group.waitForAll()
        }

        #expect(await context.attester.maximumConcurrentAssertions == 1)
        let business = await context.server.businessRequests
        #expect(business.count == 3)
        #expect(
            Set(business.compactMap { $0.value(forHTTPHeaderField: "X-App-Attest-Challenge-Id") })
                .count == 3)
        #expect(business.allSatisfy { $0.httpBody == request.body })
        #expect(
            business.allSatisfy { $0.value(forHTTPHeaderField: "X-App-Attest-Assertion") != nil })
    }

    @Test func structuredRevisionConflictIsReturnedWithoutChangingTheRequest() async throws {
        let context = try makeContext()
        await context.server.rejectBusinessWithConflict()
        let request = try LiveActivityEndAPIRequest.cancel(jobID: jobID, revision: 2)

        await #expect(
            throws: LiveActivityEndAPIError.server(
                status: 409, code: "STALE_REVISION", currentRevision: 17, retryAfter: nil)
        ) {
            _ = try await context.client.send(request)
        }
        #expect(await context.server.businessRequests.first?.httpBody == request.body)
    }

    @Test func sharedServerConflictBodiesPreserveTheFullUInt64Revision() async throws {
        let vector = try fixture("revision-errors-v1")
        let cases = try #require(vector["cases"] as? [[String: Any]])
        for sample in cases {
            let body = try #require(sample["response"] as? [String: Any])
            let error = try #require(body["error"] as? [String: Any])
            let code = try #require(error["code"] as? String)
            let revisionText = try #require(sample["currentRevision"] as? String)
            let revision = try #require(UInt64(revisionText))
            let context = try makeContext()
            await context.server.rejectBusiness(
                with: try JSONSerialization.data(withJSONObject: body))
            await #expect(
                throws: LiveActivityEndAPIError.server(
                    status: 409, code: code, currentRevision: revision, retryAfter: nil)
            ) {
                _ = try await context.client.send(.get(jobID: jobID))
            }
        }
    }

    private func fixture(_ name: String) throws -> [String: Any] {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func makeContext(supported: Bool = true) throws -> EndAPIContext {
        let server = EndAPITestServer(jobID: jobID, now: now)
        let attester = EndAPITestAttester(supported: supported)
        let credentials = EndAPITestCredentials()
        let client = try LiveActivityEndHTTPClient(
            configuration: LiveActivityEndAPIConfiguration(
                origin: URL(string: "https://example.invalid")!, environment: .development),
            attester: attester, credentials: credentials,
            transport: { try await server.respond(to: $0) })
        return EndAPIContext(
            client: client, server: server, attester: attester, credentials: credentials)
    }
}

private struct EndAPIContext {
    let client: LiveActivityEndHTTPClient
    let server: EndAPITestServer
    let attester: EndAPITestAttester
    let credentials: EndAPITestCredentials
}

private actor EndAPITestCredentials: LiveActivityEndCredentialStoring {
    private var value = LiveActivityEndAPICredentials()
    func load() -> LiveActivityEndAPICredentials { value }
    func save(_ value: LiveActivityEndAPICredentials) { self.value = value }
}

private actor EndAPITestAttester: LiveActivityAppAttesting {
    private var rejectsAttestation = false
    private var rejectsAssertion = false

    func rejectNextAttestation() { rejectsAttestation = true }
    func rejectNextAssertion() { rejectsAssertion = true }
    let isSupported: Bool
    private(set) var generatedKeys = 0
    private(set) var attestations = 0
    private(set) var maximumConcurrentAssertions = 0
    private var concurrentAssertions = 0

    init(supported: Bool) { isSupported = supported }

    func generateKey() -> String {
        generatedKeys += 1
        return Data(repeating: 1, count: 32).base64EncodedString()
    }

    func attestKey(_ keyID: String, clientDataHash: Data) throws -> Data {
        attestations += 1
        if rejectsAttestation {
            rejectsAttestation = false
            throw LiveActivityEndAPIError.invalidAttestationKey
        }
        return Data([1, 2, 3])
    }

    func assertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        if rejectsAssertion {
            rejectsAssertion = false
            throw LiveActivityEndAPIError.invalidAttestationKey
        }
        concurrentAssertions += 1
        maximumConcurrentAssertions = max(maximumConcurrentAssertions, concurrentAssertions)
        defer { concurrentAssertions -= 1 }
        try await Task.sleep(for: .milliseconds(5))
        return clientDataHash
    }
}

private actor EndAPITestServer {
    let jobID: UUID
    let now: Date
    private(set) var requestCount = 0
    private(set) var registrationBodies: [Data] = []
    private(set) var businessRequests: [URLRequest] = []
    private var loseRegistration = false
    private var conflict = false
    private var errorResponse: Data?
    private var challengeCount = 0

    init(jobID: UUID, now: Date) {
        self.jobID = jobID
        self.now = now
    }

    func loseNextRegistrationResponse() { loseRegistration = true }
    func rejectBusinessWithConflict() { conflict = true }
    func rejectBusiness(with body: Data) { errorResponse = body }

    func respond(to request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        let url = try #require(request.url)
        var status = 200
        let body: [String: Any]
        switch url.path {
        case "/v1/auth/challenges":
            challengeCount += 1
            body = [
                "challengeId": String(format: "00000000-0000-0000-0000-%012d", challengeCount),
                "challenge": Data(repeating: UInt8(challengeCount), count: 32)
                    .base64EncodedString(),
                "expiresAt": now.addingTimeInterval(300).ISO8601Format()
            ]
        case "/v1/auth/attestations":
            registrationBodies.append(try #require(request.httpBody))
            if loseRegistration {
                loseRegistration = false
                throw URLError(.networkConnectionLost)
            }
            body = [
                "installationId": "76a56592-c9c2-46c7-becd-fdf13dff1d8c",
                "authScheme": "app-attest-v1"
            ]
        default:
            businessRequests.append(request)
            if let errorResponse {
                return (
                    errorResponse,
                    try #require(
                        HTTPURLResponse(
                            url: url, statusCode: 409, httpVersion: nil, headerFields: nil))
                )
            }
            if conflict {
                status = 409
                body = ["error": ["code": "STALE_REVISION", "details": ["currentRevision": "17"]]]
            } else {
                body = [
                    "jobId": jobID.uuidString.lowercased(), "revision": "2", "status": "cancelled",
                    "activityEndsAt": NSNull(),
                    "delivery": [
                        "state": "not_sent", "attemptCount": 0, "acceptedAt": NSNull(),
                        "mayHaveBeenSent": false
                    ]
                ]
            }
        }
        return (
            try JSONSerialization.data(withJSONObject: body),
            try #require(
                HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
        )
    }
}
