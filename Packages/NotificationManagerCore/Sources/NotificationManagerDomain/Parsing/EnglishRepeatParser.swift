public struct RepeatParseFailure: Error, Sendable, Equatable {
    public let suggestion: String?

    public init(suggestion: String?) {
        self.suggestion = suggestion
    }
}

public struct EnglishRepeatParser: Sendable {
    public static let grammarVersion = "rtm-every-2026-08-02-v1"

    public init() {}

    public func parse(_ input: String) -> Result<RepeatCandidate, RepeatParseFailure> {
        do {
            return .success(try parseExact(input))
        } catch {
            return .failure(RepeatParseFailure(suggestion: suggestion(for: input)))
        }
    }

    private func parseExact(_ input: String) throws -> RepeatCandidate {
        let lexed = try EnglishRepeatLexer().lex(input)
        var cursor = Cursor(tokens: lexed.tokens)
        try cursor.requireWord("every")
        let candidate = try parseBody(&cursor)
        guard cursor.isAtEnd else { throw SyntaxFailure.invalid }

        _ = try RepeatRuleValidator().validate(candidate, source: Self.validationSource)
        return candidate
    }

    private func parseBody(_ cursor: inout Cursor) throws -> RepeatCandidate {
        if cursor.peekWord("weekday") {
            cursor.advance()
            return RepeatCandidate(
                frequency: .weekly,
                interval: 1,
                weekdaySetKind: .weekday,
                weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday]
            )
        }
        if cursor.peekWord("weekend") {
            cursor.advance()
            return RepeatCandidate(
                frequency: .weekly,
                interval: 1,
                weekdaySetKind: .weekend,
                weekdays: [.saturday, .sunday]
            )
        }
        if cursor.peekWeekday() != nil {
            return try parseWeekdayList(&cursor)
        }
        if let word = cursor.peekWordValue() {
            switch word {
            case "hour":
                cursor.advance()
                return RepeatCandidate(frequency: .hourly, interval: 1)
            case "day":
                cursor.advance()
                return RepeatCandidate(frequency: .daily, interval: 1)
            case "week":
                cursor.advance()
                return RepeatCandidate(frequency: .weekly, interval: 1)
            case "month":
                cursor.advance()
                return try parseMonthly(interval: 1, cursor: &cursor)
            case "year":
                cursor.advance()
                return try parseYearly(interval: 1, cursor: &cursor)
            default:
                throw SyntaxFailure.invalid
            }
        }
        if cursor.peekInteger() != nil {
            return try parseCountedFrequency(&cursor)
        }
        throw SyntaxFailure.invalid
    }

    private func parseCountedFrequency(_ cursor: inout Cursor) throws -> RepeatCandidate {
        let interval = try cursor.requireDecimalInteger()
        guard let unit = cursor.consumeWord() else { throw SyntaxFailure.invalid }

        if interval == 1 {
            switch unit {
            case "hour": return RepeatCandidate(frequency: .hourly, interval: interval)
            case "day": return RepeatCandidate(frequency: .daily, interval: interval)
            case "week": return RepeatCandidate(frequency: .weekly, interval: interval)
            case "month": return try parseMonthly(interval: interval, cursor: &cursor)
            case "year": return try parseYearly(interval: interval, cursor: &cursor)
            default: throw SyntaxFailure.invalid
            }
        }
        guard (2...9_999).contains(interval) else { throw SyntaxFailure.invalid }
        switch unit {
        case "hours": return RepeatCandidate(frequency: .hourly, interval: interval)
        case "days": return RepeatCandidate(frequency: .daily, interval: interval)
        case "weeks": return RepeatCandidate(frequency: .weekly, interval: interval)
        case "months": return try parseMonthly(interval: interval, cursor: &cursor)
        case "years": return try parseYearly(interval: interval, cursor: &cursor)
        default: throw SyntaxFailure.invalid
        }
    }

    private func parseWeekdayList(_ cursor: inout Cursor) throws -> RepeatCandidate {
        var weekdays = [try cursor.requireWeekday()]
        if cursor.isAtEnd {
            return explicitWeekdays(weekdays)
        }
        if cursor.consumeWord("and") {
            weekdays.append(try cursor.requireWeekday())
            guard cursor.isAtEnd else { throw SyntaxFailure.invalid }
            return explicitWeekdays(weekdays)
        }
        guard cursor.consumeComma() else { throw SyntaxFailure.invalid }
        weekdays.append(try cursor.requireWeekday())
        guard !cursor.isAtEnd else { throw SyntaxFailure.invalid }

        while true {
            if cursor.consumeWord("and") {
                weekdays.append(try cursor.requireWeekday())
                guard cursor.isAtEnd else { throw SyntaxFailure.invalid }
                return try boundedWeekdayList(weekdays)
            }
            guard cursor.consumeComma() else { throw SyntaxFailure.invalid }
            if cursor.consumeWord("and") {
                weekdays.append(try cursor.requireWeekday())
                guard cursor.isAtEnd else { throw SyntaxFailure.invalid }
                return try boundedWeekdayList(weekdays)
            }
            weekdays.append(try cursor.requireWeekday())
            if cursor.isAtEnd {
                return try boundedWeekdayList(weekdays)
            }
        }
    }

    private func boundedWeekdayList(_ weekdays: [Weekday]) throws -> RepeatCandidate {
        guard (3...7).contains(weekdays.count) else { throw SyntaxFailure.invalid }
        return explicitWeekdays(weekdays)
    }

    private func explicitWeekdays(_ weekdays: [Weekday]) -> RepeatCandidate {
        RepeatCandidate(
            frequency: .weekly,
            interval: 1,
            weekdaySetKind: .explicit,
            weekdays: weekdays
        )
    }

    private func parseMonthly(
        interval: Int,
        cursor: inout Cursor
    ) throws -> RepeatCandidate {
        guard cursor.consumeWord("on") else {
            return RepeatCandidate(frequency: .monthly, interval: interval, selector: .anchorDay)
        }
        _ = cursor.consumeWord("the")
        let selector = try parseSelector(&cursor)
        return RepeatCandidate(frequency: .monthly, interval: interval, selector: selector)
    }

    private func parseYearly(
        interval: Int,
        cursor: inout Cursor
    ) throws -> RepeatCandidate {
        guard cursor.consumeWord("on") else {
            return RepeatCandidate(
                frequency: .yearly,
                interval: interval,
                selector: .anchorMonthDay
            )
        }
        _ = cursor.consumeWord("the")
        let selector = try parseSelector(&cursor)
        try cursor.requireWord("of")
        let month = try cursor.requireMonth()
        return RepeatCandidate(
            frequency: .yearly,
            interval: interval,
            month: month,
            selector: selector
        )
    }

    private func parseSelector(_ cursor: inout Cursor) throws -> RepeatCandidateSelector {
        if cursor.consumeWord("last") {
            if cursor.consumeWord("day") { return .lastDay }
            return .ordinalWeekday(ordinal: -1, weekday: try cursor.requireWeekday())
        }

        let (ordinal, isNumeric) = try cursor.requireForwardOrNumericOrdinal()
        if cursor.consumeWord("last") {
            guard isNumeric, (2...5).contains(ordinal) else { throw SyntaxFailure.invalid }
            return .ordinalWeekday(ordinal: -ordinal, weekday: try cursor.requireWeekday())
        }
        if cursor.consumeWord("weekday") {
            guard (1...5).contains(ordinal) else { throw SyntaxFailure.invalid }
            return .ordinalDaySet(ordinal: ordinal, daySet: .weekday)
        }
        if cursor.consumeWord("weekend") {
            guard (1...5).contains(ordinal), cursor.consumeWord("day") else {
                throw SyntaxFailure.invalid
            }
            return .ordinalDaySet(ordinal: ordinal, daySet: .weekend)
        }
        if let weekday = cursor.peekWeekday() {
            guard (1...5).contains(ordinal) else { throw SyntaxFailure.invalid }
            cursor.advance()
            return .ordinalWeekday(ordinal: ordinal, weekday: weekday)
        }
        guard isNumeric, (1...31).contains(ordinal) else { throw SyntaxFailure.invalid }
        return .dayOfMonth(ordinal)
    }

    private func suggestion(for input: String) -> String? {
        guard let lexed = try? EnglishRepeatLexer().lex(input) else { return nil }
        let scalars = Array(input.unicodeScalars)
        var canonicalResults = Set<String>()

        for token in lexed.tokens {
            guard case let .word(original) = token.kind else { continue }
            for replacement in Self.knownWords
            where replacement != original && Self.distance(original, replacement) == 1 {
                let prefix = String(String.UnicodeScalarView(scalars[..<token.scalarRange.lowerBound]))
                let suffix = String(String.UnicodeScalarView(scalars[token.scalarRange.upperBound...]))
                let replaced = prefix + replacement + suffix
                guard let candidate = try? parseExact(replaced),
                      !candidate.requiresSourceResolution,
                      let rule = try? RepeatRuleValidator().validate(
                        candidate,
                        source: Self.validationSource
                      )
                else {
                    continue
                }
                canonicalResults.insert(CanonicalRepeatFormatter().string(for: rule))
            }
        }

        let sorted = canonicalResults.sorted()
        return sorted.count == 1 ? sorted[0] : nil
    }

    private static func distance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        var matrix = Array(
            repeating: Array(repeating: 0, count: b.count + 1),
            count: a.count + 1
        )
        for index in 0...a.count { matrix[index][0] = index }
        for index in 0...b.count { matrix[0][index] = index }
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }

        for row in 1...a.count {
            for column in 1...b.count {
                let substitution = matrix[row - 1][column - 1]
                    + (a[row - 1] == b[column - 1] ? 0 : 1)
                var value = min(
                    matrix[row - 1][column] + 1,
                    matrix[row][column - 1] + 1,
                    substitution
                )
                if row > 1, column > 1,
                   a[row - 1] == b[column - 2], a[row - 2] == b[column - 1]
                {
                    value = min(value, matrix[row - 2][column - 2] + 1)
                }
                matrix[row][column] = value
            }
        }
        return matrix[a.count][b.count]
    }

    private static let validationSource = SourceWallClock(
        year: 2001,
        month: 1,
        day: 1,
        hour: 0,
        minute: 0,
        timeZoneIdentifier: "UTC"
    )

    private static let knownWords: [String] = [
        "every", "hour", "hours", "day", "days", "week", "weeks",
        "month", "months", "year", "years", "weekday", "weekend",
        "on", "the", "last", "first", "second", "third", "fourth", "fifth", "and", "of",
        "monday", "mon", "tuesday", "tue", "wednesday", "wed", "thursday", "thu",
        "friday", "fri", "saturday", "sat", "sunday", "sun",
        "january", "jan", "february", "feb", "march", "mar", "april", "apr",
        "may", "june", "jun", "july", "jul", "august", "aug", "september", "sep",
        "october", "oct", "november", "nov", "december", "dec"
    ]
}

