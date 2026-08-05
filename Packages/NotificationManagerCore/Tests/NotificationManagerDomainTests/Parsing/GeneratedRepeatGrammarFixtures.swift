import Testing

struct GeneratedRepeatGrammarFixture: Sendable, CustomTestStringConvertible {
    let production: String
    let input: String
    let canonical: String

    var testDescription: String { "\(production): \(input)" }
}

struct GeneratedRejectedRepeatFixture: Sendable, CustomTestStringConvertible {
    let mutation: String
    let input: String

    var testDescription: String { "\(mutation): \(input)" }
}

enum GeneratedRepeatGrammarFixtures {
    static let accepted: [GeneratedRepeatGrammarFixture] =
        simpleFrequencies
        + monthlyRules
        + yearlyRules
        + yearlyMonthSpellings
        + weekdayRules

    static let rejected: [GeneratedRejectedRepeatFixture] =
        numberMutations
        + selectorMutations
        + separatorMutations
        + eofMutations
        + lexicalMutations

    private struct Form {
        let input: String
        let canonical: String
    }

    private static let simpleFrequencies: [GeneratedRepeatGrammarFixture] = {
        let forms = [
            Form(input: "hour", canonical: "hour"),
            Form(input: "1 hour", canonical: "hour"),
            Form(input: "2 hours", canonical: "2 hours"),
            Form(input: "9999 hours", canonical: "9999 hours"),
            Form(input: "day", canonical: "day"),
            Form(input: "1 day", canonical: "day"),
            Form(input: "2 days", canonical: "2 days"),
            Form(input: "9999 days", canonical: "9999 days"),
            Form(input: "week", canonical: "Tuesday"),
            Form(input: "1 week", canonical: "Tuesday"),
            Form(input: "2 weeks", canonical: "2 weeks"),
            Form(input: "9999 weeks", canonical: "9999 weeks"),
            Form(input: "weekday", canonical: "weekday"),
            Form(input: "weekend", canonical: "weekend")
        ]
        return forms.map {
            .init(production: "simple-frequency", input: "Every \($0.input)", canonical: "Every \($0.canonical)")
        }
    }()

    private static let monthlyRules: [GeneratedRepeatGrammarFixture] = {
        var fixtures = monthlyFrequencies.map {
            GeneratedRepeatGrammarFixture(
                production: "monthly-rule without selector",
                input: "Every \($0.input)",
                canonical: "Every \($0.canonical)"
            )
        }
        for frequency in monthlyFrequencies {
            for selector in selectors {
                for article in ["", "the "] {
                    fixtures.append(
                        .init(
                            production: "monthly-rule / \(selector.production)",
                            input: "Every \(frequency.input) on \(article)\(selector.input)",
                            canonical: "Every \(frequency.canonical) on the \(selector.canonical)"
                        )
                    )
                }
            }
        }
        return fixtures
    }()

    private static let yearlyRules: [GeneratedRepeatGrammarFixture] = {
        var fixtures = yearlyFrequencies.map {
            GeneratedRepeatGrammarFixture(
                production: "yearly-rule without selector",
                input: "Every \($0.input)",
                canonical: "Every \($0.canonical)"
            )
        }
        let monthForms = [
            Form(input: "January", canonical: "January"),
            Form(input: "JAN", canonical: "January")
        ]
        for frequency in yearlyFrequencies {
            for selector in selectors {
                for article in ["", "the "] {
                    for month in monthForms {
                        fixtures.append(
                            .init(
                                production: "yearly-rule / \(selector.production)",
                                input: "Every \(frequency.input) on \(article)\(selector.input) of \(month.input)",
                                canonical: "Every \(frequency.canonical) on the \(selector.canonical) of \(month.canonical)"
                            )
                        )
                    }
                }
            }
        }
        return fixtures
    }()

    private static let yearlyMonthSpellings: [GeneratedRepeatGrammarFixture] = {
        let months = [
            ("January", "Jan"), ("February", "Feb"), ("March", "Mar"),
            ("April", "Apr"), ("May", "May"), ("June", "Jun"),
            ("July", "Jul"), ("August", "Aug"), ("September", "Sep"),
            ("October", "Oct"), ("November", "Nov"), ("December", "Dec")
        ]
        return months.flatMap { full, abbreviation in
            let spellings = full == abbreviation
                ? [full, full.uppercased()]
                : [full, abbreviation, abbreviation.uppercased()]
            return spellings.map {
                GeneratedRepeatGrammarFixture(
                    production: "month-name spelling",
                    input: "Every year on the 1st of \($0)",
                    canonical: "Every year on the 1st of \(full)"
                )
            }
        }
    }()

