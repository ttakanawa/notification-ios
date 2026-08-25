public struct EnglishRepeatCandidateGenerator: Sendable {
    public static let maxRepairCost = 2
    public static let maxDisplayedCandidates = 5
    static let maxExploredVariants = 512

    public init() {}

    public func suggestions(for input: String) -> [String] {
        guard case .failure = EnglishRepeatParser().parse(input),
            let lexed = try? EnglishRepeatLexer().lex(input)
        else { return [] }
        return repairedVariants(from: lexed)
            .compactMap(validatedSuggestion)
            .reduce(into: [String: RepairRank]()) { result, value in
                result[value.canonical] = min(result[value.canonical] ?? value.rank, value.rank)
            }
            .sorted { lhs, rhs in
                lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key < rhs.key
            }
            .prefix(Self.maxDisplayedCandidates)
            .map(\.key)
    }

    private func repairedVariants(from lexed: EnglishRepeatLexer.Lexed) -> [RepairedVariant] {
        var variants = weekdaySeparatorNormalization(from: lexed).map { [$0] } ?? []
        var queue = [VariantState(replacements: [:], rank: .zero)]
        var visited = Set([queue[0].key])
        var explored = 0

        while !queue.isEmpty, explored < Self.maxExploredVariants {
            queue.sort(by: VariantState.isHigherPriority)
            let state = queue.removeFirst()
            explored += 1

            if state.rank.totalCost > 0 {
                variants.append(RepairedVariant(rendered: render(lexed, replacements: state.replacements), rank: state.rank))
            }

            for (index, token) in lexed.tokens.enumerated() {
                guard case .word(let original) = token.kind, state.replacements[index] == nil else {
                    continue
                }
                for replacement in Self.grammarVocabulary where replacement != original {
                    let cost = Self.damerauLevenshteinDistance(original, replacement)
                    let rank = RepairRank(
                        totalCost: state.rank.totalCost + cost,
                        operationCount: state.rank.operationCount + 1
                    )
                    guard cost > 0, rank.totalCost <= Self.maxRepairCost else { continue }

                    var replacements = state.replacements
                    replacements[index] = replacement
                    let next = VariantState(replacements: replacements, rank: rank)
                    guard visited.insert(next.key).inserted else { continue }
                    queue.append(next)
                }
            }

            queue.sort(by: VariantState.isHigherPriority)
            let capacity = max(0, Self.maxExploredVariants - explored)
            if queue.count > capacity {
                queue.removeLast(queue.count - capacity)
            }
        }
        return variants
    }

    private func weekdaySeparatorNormalization(
        from lexed: EnglishRepeatLexer.Lexed
    ) -> RepairedVariant? {
        guard let first = lexed.tokens.first,
            first.kind == .word("every")
        else { return nil }

        var index = 1
        var weekdays = [Weekday]()
        while index < lexed.tokens.count {
            guard case .word(let word) = lexed.tokens[index].kind,
                let weekday = Self.weekdays[word]
            else { return nil }
            weekdays.append(weekday)
            index += 1
            guard index < lexed.tokens.count else { break }

            var sawComma = false
            var sawAnd = false
            while index < lexed.tokens.count, isSeparator(lexed.tokens[index].kind) {
                switch lexed.tokens[index].kind {
                case .comma where !sawComma && !sawAnd:
                    sawComma = true
                    index += 1
                case .word("and") where !sawAnd:
                    sawAnd = true
                    index += 1
                default:
                    return nil
                }
            }
            guard index < lexed.tokens.count else { return nil }
        }

        guard (2...7).contains(weekdays.count), Set(weekdays).count == weekdays.count else {
            return nil
        }
        let names = weekdays.sorted { $0.rawValue < $1.rawValue }.map(Self.weekdayName)
        let rendered: String
        if names.count == 2 {
            rendered = "Every \(names[0]) and \(names[1])"
        } else {
            rendered = "Every \(names.dropLast().joined(separator: ", ")), and \(names.last!)"
        }
        return RepairedVariant(
            rendered: rendered,
            rank: RepairRank(totalCost: 1, operationCount: 1)
        )
    }

    private func isSeparator(_ kind: EnglishRepeatLexer.Token.Kind) -> Bool {
        if case .comma = kind { return true }
        if case .word("and") = kind { return true }
        return false
    }

    private func validatedSuggestion(_ variant: RepairedVariant) -> (canonical: String, rank: RepairRank)? {
        guard case .success(let candidate) = EnglishRepeatParser().parse(variant.rendered),
            !isSourceAnchoredWeekly(candidate),
            let rule = try? RepeatRuleValidator().validate(candidate, source: Self.validationSource)
        else { return nil }
        return (CanonicalRepeatFormatter().string(for: rule), variant.rank)
    }

    private func isSourceAnchoredWeekly(_ candidate: RepeatCandidate) -> Bool {
        candidate.frequency == .weekly && candidate.weekdaySetKind == nil && candidate.weekdays.isEmpty
    }

    private func render(
        _ lexed: EnglishRepeatLexer.Lexed,
        replacements: [Int: String]
    ) -> String {
        lexed.tokens.enumerated().reduce(into: "") { rendered, item in
            let (index, token) = item
            switch token.kind {
            case .comma:
                rendered += ","
            case .word(let word):
                appendWord(replacements[index] ?? word, to: &rendered)
            case .integer(let value):
                appendWord(value, to: &rendered)
            case .ordinal(let number, let suffix):
                appendWord(number + suffix, to: &rendered)
            }
        }
    }

    private func appendWord(_ word: String, to rendered: inout String) {
        if !rendered.isEmpty { rendered += " " }
        rendered += word
    }

    private static func damerauLevenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let lhsCharacters = Array(lhs)
        let rhsCharacters = Array(rhs)
        var matrix = Array(
            repeating: Array(repeating: 0, count: rhsCharacters.count + 1),
            count: lhsCharacters.count + 1
        )
        for index in 0...lhsCharacters.count { matrix[index][0] = index }
        for index in 0...rhsCharacters.count { matrix[0][index] = index }

        for row in 1...lhsCharacters.count {
            for column in 1...rhsCharacters.count {
                let substitution = matrix[row - 1][column - 1]
                    + (lhsCharacters[row - 1] == rhsCharacters[column - 1] ? 0 : 1)
                var value = min(
                    matrix[row - 1][column] + 1,
                    matrix[row][column - 1] + 1,
                    substitution
                )
                if row > 1, column > 1,
                    lhsCharacters[row - 1] == rhsCharacters[column - 2],
                    lhsCharacters[row - 2] == rhsCharacters[column - 1]
                {
                    value = min(value, matrix[row - 2][column - 2] + 1)
                }
                matrix[row][column] = value
            }
        }
        return matrix[lhsCharacters.count][rhsCharacters.count]
    }

    private static let validationSource = SourceWallClock(
        year: 2001,
        month: 1,
        day: 1,
        hour: 0,
        minute: 0,
        timeZoneIdentifier: "UTC"
    )

    private static let grammarVocabulary = [
        "every", "hour", "hours", "day", "days", "week", "weeks",
        "month", "months", "year", "years", "weekday", "weekend",
        "on", "the", "last", "first", "second", "third", "fourth", "fifth", "and", "of",
        "monday", "mon", "tuesday", "tue", "wednesday", "wed", "thursday", "thu",
        "friday", "fri", "saturday", "sat", "sunday", "sun",
        "january", "jan", "february", "feb", "march", "mar", "april", "apr",
        "may", "june", "jun", "july", "jul", "august", "aug", "september", "sep",
        "october", "oct", "november", "nov", "december", "dec"
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

    private static func weekdayName(_ weekday: Weekday) -> String {
        ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][weekday.rawValue - 1]
    }
}

private struct RepairRank: Comparable, Equatable {
    static let zero = RepairRank(totalCost: 0, operationCount: 0)

    let totalCost: Int
    let operationCount: Int

    static func < (lhs: RepairRank, rhs: RepairRank) -> Bool {
        lhs.totalCost != rhs.totalCost
            ? lhs.totalCost < rhs.totalCost
            : lhs.operationCount < rhs.operationCount
    }
}

private struct RepairedVariant {
    let rendered: String
    let rank: RepairRank
}

private struct VariantState {
    let replacements: [Int: String]
    let rank: RepairRank

    var key: String {
        replacements.keys.sorted().map { "\($0):\(replacements[$0]!)" }.joined(separator: "|")
    }

    static func isHigherPriority(_ lhs: VariantState, _ rhs: VariantState) -> Bool {
        lhs.rank != rhs.rank ? lhs.rank < rhs.rank : lhs.key < rhs.key
    }
}
