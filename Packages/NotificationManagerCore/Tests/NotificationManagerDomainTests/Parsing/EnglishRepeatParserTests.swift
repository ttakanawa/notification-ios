import Testing

@testable import NotificationManagerDomain

@Suite("Parsing.EnglishRepeatParser")
struct ParsingEnglishRepeatParserTests {
    @Test(arguments: RepeatGrammarFixtures.accepted)
    func acceptsEveryNormativeProductionAndCompatibilityFixture(
        _ fixture: AcceptedRepeatFixture
    ) throws {
        let candidate = try parser.parse(fixture.input).get()
        let rule = try validator.validate(candidate, source: .repeatFixture)
        #expect(formatter.string(for: rule) == fixture.canonical)
    }

    @Test(arguments: RepeatGrammarFixtures.rejected)
    func rejectsMalformedUnsupportedAndOutOfRangeGrammar(_ input: String) {
        #expect(throws: RepeatParseFailure.self) {
            _ = try parser.parse(input).get()
        }
    }

    @Test func acceptsEveryASCIIWhitespaceScalarAtBothEdgesAndBetweenWords() throws {
        for scalar in [" ", "\t", "\n", "\u{000B}", "\u{000C}", "\r"] {
            let input = scalar + "Every" + scalar + scalar + "week" + scalar
            let candidate = try parser.parse(input).get()
            let rule = try validator.validate(candidate, source: .repeatFixture)
            #expect(rule == .weekly(interval: 1, weekdaySetKind: .explicit, weekdays: [.tuesday]))
        }
    }

    @Test func appliesThe256UnicodeScalarLimitBeforeTrimming() throws {
        let accepted = String(repeating: " ", count: 245) + "Every week"
        #expect(accepted.unicodeScalars.count == 255)
        _ = try parser.parse(accepted).get()

        let rejected = String(repeating: " ", count: 246) + "Every week"
        #expect(rejected.unicodeScalars.count == 256)
        _ = try parser.parse(rejected).get()

        let tooLong = String(repeating: " ", count: 247) + "Every week"
        #expect(tooLong.unicodeScalars.count == 257)
        #expect(throws: RepeatParseFailure.self) {
            _ = try parser.parse(tooLong).get()
        }
    }

    @Test func acceptsAllFullAndAbbreviatedWeekdayNamesCaseInsensitively() throws {
        let spellings = [
            ("Monday", "Mon", "Every Monday"), ("Tuesday", "Tue", "Every Tuesday"),
            ("Wednesday", "Wed", "Every Wednesday"), ("Thursday", "Thu", "Every Thursday"),
            ("Friday", "Fri", "Every Friday"), ("Saturday", "Sat", "Every Saturday"),
            ("Sunday", "Sun", "Every Sunday")
        ]

        for (full, abbreviation, canonical) in spellings {
            for spelling in [full, abbreviation, full.uppercased(), abbreviation.lowercased()] {
                let rule = try validated("Every \(spelling)")
                #expect(formatter.string(for: rule) == canonical)
            }
        }
    }

    @Test func acceptsAllFullAndAbbreviatedMonthNamesCaseInsensitively() throws {
        let names = [
            ("January", "Jan"), ("February", "Feb"), ("March", "Mar"),
            ("April", "Apr"), ("May", "May"), ("June", "Jun"),
            ("July", "Jul"), ("August", "Aug"), ("September", "Sep"),
            ("October", "Oct"), ("November", "Nov"), ("December", "Dec")
        ]

        for (full, abbreviation) in names {
            for spelling in [full, abbreviation, full.uppercased()] {
                let rule = try validated("Every year on the 1st of \(spelling)")
                #expect(formatter.string(for: rule) == "Every year on the 1st of \(full)")
            }
        }
    }

    @Test func acceptsEveryCorrectNumericOrdinalSuffixAndRejectsIncorrectSuffixes() throws {
        let accepted = [
            1: "st", 2: "nd", 3: "rd", 4: "th", 11: "th", 12: "th", 13: "th", 21: "st", 22: "nd",
            23: "rd", 31: "st"
        ]
        for (number, suffix) in accepted {
            _ = try validated("Every month on the \(number)\(suffix)")
        }

        for input in [
            "Every month on the 1th", "Every month on the 2ndd", "Every month on the 11st",
            "Every month on the 12nd", "Every month on the 13rd", "Every month on the 21th"
        ] {
            #expect(throws: RepeatParseFailure.self) { _ = try parser.parse(input).get() }
        }
    }

    @Test func generatesCoverageForEveryCountedFrequencyProductionAtBothBoundaries() throws {
        let fixtures = [
            ("hours", "Every 2 hours", "Every 9999 hours"),
            ("days", "Every 2 days", "Every 9999 days"),
            ("weeks", "Every 2 weeks", "Every 9999 weeks"),
            ("months", "Every 2 months", "Every 9999 months"),
            ("years", "Every 2 years", "Every 9999 years")
        ]
        for (unit, lowerCanonical, upperCanonical) in fixtures {
            #expect(formatter.string(for: try validated("Every 2 \(unit)")) == lowerCanonical)
            #expect(formatter.string(for: try validated("Every 9999 \(unit)")) == upperCanonical)
        }
    }

    @Test func generatesCoverageForEveryForwardAndReverseSelectorProduction() throws {
        let wordOrdinals = [
            ("first", "1st"), ("second", "2nd"), ("third", "3rd"), ("fourth", "4th"),
            ("fifth", "5th")
        ]
        for (word, numeric) in wordOrdinals {
            #expect(
                formatter.string(for: try validated("Every month on the \(word) weekday"))
                    == "Every month on the \(numeric) weekday")
            #expect(
                formatter.string(for: try validated("Every month on the \(word) weekend day"))
                    == "Every month on the \(numeric) weekend day")
            #expect(
                formatter.string(for: try validated("Every month on the \(word) Monday"))
                    == "Every month on the \(numeric) Monday")
        }
        for ordinal in 2...5 {
            let suffix = ordinal == 2 ? "nd" : ordinal == 3 ? "rd" : "th"
            let text = "\(ordinal)\(suffix)"
            #expect(
                formatter.string(for: try validated("Every month on the \(text) last Sunday"))
                    == "Every month on the \(text) last Sunday")
        }
    }

    @Test func generatesAllAllowedWeekdayListLengthsAndSeparatorForms() throws {
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        for count in 3...7 {
            let prefix = names.prefix(count)
            let finalInputName = try #require(prefix.last)
            let commaOnly = "Every " + prefix.joined(separator: ",")
            let noOxford =
                "Every " + prefix.dropLast().joined(separator: ", ") + " and " + finalInputName
            let oxford =
                "Every " + prefix.dropLast().joined(separator: ", ") + ", and " + finalInputName
            let expectedNames = [
                "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
            ].prefix(count)
            let finalExpectedName = try #require(expectedNames.last)
            let canonical =
                "Every " + expectedNames.dropLast().joined(separator: ", ") + ", and "
                + finalExpectedName
            #expect(formatter.string(for: try validated(commaOnly)) == canonical)
            #expect(formatter.string(for: try validated(noOxford)) == canonical)
            #expect(formatter.string(for: try validated(oxford)) == canonical)
        }
    }

    @Test func validatesEveryFixedYearlyMonthMaximumAgainstTheProlepticGregorianSource() throws {
        let valid = [
            ("31st", "January"), ("29th", "February"), ("31st", "March"),
            ("30th", "April"), ("31st", "May"), ("30th", "June"),
            ("31st", "July"), ("31st", "August"), ("30th", "September"),
            ("31st", "October"), ("30th", "November"), ("31st", "December")
        ]
        for (day, month) in valid {
            let text = "Every year on the \(day) of \(month)"
            #expect(formatter.string(for: try validated(text)) == text)
        }
    }

    @Test func offersAUniqueSingleAlphabeticTokenDamerauLevenshteinSuggestion() {
        #expect(failure(for: "Evrey day").suggestion == "Every day")
        #expect(failure(for: "Every Tuseday").suggestion == "Every Tuesday")
        #expect(
            failure(for: "Every yer on the 1st of January").suggestion
                == "Every year on the 1st of January")
    }

    @Test func doesNotSuggestWhenCorrectionIsAmbiguousRequiresTwoTokensOrFailsValidation() {
        #expect(failure(for: "Every mont").suggestion == nil)
        #expect(failure(for: "Evrey Tuseday").suggestion == nil)
        #expect(failure(for: "Every year on the 31st of Apri").suggestion == nil)
    }

    @Test func doesNotFabricateAWeekdayForSourceAnchoredWeeklySuggestion() {
        let parseFailure = failure(for: "Every wekk")
        let countedParseFailure = failure(for: "Every 2 weks")

        #expect(parseFailure.suggestion == nil)
        #expect(countedParseFailure.suggestion == nil)
        #expect(throws: RepeatParseFailure.self) {
            _ = try parser.parse("Every wekk").get()
        }

        let correctedCandidate = try? parser.parse("Every week").get()
        let actualSourceRule = correctedCandidate.flatMap {
            try? validator.validate($0, source: .repeatFixture)
        }
        #expect(
            actualSourceRule
                == .weekly(interval: 1, weekdaySetKind: .explicit, weekdays: [.tuesday]))
    }

    @Test func suggestionNeverAutoAppliesTheCorrection() {
        let result = parser.parse("Every Tuseday")
        #expect(throws: RepeatParseFailure.self) { _ = try result.get() }
    }

    private let parser = EnglishRepeatParser()
    private let validator = RepeatRuleValidator()
    private let formatter = CanonicalRepeatFormatter()

    private func validated(_ input: String) throws -> RepeatRule {
        try validator.validate(parser.parse(input).get(), source: .repeatFixture)
    }

    private func failure(for input: String) -> RepeatParseFailure {
        switch parser.parse(input) {
        case .success:
            Issue.record("Expected parsing to fail: \(input)")
            return RepeatParseFailure(suggestion: nil)
        case .failure(let failure):
            return failure
        }
    }
}
