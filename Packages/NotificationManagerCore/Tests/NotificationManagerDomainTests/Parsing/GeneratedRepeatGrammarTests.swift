import Testing

@testable import NotificationManagerDomain

@Suite("Parsing.GeneratedRepeatGrammar")
struct ParsingGeneratedRepeatGrammarTests {
    @Test(arguments: GeneratedRepeatGrammarFixtures.accepted)
    func everyGeneratedProductionParsesValidatesAndCanonicalizes(
        _ fixture: GeneratedRepeatGrammarFixture
    ) throws {
        let candidate = try parser.parse(fixture.input).get()
        let rule = try validator.validate(candidate, source: .repeatFixture)

        #expect(formatter.string(for: rule) == fixture.canonical)
    }

    @Test(arguments: GeneratedRepeatGrammarFixtures.rejected)
    func everyOneVariableInvalidMutationFailsParsing(
        _ fixture: GeneratedRejectedRepeatFixture
    ) {
        #expect(throws: RepeatParseFailure.self) {
            _ = try parser.parse(fixture.input).get()
        }
    }

    @Test func generatedFixtureCountsPreventSilentCoverageShrinkage() {
        #expect(GeneratedRepeatGrammarFixtures.accepted.count == 1_750)
        #expect(GeneratedRepeatGrammarFixtures.rejected.count == 65)
    }

    private let parser = EnglishRepeatParser()
    private let validator = RepeatRuleValidator()
    private let formatter = CanonicalRepeatFormatter()
}
