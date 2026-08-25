public struct EnglishRepeatLexicalSafety: Sendable {
    public init() {}

    public func containsUnsupportedSemanticOperator(in input: String) -> Bool {
        guard let lexed = try? EnglishRepeatLexer().lex(input) else { return false }
        return containsUnsupportedSemanticOperator(in: lexed)
    }

    func containsUnsupportedSemanticOperator(in lexed: EnglishRepeatLexer.Lexed) -> Bool {
        lexed.tokens.contains { token in
            guard case .word(let word) = token.kind else { return false }
            return Self.unsupportedSemanticOperators.contains(word)
        }
    }

    private static let unsupportedSemanticOperators: Set<String> = ["except", "never", "not"]
}