    private static let weekdayRules: [GeneratedRepeatGrammarFixture] = {
        let weekdays = [
            ("Monday", "Mon"), ("Tuesday", "Tue"), ("Wednesday", "Wed"),
            ("Thursday", "Thu"), ("Friday", "Fri"), ("Saturday", "Sat"),
            ("Sunday", "Sun")
        ]
        var fixtures = weekdays.flatMap { full, abbreviation in
            [full, abbreviation, abbreviation.uppercased()].map {
                GeneratedRepeatGrammarFixture(
                    production: "one-item weekday-list",
                    input: "Every \($0)",
                    canonical: "Every \(full)"
                )
            }
        }
        fixtures += [
            .init(production: "two-item weekday-list", input: "Every Monday and Tuesday", canonical: "Every Monday and Tuesday"),
            .init(production: "two-item weekday-list", input: "Every Mon\tand\tTUE", canonical: "Every Monday and Tuesday"),
            .init(production: "two-item weekday-list", input: "Every Sunday and Monday", canonical: "Every Monday and Sunday"),
            .init(production: "two-item duplicate normalization", input: "Every Mon and Monday", canonical: "Every Monday")
        ]

        let abbreviations = weekdays.map(\.1)
        let canonicalNames = weekdays.map(\.0)
        let commaForms = [",", ", ", " ,", " , "]
        for count in 3...7 {
            let inputNames = Array(abbreviations.prefix(count))
            let outputNames = Array(canonicalNames.prefix(count))
            let canonical = "Every " + outputNames.dropLast().joined(separator: ", ") + ", and " + outputNames.last!
            for comma in commaForms {
                fixtures.append(
                    .init(
                        production: "\(count)-item comma-only weekday-list",
                        input: "Every " + inputNames.joined(separator: comma),
                        canonical: canonical
                    )
                )
                fixtures.append(
                    .init(
                        production: "\(count)-item no-Oxford weekday-list",
                        input: "Every " + inputNames.dropLast().joined(separator: comma) + " and " + inputNames.last!,
                        canonical: canonical
                    )
                )
                fixtures.append(
                    .init(
                        production: "\(count)-item Oxford weekday-list",
                        input: "Every " + inputNames.dropLast().joined(separator: comma) + comma + "and " + inputNames.last!,
                        canonical: canonical
                    )
                )
            }
        }
        return fixtures
    }()

    private static let monthlyFrequencies = [
        Form(input: "month", canonical: "month"),
        Form(input: "1 month", canonical: "month"),
        Form(input: "2 months", canonical: "2 months"),
        Form(input: "9999 months", canonical: "9999 months")
    ]

    private static let yearlyFrequencies = [
        Form(input: "year", canonical: "year"),
        Form(input: "1 year", canonical: "year"),
        Form(input: "2 years", canonical: "2 years"),
        Form(input: "9999 years", canonical: "9999 years")
    ]

    private static let selectors: [(production: String, input: String, canonical: String)] = {
        let dayOrdinals = [
            "1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th", "9th", "10th",
            "11th", "12th", "13th", "14th", "15th", "16th", "17th", "18th", "19th", "20th",
            "21st", "22nd", "23rd", "24th", "25th", "26th", "27th", "28th", "29th", "30th", "31st"
        ]
        let forwardOrdinals = [
            ("first", "1st"), ("second", "2nd"), ("third", "3rd"),
            ("fourth", "4th"), ("fifth", "5th")
        ]
        var values = dayOrdinals.map {
            (production: "day-ordinal \($0)", input: $0, canonical: $0)
        }
        values.append(("last day", "last day", "last day"))
        for (word, numeric) in forwardOrdinals {
            values += [
                ("word forward weekday", "\(word) weekday", "\(numeric) weekday"),
                ("numeric forward weekday", "\(numeric) weekday", "\(numeric) weekday"),
                ("word forward weekend day", "\(word) weekend day", "\(numeric) weekend day"),
                ("numeric forward weekend day", "\(numeric) weekend day", "\(numeric) weekend day"),
                ("word forward weekday-position", "\(word) Monday", "\(numeric) Monday"),
                ("numeric forward weekday-position", "\(numeric) Mon", "\(numeric) Monday")
            ]
        }
        values.append(("last weekday-position", "last Wednesday", "last Wednesday"))
        values += ["2nd", "3rd", "4th", "5th"].map {
            ("reverse weekday-position", "\($0) last Fri", "\($0) last Friday")
        }
        return values
    }()