private extension RepeatCandidate {
    var requiresSourceResolution: Bool {
        frequency == .weekly && weekdaySetKind == nil && weekdays.isEmpty
    }
}

private enum SyntaxFailure: Error {
    case invalid
}

private struct Cursor {
    let tokens: [EnglishRepeatLexer.Token]
    var index = 0

    var isAtEnd: Bool { index == tokens.count }

    mutating func advance() { index += 1 }

    func peekWordValue() -> String? {
        guard index < tokens.count, case let .word(word) = tokens[index].kind else { return nil }
        return word
    }

    func peekWord(_ expected: String) -> Bool { peekWordValue() == expected }

    mutating func consumeWord() -> String? {
        guard let word = peekWordValue() else { return nil }
        advance()
        return word
    }

    mutating func consumeWord(_ expected: String) -> Bool {
        guard peekWord(expected) else { return false }
        advance()
        return true
    }

    mutating func requireWord(_ expected: String) throws {
        guard consumeWord(expected) else { throw SyntaxFailure.invalid }
    }

    func peekInteger() -> String? {
        guard index < tokens.count, case let .integer(raw) = tokens[index].kind else { return nil }
        return raw
    }

    mutating func requireDecimalInteger() throws -> Int {
        guard let raw = peekInteger(), raw.first != "0", let value = Int(raw),
              (1...9_999).contains(value)
        else {
            throw SyntaxFailure.invalid
        }
        advance()
        return value
    }

