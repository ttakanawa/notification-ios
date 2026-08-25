public struct EnglishRepeatLexicalSafety: Sendable {
    public init() {}

    public func containsUnsupportedSemanticOperator(in input: String) -> Bool {
        var scanner = OperatorTokenScanner()
        for scalar in input.unicodeScalars {
            if Self.isASCIILetter(scalar) {
                scanner.append(Self.lowercasedASCII(scalar.value))
            } else if scanner.isProtectedOperator {
                return true
            } else {
                scanner.reset()
            }
        }
        return scanner.isProtectedOperator
    }

    func containsUnsupportedSemanticOperator(in lexed: EnglishRepeatLexer.Lexed) -> Bool {
        lexed.tokens.contains { token in
            guard case .word(let word) = token.kind else { return false }
            return Self.isUnsupportedSemanticOperator(word)
        }
    }

    private static func isUnsupportedSemanticOperator(_ word: String) -> Bool {
        word == "except" || word == "never" || word == "not"
    }

    private static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
        (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }

    private static func lowercasedASCII(_ value: UInt32) -> UInt32 {
        (65...90).contains(value) ? value + 32 : value
    }

    private static let protectedOperatorTokens: [[UInt32]] = [
        [101, 120, 99, 101, 112, 116],
        [110, 101, 118, 101, 114],
        [110, 111, 116]
    ]

    private struct OperatorTokenScanner {
        private var tokenLength = 0
        private var candidateMask = 0b111

        var isProtectedOperator: Bool {
            for (index, token) in EnglishRepeatLexicalSafety.protectedOperatorTokens.enumerated()
            where candidateMask & (1 << index) != 0 {
                if tokenLength == token.count { return true }
            }
            return false
        }

        mutating func append(_ value: UInt32) {
            guard tokenLength < EnglishRepeatLexicalSafety.maximumProtectedTokenLength else {
                candidateMask = 0
                return
            }

            let index = tokenLength
            tokenLength += 1
            for (operatorIndex, token) in EnglishRepeatLexicalSafety.protectedOperatorTokens
                .enumerated()
            where candidateMask & (1 << operatorIndex) != 0 {
                guard index < token.count, token[index] == value else {
                    candidateMask &= ~(1 << operatorIndex)
                    continue
                }
            }
        }

        mutating func reset() {
            tokenLength = 0
            candidateMask = 0b111
        }
    }

    private static let maximumProtectedTokenLength = 6
}
