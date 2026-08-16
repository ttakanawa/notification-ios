import Foundation
import Testing

@testable import NotificationManager

struct TimeZoneChoiceTests {
    @Test func choicesAreKnownValidAndSortedByIdentifier() {
        let choices = TimeZoneChoice.all(locale: Locale(identifier: "en_US"))

        #expect(!choices.isEmpty)
        #expect(choices.map(\.identifier) == choices.map(\.identifier).sorted())
        #expect(
            choices.allSatisfy {
                TimeZone.knownTimeZoneIdentifiers.contains($0.identifier)
                    && TimeZone(identifier: $0.identifier) != nil
            })
    }

    @Test func searchMatchesIdentifierAndGenericNameCaseInsensitively() throws {
        let tokyo = try #require(
            TimeZoneChoice.all(locale: Locale(identifier: "en_US"))
                .first { $0.identifier == "Asia/Tokyo" }
        )

        #expect(tokyo.matches(query: "TOKYO"))
        if let localizedName = tokyo.localizedName {
            #expect(tokyo.matches(query: localizedName.uppercased()))
        }
    }

    @Test func emptySearchMatchesAndUnrelatedSearchDoesNot() throws {
        let tokyo = try #require(
            TimeZoneChoice.all(locale: Locale(identifier: "en_US"))
                .first { $0.identifier == "Asia/Tokyo" }
        )

        #expect(tokyo.matches(query: ""))
        #expect(!tokyo.matches(query: "not-a-real-time-zone-name"))
    }
}