    private static let numberMutations: [GeneratedRejectedRepeatFixture] = {
        let singulars = ["hour", "day", "week", "month", "year"]
        let plurals = ["hours", "days", "weeks", "months", "years"]
        var fixtures: [GeneratedRejectedRepeatFixture] = []
        for plural in plurals {
            fixtures.append(.init(mutation: "singular agreement", input: "Every 1 \(plural)"))
        }
        for singular in singulars {
            fixtures.append(.init(mutation: "plural agreement", input: "Every 2 \(singular)"))
        }
        for plural in plurals {
            fixtures.append(.init(mutation: "zero interval", input: "Every 0 \(plural)"))
            fixtures.append(.init(mutation: "leading-zero interval", input: "Every 01 \(plural)"))
            fixtures.append(.init(mutation: "interval above maximum", input: "Every 10000 \(plural)"))
        }
        return fixtures
    }()

    private static let selectorMutations: [GeneratedRejectedRepeatFixture] = [
        .init(mutation: "day ordinal below range", input: "Every month on the 0th"),
        .init(mutation: "day ordinal above range", input: "Every month on the 32nd"),
        .init(mutation: "word ordinal used as day ordinal", input: "Every month on the first"),
        .init(mutation: "forward weekday below range", input: "Every month on the 0th Monday"),
        .init(mutation: "forward weekday above range", input: "Every month on the 6th Monday"),
        .init(mutation: "reverse weekday below range", input: "Every month on the 1st last Monday"),
        .init(mutation: "reverse weekday above range", input: "Every month on the 6th last Monday"),
        .init(mutation: "last day-set unsupported", input: "Every month on the last weekday"),
        .init(mutation: "invalid fixed February date", input: "Every year on the 30th of February"),
        .init(mutation: "invalid fixed April date", input: "Every year on the 31st of April"),
        .init(mutation: "invalid fixed June date", input: "Every year on the 31st of June"),
        .init(mutation: "invalid fixed September date", input: "Every year on the 31st of September"),
        .init(mutation: "invalid fixed November date", input: "Every year on the 31st of November"),
        .init(mutation: "yearly selector missing month", input: "Every year on the 1st"),
        .init(mutation: "yearly month missing selector", input: "Every year on January"),
        .init(mutation: "incorrect ordinal suffix", input: "Every month on the 1th"),
        .init(mutation: "incorrect ordinal suffix", input: "Every month on the 2th"),
        .init(mutation: "incorrect ordinal suffix", input: "Every month on the 3th"),
        .init(mutation: "incorrect teen ordinal suffix", input: "Every month on the 11st"),
        .init(mutation: "incorrect teen ordinal suffix", input: "Every month on the 12nd"),
        .init(mutation: "incorrect teen ordinal suffix", input: "Every month on the 13rd")
    ]

    private static let separatorMutations: [GeneratedRejectedRepeatFixture] = [
        .init(mutation: "two-item comma", input: "Every Mon, Tue"),
        .init(mutation: "two-item Oxford comma", input: "Every Mon, and Tue"),
        .init(mutation: "missing two-item separator", input: "Every Mon Tue"),
        .init(mutation: "missing three-item comma", input: "Every Mon Tue and Wed"),
        .init(mutation: "multiple and", input: "Every Mon and Tue and Wed"),
        .init(mutation: "empty comma element", input: "Every Mon,,Tue"),
        .init(mutation: "trailing separator", input: "Every Mon, Tue, and"),
        .init(mutation: "more than seven items", input: "Every Mon, Tue, Wed, Thu, Fri, Sat, Sun, Mon")
    ]

    private static let eofMutations: [GeneratedRejectedRepeatFixture] = [
        .init(mutation: "trailing word", input: "Every day please"),
        .init(mutation: "ending until clause", input: "Every weekday until December 31"),
        .init(mutation: "ending count clause", input: "Every week for 20 times"),
        .init(mutation: "time clause", input: "Every Monday at 09:30"),
        .init(mutation: "time-zone clause", input: "Every month UTC")
    ]

    private static let lexicalMutations: [GeneratedRejectedRepeatFixture] = [
        .init(mutation: "missing word-number whitespace", input: "Every2 weeks"),
        .init(mutation: "missing number-word whitespace", input: "Every 2weeks"),
        .init(mutation: "non-ASCII whitespace", input: "Every\u{00A0}week"),
        .init(mutation: "non-ASCII letter", input: "Évery week"),
        .init(mutation: "unsupported punctuation", input: "Every week."),
        .init(mutation: "input above scalar limit", input: String(repeating: " ", count: 247) + "Every week")
    ]
}
