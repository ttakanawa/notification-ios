struct EnglishRepeatLexer: Sendable {
    struct Lexed: Sendable {
        let input: String
        let tokens: [Token]
    }

    struct Token: Sendable, Equatable {
        enum Kind: Sendable, Equatable {
            case word(String)
            case integer(String)
            case ordinal(number: String, suffix: String)
            case comma
        }

        let kind: Kind
        let scalarRange: Range<Int>
    }

    enum Failure: Error {
        case invalidInput
    }

    func lex(_ input: String) throws -> Lexed {
        let scalars = Array(input.unicodeScalars)
        guard scalars.count <= 256 else { throw Failure.invalidInput }

        var lowerBound = 0
        while lowerBound < scalars.count, Self.isWhitespace(scalars[lowerBound]) {
            lowerBound += 1
        }
        var upperBound = scalars.count
        while upperBound > lowerBound, Self.isWhitespace(scalars[upperBound - 1]) {
            upperBound -= 1
        }
        guard lowerBound < upperBound else { throw Failure.invalidInput }

        var tokens: [Token] = []
        var index = lowerBound
        while index < upperBound {
            if Self.isWhitespace(scalars[index]) {
                index += 1
                while index < upperBound, Self.isWhitespace(scalars[index]) { index += 1 }
                continue
            }

            let start = index
            let value = scalars[index].value
            if value == 44 {
                tokens.append(Token(kind: .comma, scalarRange: start..<start + 1))
                index += 1
            } else if Self.isLetter(scalars[index]) {
                index += 1
                while index < upperBound, Self.isLetter(scalars[index]) { index += 1 }
                try Self.validateTokenBoundary(tokens, nextStart: start)
                let word = String(String.UnicodeScalarView(scalars[start..<index])).lowercased()
                tokens.append(Token(kind: .word(word), scalarRange: start..<index))
            } else if Self.isDigit(scalars[index]) {
                index += 1
                while index < upperBound, Self.isDigit(scalars[index]) { index += 1 }
                let numberEnd = index
                while index < upperBound, Self.isLetter(scalars[index]) { index += 1 }
                try Self.validateTokenBoundary(tokens, nextStart: start)
                let number = String(String.UnicodeScalarView(scalars[start..<numberEnd]))
                if numberEnd == index {
                    tokens.append(Token(kind: .integer(number), scalarRange: start..<index))
                } else {
                    let suffix = String(String.UnicodeScalarView(scalars[numberEnd..<index]))
                        .lowercased()
                    tokens.append(
                        Token(
                            kind: .ordinal(number: number, suffix: suffix),
                            scalarRange: start..<index
                        )
                    )
                }
            } else {
                throw Failure.invalidInput
            }
        }
        return Lexed(input: input, tokens: tokens)
    }

    private static func validateTokenBoundary(_ tokens: [Token], nextStart: Int) throws {
        if let previous = tokens.last,
            previous.scalarRange.upperBound == nextStart,
            previous.kind != .comma
        {
            throw Failure.invalidInput
        }
    }

    private static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 32 || (9...13).contains(scalar.value)
    }

    private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        (48...57).contains(scalar.value)
    }
}
