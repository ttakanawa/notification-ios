import Testing

@testable import NotificationManagerDomain

@Suite("Parsing.EnglishRepeatCandidateGenerator")
struct EnglishRepeatCandidateGeneratorTests {
    private let generator = EnglishRepeatCandidateGenerator()

    @Test func normalizesTwoAndThreeWeekdaySeparators() {
        #expect(generator.suggestions(for: "Every Monday, and Wednesday") == [
            "Every Monday and Wednesday"
        ])
        #expect(generator.suggestions(for: "Every Monday Wednesday") == [
            "Every Monday and Wednesday"
        ])
        #expect(generator.suggestions(for: "Every Monday Wednesday Friday") == [
            "Every Monday, Wednesday, and Friday"
        ])
    }

    @Test func combinesTwoSingleCostSpellingRepairs() {
        #expect(generator.suggestions(for: "Evrey Tuseday") == ["Every Tuesday"])
    }

    @Test func preservesAmbiguityAsMultipleStableCandidates() {
        #expect(generator.suggestions(for: "Every mont") == [
            "Every Monday", "Every month"
        ])
    }

    @Test func rejectsOverBudgetUnsafeAndDuplicateRepairs() {
        #expect(generator.suggestions(for: "Evrey Tuseday adn Wednesday").isEmpty)
        #expect(generator.suggestions(for: "Every Monday except first Monday").isEmpty)
        #expect(generator.suggestions(for: "Every Monday Monday").isEmpty)
    }

    @Test func rejectsMalformedWeekdaySeparatorOrder() {
        #expect(generator.suggestions(for: "Every Monday and, Wednesday").isEmpty)
    }
}
