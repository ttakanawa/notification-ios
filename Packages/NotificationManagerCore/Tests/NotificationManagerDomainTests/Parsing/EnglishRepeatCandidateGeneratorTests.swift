import Testing

@testable import NotificationManagerDomain

@Suite("Parsing.EnglishRepeatCandidateGenerator")
struct EnglishRepeatCandidateGeneratorTests {
    private let generator = EnglishRepeatCandidateGenerator()

    @Test func normalizesTwoAndThreeWeekdaySeparators() {
        #expect(
            generator.suggestions(for: "Every Monday, and Wednesday") == [
                "Every Monday and Wednesday"
            ])
        #expect(
            generator.suggestions(for: "Every Monday Wednesday") == [
                "Every Monday and Wednesday"
            ])
        #expect(
            generator.suggestions(for: "Every Monday Wednesday Friday") == [
                "Every Monday, Wednesday, and Friday"
            ])
    }

    @Test func combinesTwoSingleCostSpellingRepairs() {
        #expect(generator.suggestions(for: "Evrey Tuseday") == ["Every Tuesday"])
    }

    @Test func composesSpellingAndWeekdaySeparatorRepairsWithinTheCostBudget() {
        #expect(
            generator.suggestions(for: "Every mondy wednesday") == [
                "Every Monday and Wednesday"
            ])
    }

    @Test func preservesAmbiguityAsMultipleStableCandidates() {
        #expect(
            generator.suggestions(for: "Every mont") == [
                "Every Monday", "Every month"
            ])
    }

    @Test func interpretsBareFirstWeekdayAsTheMatchingWeeklyCandidate() {
        #expect(generator.suggestions(for: "Every 1st Friday") == ["Every Friday"])
    }

    @Test func insertsTheMissingMonthlySelectorPreposition() {
        #expect(
            generator.suggestions(for: "Every month 1st Friday") == [
                "Every month on the 1st Friday"
            ])
    }

    @Test func rejectsOverBudgetUnsafeAndDuplicateRepairs() {
        #expect(generator.suggestions(for: "Evrey Tuseday adn Wednesday").isEmpty)
        #expect(generator.suggestions(for: "Every Monday except first Monday").isEmpty)
        #expect(generator.suggestions(for: "Every Monday Monday").isEmpty)
    }

    @Test func rejectsSemanticOperatorsWithoutDroppingTheirClauses() {
        #expect(generator.suggestions(for: "Never day").isEmpty)
        #expect(generator.suggestions(for: "Every month not the first Monday").isEmpty)
    }

    @Test func detectsExactUnsupportedSemanticOperatorTokensCaseInsensitively() {
        let safety = EnglishRepeatLexicalSafety()

        #expect(safety.containsUnsupportedSemanticOperator(in: "Never day"))
        #expect(safety.containsUnsupportedSemanticOperator(in: "Every Monday EXCEPT first Monday"))
        #expect(safety.containsUnsupportedSemanticOperator(in: "Every month NOT the first Monday"))
        #expect(!safety.containsUnsupportedSemanticOperator(in: "Every month notation"))
        #expect(!safety.containsUnsupportedSemanticOperator(in: "Every month exception"))
    }

    @Test func detectsOperatorsOutsideTheStrictLexerGrammar() {
        let safety = EnglishRepeatLexicalSafety()
        let overLimit = String(repeating: "x", count: 256) + " except"

        #expect(safety.containsUnsupportedSemanticOperator(in: "Every Monday except first Monday."))
        #expect(safety.containsUnsupportedSemanticOperator(in: "毎週 except 月曜日"))
        #expect(overLimit.unicodeScalars.count > 256)
        #expect(safety.containsUnsupportedSemanticOperator(in: overLimit))
    }

    @Test func rejectsMalformedWeekdaySeparatorOrder() {
        #expect(generator.suggestions(for: "Every Monday and, Wednesday").isEmpty)
    }
}
