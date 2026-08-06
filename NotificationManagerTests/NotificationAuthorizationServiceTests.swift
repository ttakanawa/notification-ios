import NotificationManagerDomain
import Testing
@testable import NotificationManager

struct NotificationAuthorizationServiceTests {
    @Test(arguments: [2, 3, 4])
    func authorizedProvisionalAndEphemeralAllowScheduling(
        rawValue: Int
    ) {
        let snapshot = NotificationAuthorizationService.map(rawValue: rawValue)

        #expect(snapshot.state == .allowed)
        #expect(snapshot.allowsScheduling)
        #expect(snapshot.diagnostic == nil)
    }

    @Test func notDeterminedAndDeniedRemainDistinctDisallowedStates() {
        let notDetermined = NotificationAuthorizationService.map(
            rawValue: 0
        )
        let denied = NotificationAuthorizationService.map(
            rawValue: 1
        )

        #expect(notDetermined.state == .notDetermined)
        #expect(!notDetermined.allowsScheduling)
        #expect(notDetermined.diagnostic == nil)
        #expect(denied.state == .denied)
        #expect(!denied.allowsScheduling)
        #expect(denied.diagnostic == nil)
    }

    @Test func futureAuthorizationValueIsDisallowedWithRawDiagnostic() {
        let snapshot = NotificationAuthorizationService.map(rawValue: 9_999)

        #expect(snapshot.state == .unknown)
        #expect(!snapshot.allowsScheduling)
        #expect(snapshot.diagnostic == .unknownStatus(rawValue: 9_999))
    }
}
