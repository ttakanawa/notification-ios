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

    @Test func searchMatchesLocationWordsSeparatedBySpaces() throws {
        let newYork = try #require(
            TimeZoneChoice.all(locale: Locale(identifier: "en_US"))
                .first { $0.identifier == "America/New_York" }
        )

        #expect(newYork.matches(query: "New York"))
    }

    @Test func newYorkUsesLocalizedCityAndCountryLabel() throws {
        let newYork = try #require(
            TimeZoneChoice.all(
                locale: Locale(identifier: "en_US"),
                at: Date(timeIntervalSince1970: 1_782_907_200)
            )
            .first { $0.identifier == "America/New_York" }
        )

        #expect(newYork.locationName == "New York, United States")
    }

    @Test func newYorkDetailUsesDaylightSavingAbbreviationInSummer() throws {
        let newYork = try #require(
            TimeZoneChoice.all(
                locale: Locale(identifier: "en_US"),
                at: Date(timeIntervalSince1970: 1_782_907_200)
            )
            .first { $0.identifier == "America/New_York" }
        )

        #expect(newYork.detailName == "Eastern Time (EDT)")
    }

    @Test func newYorkDetailUsesStandardAbbreviationInWinter() throws {
        let newYork = try #require(
            TimeZoneChoice.all(
                locale: Locale(identifier: "en_US"),
                at: Date(timeIntervalSince1970: 1_767_268_800)
            )
            .first { $0.identifier == "America/New_York" }
        )

        #expect(newYork.detailName == "Eastern Time (EST)")
    }

    @Test func newYorkPresentationLocalizesInJapanese() throws {
        let locale = Locale(identifier: "ja_JP")
        let date = Date(timeIntervalSince1970: 1_782_907_200)
        let timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let newYork = try #require(
            TimeZoneChoice.all(
                locale: locale,
                at: date
            )
            .first { $0.identifier == "America/New_York" }
        )
        let formatStyle = Date.FormatStyle(locale: locale, timeZone: timeZone)
        let city = date.formatted(formatStyle.timeZone(.exemplarLocation))
        let country = try #require(locale.localizedString(forRegionCode: "US"))
        let expectedLocation = [city, country].formatted(
            .list(type: .and, width: .narrow).locale(locale)
        )
        let genericName = try #require(
            timeZone.localizedName(for: .generic, locale: locale)
        )
        let abbreviation = try #require(timeZone.abbreviation(for: date))

        #expect(newYork.locationName == expectedLocation)
        #expect(newYork.detailName == "\(genericName) (\(abbreviation))")
    }

    @Test func choicesHaveUniquePresentationAndHideDeprecatedAliases() {
        let choices = TimeZoneChoice.all(
            locale: Locale(identifier: "en_US"),
            at: Date(timeIntervalSince1970: 1_782_907_200)
        )
        let presentations = choices.map {
            "\($0.locationName)\u{0}\($0.detailName ?? "")"
        }

        #expect(Set(presentations).count == presentations.count)
        #expect(!choices.contains { $0.identifier == "Asia/Katmandu" })
        #expect(choices.contains { $0.identifier == "Asia/Kathmandu" })
    }

    @Test func selectedDeprecatedAliasRemainsAvailableWithoutDuplicatePresentation() {
        let choices = TimeZoneChoice.all(
            locale: Locale(identifier: "en_US"),
            at: Date(timeIntervalSince1970: 1_782_907_200),
            preservingIdentifier: "Asia/Katmandu"
        )
        let presentations = choices.map {
            "\($0.locationName)\u{0}\($0.detailName ?? "")"
        }

        #expect(choices.contains { $0.identifier == "Asia/Katmandu" })
        #expect(Set(presentations).count == presentations.count)
    }

    @Test func regionCatalogHasExpectedWellFormedCanonicalAndAliasEntries() {
        let entries = TimeZoneRegionCatalog.entries

        #expect(entries.count == 443)
        #expect(entries.filter(\.isAlias).count == 25)
        #expect(Set(entries.map(\.identifier)).count == entries.count)
        #expect(
            entries.allSatisfy {
                $0.regionCode.count == 2
                    && $0.regionCode.unicodeScalars.allSatisfy {
                        CharacterSet.uppercaseLetters.contains($0)
                    }
            }
        )
    }

    @Test func searchMatchesLocalizedCountryAndCurrentAbbreviation() throws {
        let newYork = try #require(
            TimeZoneChoice.all(
                locale: Locale(identifier: "en_US"),
                at: Date(timeIntervalSince1970: 1_782_907_200)
            )
            .first { $0.identifier == "America/New_York" }
        )

        #expect(newYork.matches(query: "United States"))
        #expect(newYork.matches(query: "EDT"))
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
