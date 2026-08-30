import Foundation
import Testing

@testable import NotificationManagerWidgetSupport

@Suite("PunctualDeepLinkCodec")
struct PunctualDeepLinkTests {
    @Test func listDeepLinkRoundTrips() {
        let codec = PunctualDeepLinkCodec()
        let url = codec.url(for: .list)

        #expect(url.absoluteString == "punctual://reminders")
        #expect(codec.parse(url) == .list)
    }

    @Test func reminderDeepLinkRoundTrips() {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let codec = PunctualDeepLinkCodec()
        let url = codec.url(for: .reminder(id))

        #expect(url.absoluteString == "punctual://reminders/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        #expect(codec.parse(url) == .reminder(id))
    }

    @Test func parserRejectsNoncanonicalOrUnsafeURLs() throws {
        let codec = PunctualDeepLinkCodec()
        let invalid = [
            "other://reminders",
            "punctual://rem%69nders",
            "punctual://user@reminders",
            "punctual://reminders:",
            "punctual://reminders:443",
            "punctual://reminders?source=widget",
            "punctual://reminders#section",
            "punctual://reminders/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/extra",
            "punctual://reminders/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            "punctual://reminders/aaaaaaaa%2Daaaa-aaaa-aaaa-aaaaaaaaaaaa",
            "punctual://reminders/%",
            "punctual://reminders/"
        ]

        for value in invalid {
            let url = try #require(URL(string: value))
            #expect(codec.parse(url) == nil)
        }
    }
}