    mutating func consumeComma() -> Bool {
        guard index < tokens.count, tokens[index].kind == .comma else { return false }
        advance()
        return true
    }

    func peekWeekday() -> Weekday? {
        guard let word = peekWordValue() else { return nil }
        return Self.weekdays[word]
    }

    mutating func requireWeekday() throws -> Weekday {
        guard let weekday = peekWeekday() else { throw SyntaxFailure.invalid }
        advance()
        return weekday
    }

    mutating func requireMonth() throws -> Int {
        guard let word = peekWordValue(), let month = Self.months[word] else {
            throw SyntaxFailure.invalid
        }
        advance()
        return month
    }

    mutating func requireForwardOrNumericOrdinal() throws -> (value: Int, isNumeric: Bool) {
        if let word = peekWordValue(), let value = Self.forwardOrdinals[word] {
            advance()
            return (value, false)
        }
        guard index < tokens.count,
              case let .ordinal(numberRaw, suffix) = tokens[index].kind,
              numberRaw.first != "0", let number = Int(numberRaw),
              (1...9_999).contains(number), suffix == Self.ordinalSuffix(number)
        else {
            throw SyntaxFailure.invalid
        }
        advance()
        return (number, true)
    }

    private static func ordinalSuffix(_ value: Int) -> String {
        if (11...13).contains(value % 100) { return "th" }
        return switch value % 10 {
        case 1: "st"
        case 2: "nd"
        case 3: "rd"
        default: "th"
        }
    }

    private static let forwardOrdinals = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5
    ]

    private static let weekdays: [String: Weekday] = [
        "monday": .monday, "mon": .monday,
        "tuesday": .tuesday, "tue": .tuesday,
        "wednesday": .wednesday, "wed": .wednesday,
        "thursday": .thursday, "thu": .thursday,
        "friday": .friday, "fri": .friday,
        "saturday": .saturday, "sat": .saturday,
        "sunday": .sunday, "sun": .sunday
    ]

    private static let months: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2,
        "march": 3, "mar": 3, "april": 4, "apr": 4, "may": 5,
        "june": 6, "jun": 6, "july": 7, "jul": 7, "august": 8, "aug": 8,
        "september": 9, "sep": 9, "october": 10, "oct": 10,
        "november": 11, "nov": 11, "december": 12, "dec": 12
    ]
}
