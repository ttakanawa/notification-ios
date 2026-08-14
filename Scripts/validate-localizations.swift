#!/usr/bin/env swift

import Darwin
import Foundation

private let requiredLanguages = ["en", "ja"]
private let requiredPluralBranches: [String: Set<String>] = [
    "en": ["one", "other"],
    "ja": ["other"]
]

// Plural behavior is an explicit product contract. Numeric placeholders in ordinary
// sentences are not assumed to be plural merely because they contain an integer.
private let declaredPluralKeys: Set<String> = [
    "tags.management.count"
]

private struct Catalog: Decodable {
    let sourceLanguage: String
    let strings: [String: CatalogEntry]
    let version: String
}

private enum CatalogTable: String, CaseIterable {
    case Common
    case ReminderForm
    case Reminder
    case NotificationText
    case Settings
    case Tags
    case Recovery

    init?(url: URL) {
        self.init(rawValue: url.deletingPathExtension().lastPathComponent)
    }

    func owns(_ key: String) -> Bool {
        switch self {
        case .Common:
            key.hasPrefix("common.")
        case .ReminderForm:
            ["reminder.form.", "reminder.field.", "reminder.early.",
             "reminder.early-unit.", "reminder.repeat.",
             "reminder.repeat-end.", "reminder.custom."].contains {
                key.hasPrefix($0)
            }
        case .Reminder:
            key.hasPrefix("reminder.")
                && CatalogTable.ReminderForm.owns(key) == false
        case .NotificationText:
            key.hasPrefix("localization.")
        case .Settings:
            key.hasPrefix("settings.") || key.hasPrefix("privacy.")
        case .Tags:
            key.hasPrefix("tags.")
        case .Recovery:
            key.hasPrefix("data_unavailable.")
                || key.hasPrefix("notification_unavailable.")
                || key.hasPrefix("recovery.")
        }
    }
}

private struct LoadedCatalog {
    let table: CatalogTable
    let url: URL
    let catalog: Catalog
}

private struct ValidationSummary {
    let catalogCount: Int
    let keyCount: Int
}

private struct CatalogEntry: Decodable {
    let comment: String?
    let extractionState: String?
    let localizations: [String: CatalogLocalization]?
}

private struct CatalogLocalization: Decodable {
    let stringUnit: CatalogStringUnit?
    let variations: CatalogVariations?
}

private struct CatalogVariations: Decodable {
    let plural: [String: CatalogVariation]?
}

private struct CatalogVariation: Decodable {
    let stringUnit: CatalogStringUnit?
}

private struct CatalogStringUnit: Decodable {
    let state: String
    let value: String
}

private struct PlaceholderSignature: Equatable, CustomStringConvertible {
    let values: [Int: String]

    var description: String {
        values.keys.sorted().map { "\($0):\(values[$0]!)" }.joined(separator: ", ")
    }
}

private struct LintFailure: Error, CustomStringConvertible {
    let messages: [String]

    var description: String { messages.joined(separator: "\n") }
}

private struct LocalizationValidator {
    let catalogURLs: [URL]
    let sourceRoot: URL?

    func validate() throws -> ValidationSummary {
        let loadedCatalogs = try loadCatalogs()
        var failures: [String] = []
        for loaded in loadedCatalogs {
            let catalog = loaded.catalog
            if catalog.version != "1.0" {
                failures.append(
                    "\(loaded.table.rawValue): catalog version must be 1.0, "
                        + "found \(catalog.version)."
                )
            }
            if catalog.sourceLanguage != "en" {
                failures.append(
                    "\(loaded.table.rawValue): catalog sourceLanguage must be en, "
                        + "found \(catalog.sourceLanguage)."
                )
            }
            if catalog.strings.isEmpty {
                failures.append(
                    "\(loaded.table.rawValue): catalog must contain at least one semantic key."
                )
            }

            for key in catalog.strings.keys.sorted() {
                guard let entry = catalog.strings[key] else { continue }
                validate(key: key, entry: entry, failures: &failures)
            }
        }

        var owners: [String: CatalogTable] = [:]
        var entries: [String: CatalogEntry] = [:]
        for loaded in loadedCatalogs {
            for key in loaded.catalog.strings.keys.sorted() {
                if let existing = owners[key] {
                    failures.append(
                        "\(key): duplicate key in \(existing.rawValue) and "
                            + "\(loaded.table.rawValue)."
                    )
                    continue
                }
                owners[key] = loaded.table
                entries[key] = loaded.catalog.strings[key]
                if loaded.table.owns(key) == false {
                    failures.append(
                        "\(key): owned by a different catalog, found in "
                            + "\(loaded.table.rawValue)."
                    )
                }
            }
        }

        let undeclaredPluralKeys = entries.keys.filter { key in
            guard let localizations = entries[key]?.localizations else { return false }
            return localizations.values.contains { $0.variations?.plural != nil }
                && !declaredPluralKeys.contains(key)
        }
        for key in undeclaredPluralKeys.sorted() {
            failures.append("\(key): plural variations exist but the key is not explicitly declared.")
        }

        for key in declaredPluralKeys.sorted() where entries[key] == nil {
            failures.append("\(key): explicitly declared plural key is missing from the catalog.")
        }

        if let sourceRoot {
            validateSourceCoverage(
                owners: owners,
                sourceRoot: sourceRoot,
                failures: &failures
            )
        }

        guard failures.isEmpty else { throw LintFailure(messages: failures) }
        return ValidationSummary(
            catalogCount: loadedCatalogs.count,
            keyCount: owners.count
        )
    }

    private func loadCatalogs() throws -> [LoadedCatalog] {
        var urlsByTable: [CatalogTable: URL] = [:]
        var failures: [String] = []

        for url in catalogURLs {
            guard let table = CatalogTable(url: url) else {
                failures.append(
                    "Unknown catalog table \(url.deletingPathExtension().lastPathComponent)."
                )
                continue
            }
            if urlsByTable[table] != nil {
                failures.append("Duplicate catalog table \(table.rawValue).")
                continue
            }
            urlsByTable[table] = url
        }

        for table in CatalogTable.allCases where urlsByTable[table] == nil {
            failures.append("Missing required catalog table \(table.rawValue).")
        }
        guard failures.isEmpty else { throw LintFailure(messages: failures) }

        return try CatalogTable.allCases.map { table in
            let url = urlsByTable[table]!
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw LintFailure(messages: [
                    "Unable to read catalog at \(url.path): \(error.localizedDescription)"
                ])
            }

            let catalog: Catalog
            do {
                catalog = try JSONDecoder().decode(Catalog.self, from: data)
            } catch {
                throw LintFailure(messages: [
                    "Invalid String Catalog JSON at \(url.path): \(error)"
                ])
            }
            return LoadedCatalog(table: table, url: url, catalog: catalog)
        }
    }

    private func validate(
        key: String,
        entry: CatalogEntry,
        failures: inout [String]
    ) {
        if !Self.isSemanticKey(key) {
            failures.append("\(key): key is not a stable lowercase semantic key.")
        }
        guard let comment = entry.comment?.trimmingCharacters(in: .whitespacesAndNewlines),
              !comment.isEmpty
        else {
            failures.append("\(key): translator comment is missing.")
            return
        }
        if let extractionState = entry.extractionState, extractionState != "manual" {
            failures.append("\(key): extractionState must be manual when present.")
        }

        guard let localizations = entry.localizations else {
            failures.append("\(key): localizations are missing.")
            return
        }
        for language in requiredLanguages where localizations[language] == nil {
            failures.append("\(key): \(language) localization is missing.")
        }
        guard requiredLanguages.allSatisfy({ localizations[$0] != nil }) else { return }

        if declaredPluralKeys.contains(key) {
            validatePlural(
                key: key,
                comment: comment,
                localizations: localizations,
                failures: &failures
            )
        } else {
            validateOrdinary(
                key: key,
                comment: comment,
                localizations: localizations,
                failures: &failures
            )
        }
    }

    private func validateOrdinary(
        key: String,
        comment: String,
        localizations: [String: CatalogLocalization],
        failures: inout [String]
    ) {
        var signatures: [String: PlaceholderSignature] = [:]
        for language in requiredLanguages {
            guard let localization = localizations[language] else { continue }
            if localization.variations?.plural != nil {
                failures.append("\(key): \(language) unexpectedly uses plural variations.")
            }
            guard let unit = localization.stringUnit else {
                failures.append("\(key): \(language) stringUnit is missing.")
                continue
            }
            validate(unit: unit, key: key, language: language, failures: &failures)
            signatures[language] = Self.placeholderSignature(for: unit.value)
        }
        validatePlaceholderCompatibility(
            key: key,
            comment: comment,
            signatures: signatures,
            failures: &failures
        )
    }

    private func validatePlural(
        key: String,
        comment: String,
        localizations: [String: CatalogLocalization],
        failures: inout [String]
    ) {
        var signatures: [String: PlaceholderSignature] = [:]
        for language in requiredLanguages {
            guard let localization = localizations[language] else { continue }
            if localization.stringUnit != nil {
                failures.append("\(key): \(language) plural key must not use a top-level stringUnit.")
            }
            guard let plural = localization.variations?.plural else {
                failures.append("\(key): \(language) plural variation is missing.")
                continue
            }
            let required = requiredPluralBranches[language] ?? ["other"]
            for branch in required where plural[branch] == nil {
                failures.append("\(key): \(language) plural branch \(branch) is missing.")
            }
            for branch in plural.keys.sorted() {
                guard let unit = plural[branch]?.stringUnit else {
                    failures.append("\(key): \(language).\(branch) stringUnit is missing.")
                    continue
                }
                validate(
                    unit: unit,
                    key: key,
                    language: "\(language).\(branch)",
                    failures: &failures
                )
                let signature = Self.placeholderSignature(for: unit.value)
                signatures["\(language).\(branch)"] = signature
            }
        }
        validatePlaceholderCompatibility(
            key: key,
            comment: comment,
            signatures: signatures,
            failures: &failures
        )
    }

    private func validate(
        unit: CatalogStringUnit,
        key: String,
        language: String,
        failures: inout [String]
    ) {
        if unit.state != "translated" {
            failures.append("\(key): \(language) state must be translated, found \(unit.state).")
        }
        if unit.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            failures.append("\(key): \(language) value is empty.")
        }
        let invalidPercents = Self.invalidPercentOffsets(in: unit.value)
        if !invalidPercents.isEmpty {
            failures.append("\(key): \(language) contains invalid percent placeholders.")
        }
    }

    private func validatePlaceholderCompatibility(
        key: String,
        comment: String,
        signatures: [String: PlaceholderSignature],
        failures: inout [String]
    ) {
        guard let reference = signatures.keys.sorted().first.flatMap({ signatures[$0] }) else {
            return
        }
        for language in signatures.keys.sorted() where signatures[language] != reference {
            failures.append(
                "\(key): incompatible placeholder signature for \(language); "
                    + "expected [\(reference)], found [\(signatures[language]!)]."
            )
        }
        guard !reference.values.isEmpty else { return }
        if !comment.localizedCaseInsensitiveContains("placeholder") {
            failures.append("\(key): translator comment must explain placeholder meaning and type.")
        }
    }

    private func validateSourceCoverage(
        owners: [String: CatalogTable],
        sourceRoot: URL,
        failures: inout [String]
    ) {
        let compatibilityCatalog = sourceRoot
            .appendingPathComponent("NotificationManager/Resources/Localizable.xcstrings")
        if FileManager.default.fileExists(atPath: compatibilityCatalog.path) {
            failures.append(
                "Legacy compatibility catalog must not exist at \(compatibilityCatalog.path)."
            )
        }

        let sourceDirectory = sourceRoot.appendingPathComponent("NotificationManager")
        guard let enumerator = FileManager.default.enumerator(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            failures.append("Unable to enumerate app sources at \(sourceDirectory.path).")
            return
        }

        var references: Set<String> = []
        var explicitTableReferences: Set<ExplicitTableReference> = []
        var interpolatedSemanticKeys: Set<String> = []
        var implicitSemanticLookups: Set<ImplicitSemanticLookup> = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let filteredSource = Self.excludingAccessibilityIdentifierCalls(
                from: Self.excludingComments(from: source)
            )
            let executableSource = Self.excludingTripleQuotedStringContents(
                from: filteredSource
            )
            let referenceSource = Self.excludingTextVerbatimCalls(
                from: executableSource
            )
            references.formUnion(Self.semanticReferences(in: referenceSource))
            explicitTableReferences.formUnion(Self.explicitTableReferences(in: executableSource))
            interpolatedSemanticKeys.formUnion(
                Self.interpolatedSemanticKeys(in: executableSource)
            )
            implicitSemanticLookups.formUnion(
                Self.implicitSemanticLookups(in: executableSource)
            )
        }
        for missing in references.subtracting(owners.keys).sorted() {
            failures.append("\(missing): referenced by app source but missing from the catalog.")
        }
        for reference in explicitTableReferences.sorted(by: {
            ($0.key, $0.table) < ($1.key, $1.table)
        }) {
            guard let owner = owners[reference.key], reference.table != owner.rawValue else {
                continue
            }
            failures.append(
                "\(reference.key): source declares table \(reference.table), "
                    + "expected \(owner.rawValue)."
            )
        }
        for key in interpolatedSemanticKeys.sorted() {
            failures.append(
                "\(key): interpolated semantic key must use an explicit catalog format entry."
            )
        }
        for lookup in implicitSemanticLookups.sorted(by: {
            ($0.key, $0.callKind) < ($1.key, $1.callKind)
        }) {
            failures.append(
                "\(lookup.key): implicit \(lookup.callKind) localization lookup "
                    + "must declare an explicit table."
            )
        }
    }

    private struct ExplicitTableReference: Hashable {
        let key: String
        let table: String
    }

    private struct ImplicitSemanticLookup: Hashable {
        let key: String
        let callKind: String
    }

    private static func excludingComments(from source: String) -> String {
        let characters = Array(source)
        var output = characters
        var index = 0
        var isInsideString = false
        var isEscaped = false

        while index < characters.count {
            let character = characters[index]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
                index += 1
                continue
            }
            if character == "\"" {
                isInsideString = true
                index += 1
                continue
            }
            guard character == "/", index + 1 < characters.count else {
                index += 1
                continue
            }

            if characters[index + 1] == "/" {
                while index < characters.count,
                      characters[index] != "\n",
                      characters[index] != "\r" {
                    output[index] = " "
                    index += 1
                }
                continue
            }
            guard characters[index + 1] == "*" else {
                index += 1
                continue
            }

            var depth = 0
            while index < characters.count {
                if index + 1 < characters.count,
                   characters[index] == "/",
                   characters[index + 1] == "*" {
                    output[index] = " "
                    output[index + 1] = " "
                    depth += 1
                    index += 2
                } else if index + 1 < characters.count,
                          characters[index] == "*",
                          characters[index + 1] == "/" {
                    output[index] = " "
                    output[index + 1] = " "
                    depth -= 1
                    index += 2
                    if depth == 0 { break }
                } else {
                    if characters[index] != "\n", characters[index] != "\r" {
                        output[index] = " "
                    }
                    index += 1
                }
            }
        }
        return String(output)
    }

    private static func excludingAccessibilityIdentifierCalls(from source: String) -> String {
        [".accessibilityIdentifier", "AccessibilityIdentifierContainer"].reduce(source) {
            excludingCalls(named: $1, from: $0)
        }
    }

    private static func excludingTextVerbatimCalls(from source: String) -> String {
        let pattern = #"\bText\s*\(\s*verbatim\s*:"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return source
        }

        let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)
        var output = ""
        var cursor = source.startIndex
        for match in expression.matches(in: source, range: fullRange) {
            guard let matchRange = Range(match.range(at: 0), in: source),
                  matchRange.lowerBound >= cursor,
                  let openingParenthesis = source[matchRange].firstIndex(of: "("),
                  let end = callEnd(
                      in: source,
                      openingParenthesis: openingParenthesis
                  )
            else {
                continue
            }
            output.append(contentsOf: source[cursor..<matchRange.lowerBound])
            for character in source[matchRange.lowerBound..<end] {
                output.append(character == "\n" || character == "\r" ? character : " ")
            }
            cursor = end
        }
        output.append(contentsOf: source[cursor...])
        return output
    }

    private static func excludingTripleQuotedStringContents(from source: String) -> String {
        let characters = Array(source)
        var output = characters
        var index = 0

        while index < characters.count {
            guard isTripleQuote(at: index, in: characters) else {
                if characters[index] == "\"" {
                    index = ordinaryStringEnd(startingAt: index, in: characters)
                } else {
                    index += 1
                }
                continue
            }

            mask(index..<(index + 3), in: characters, output: &output)
            index += 3
            while index < characters.count {
                if isTripleQuote(at: index, in: characters) {
                    mask(index..<(index + 3), in: characters, output: &output)
                    index += 3
                    break
                }

                if characters[index] == "\\" {
                    var afterBackslashes = index
                    while afterBackslashes < characters.count,
                          characters[afterBackslashes] == "\\" {
                        afterBackslashes += 1
                    }
                    let slashCount = afterBackslashes - index
                    if slashCount.isMultiple(of: 2) == false,
                       afterBackslashes < characters.count,
                       characters[afterBackslashes] == "(",
                       let openingParenthesis = source.index(
                           source.startIndex,
                           offsetBy: afterBackslashes,
                           limitedBy: source.endIndex
                       ),
                       let callEnd = callEnd(
                           in: source,
                           openingParenthesis: openingParenthesis
                       ) {
                        mask(
                            index..<(afterBackslashes - 1),
                            in: characters,
                            output: &output
                        )
                        index = source.distance(from: source.startIndex, to: callEnd)
                        continue
                    }
                    mask(index..<afterBackslashes, in: characters, output: &output)
                    index = afterBackslashes
                    continue
                }

                mask(index..<(index + 1), in: characters, output: &output)
                index += 1
            }
        }
        return String(output)
    }

    private static func isTripleQuote(
        at index: Int,
        in characters: [Character]
    ) -> Bool {
        index + 2 < characters.count
            && characters[index] == "\""
            && characters[index + 1] == "\""
            && characters[index + 2] == "\""
    }

    private static func ordinaryStringEnd(
        startingAt start: Int,
        in characters: [Character]
    ) -> Int {
        var index = start + 1
        var isEscaped = false
        while index < characters.count {
            let character = characters[index]
            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                return index + 1
            }
            index += 1
        }
        return index
    }

    private static func mask(
        _ range: Range<Int>,
        in characters: [Character],
        output: inout [Character]
    ) {
        for index in range where index >= 0 && index < characters.count {
            if characters[index] != "\n", characters[index] != "\r" {
                output[index] = " "
            }
        }
    }

    private static func excludingCalls(named marker: String, from source: String) -> String {
        var output = ""
        var cursor = source.startIndex

        while let markerRange = source.range(
            of: marker,
            range: cursor..<source.endIndex
        ) {
            output.append(contentsOf: source[cursor..<markerRange.lowerBound])
            guard let callEnd = accessibilityIdentifierCallEnd(
                in: source,
                after: markerRange
            ) else {
                output.append(contentsOf: source[markerRange])
                cursor = markerRange.upperBound
                continue
            }
            for character in source[markerRange.lowerBound..<callEnd] {
                output.append(character == "\n" || character == "\r" ? character : " ")
            }
            cursor = callEnd
        }
        output.append(contentsOf: source[cursor...])
        return output
    }

    private static func accessibilityIdentifierCallEnd(
        in source: String,
        after markerRange: Range<String.Index>
    ) -> String.Index? {
        var index = markerRange.upperBound
        while index < source.endIndex, source[index].isWhitespace {
            index = source.index(after: index)
        }
        guard index < source.endIndex, source[index] == "(" else { return nil }

        return callEnd(in: source, openingParenthesis: index)
    }

    private static func callEnd(
        in source: String,
        openingParenthesis: String.Index
    ) -> String.Index? {
        var index = openingParenthesis
        var depth = 0
        var isInsideString = false
        var isEscaped = false
        while index < source.endIndex {
            let character = source[index]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else if character == "\"" {
                isInsideString = true
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 {
                    return source.index(after: index)
                }
            }
            index = source.index(after: index)
        }
        return nil
    }

    private static func semanticReferences(in source: String) -> Set<String> {
        let pattern = #"\"((?:reminder|settings|tags|common|data_unavailable|notification_unavailable|privacy|recovery|localization)(?:\.[a-z0-9_-]+)+)\""#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return Set(expression.matches(in: source, range: range).compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[valueRange])
        })
    }

    private static func explicitTableReferences(
        in source: String
    ) -> Set<ExplicitTableReference> {
        let semanticKey = "(?:reminder|settings|tags|common|data_unavailable|"
            + "notification_unavailable|privacy|recovery|localization)"
            + "(?:\\.[a-z0-9_-]+)+"
        let pattern = "(?:LocalizedStringResource\\s*\\(\\s*|"
            + "String\\s*\\(\\s*localized\\s*:\\s*)"
            + "\"(\(semanticKey))\""
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return Set(expression.matches(in: source, range: range).compactMap { match in
            guard let matchRange = Range(match.range(at: 0), in: source),
                  let keyRange = Range(match.range(at: 1), in: source),
                  let openingParenthesis = source[matchRange].firstIndex(of: "("),
                  let end = callEnd(
                      in: source,
                      openingParenthesis: openingParenthesis
                  )
            else {
                return nil
            }
            let call = String(source[openingParenthesis..<end])
            guard let table = topLevelStringArgument(named: "table", in: call) else {
                return nil
            }
            return ExplicitTableReference(
                key: String(source[keyRange]),
                table: table
            )
        })
    }

    private static func topLevelStringArgument(
        named name: String,
        in call: String
    ) -> String? {
        let characters = Array(call)
        let nameCharacters = Array(name)
        var parenthesisDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        var isInsideString = false
        var isEscaped = false
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
                index += 1
                continue
            }
            if character == "\"" {
                isInsideString = true
                index += 1
                continue
            }

            switch character {
            case "(": parenthesisDepth += 1
            case ")": parenthesisDepth -= 1
            case "[": bracketDepth += 1
            case "]": bracketDepth -= 1
            case "{": braceDepth += 1
            case "}": braceDepth -= 1
            default: break
            }

            if parenthesisDepth == 1, bracketDepth == 0, braceDepth == 0,
               let value = stringArgumentValue(
                   named: nameCharacters,
                   at: index,
                   in: characters
               ) {
                return value
            }
            index += 1
        }
        return nil
    }

    private static func stringArgumentValue(
        named name: [Character],
        at index: Int,
        in characters: [Character]
    ) -> String? {
        guard index + name.count <= characters.count,
              Array(characters[index..<(index + name.count)]) == name,
              index == 0 || !isIdentifierCharacter(characters[index - 1]),
              index + name.count == characters.count
                || !isIdentifierCharacter(characters[index + name.count])
        else {
            return nil
        }

        var cursor = index + name.count
        while cursor < characters.count, characters[cursor].isWhitespace {
            cursor += 1
        }
        guard cursor < characters.count, characters[cursor] == ":" else { return nil }
        cursor += 1
        while cursor < characters.count, characters[cursor].isWhitespace {
            cursor += 1
        }
        guard cursor < characters.count, characters[cursor] == "\"" else { return nil }
        cursor += 1

        var value = ""
        var isEscaped = false
        while cursor < characters.count {
            let character = characters[cursor]
            if isEscaped {
                value.append(character)
                isEscaped = false
            } else if character == "\\" {
                value.append(character)
                isEscaped = true
            } else if character == "\"" {
                return value
            } else {
                value.append(character)
            }
            cursor += 1
        }
        return nil
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }

    private static let localizedInitializerKinds = [
        "Button",
        "ContentUnavailableView",
        "ControlGroup",
        "DatePicker",
        "DisclosureGroup",
        "Gauge",
        "GroupBox",
        "Label",
        "LabeledContent",
        "Link",
        "Menu",
        "NavigationLink",
        "Picker",
        "ProgressView",
        "Section",
        "SecureField",
        "ShareLink",
        "Stepper",
        "Tab",
        "TableColumn",
        "Text",
        "TextField",
        "Toggle",
        "Window",
        "WindowGroup",
    ]

    private static let localizedModifierKinds = [
        "accessibilityHint",
        "accessibilityLabel",
        "accessibilityValue",
        "alert",
        "badge",
        "confirmationDialog",
        "help",
        "navigationSubtitle",
        "navigationTitle",
    ]

    private static let namedLocalizedArguments = [
        (callKind: "searchable", argument: "prompt"),
    ]

    private static func regularExpressionAlternation(for values: [String]) -> String {
        values
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
    }

    private static func interpolatedSemanticKeys(in source: String) -> Set<String> {
        let semanticKey = "(?:reminder|settings|tags|common|data_unavailable|"
            + "notification_unavailable|privacy|recovery|localization)"
            + "(?:\\.[a-z0-9_-]+)+"
        let initializerKinds = regularExpressionAlternation(for: localizedInitializerKinds)
        let modifierKinds = regularExpressionAlternation(for: localizedModifierKinds)
        let patterns = [
            "\\b(?:LocalizedStringResource|\(initializerKinds))\\s*\\(\\s*"
                + "\"(\(semanticKey))\\s*\\\\\\(",
            "\\.(?:\(modifierKinds))\\s*\\(\\s*"
                + "\"(\(semanticKey))\\s*\\\\\\(",
        ]
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        var keys: Set<String> = []
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            keys.formUnion(expression.matches(in: source, range: range).compactMap { match in
                guard let keyRange = Range(match.range(at: 1), in: source) else { return nil }
                return String(source[keyRange])
            })
        }
        for localizedArgument in namedLocalizedArguments {
            let callKind = NSRegularExpression.escapedPattern(
                for: localizedArgument.callKind
            )
            let callPattern = "\\.\(callKind)\\s*\\("
            guard let expression = try? NSRegularExpression(pattern: callPattern) else {
                continue
            }
            for match in expression.matches(in: source, range: range) {
                guard let matchRange = Range(match.range(at: 0), in: source),
                      let openingParenthesis = source[matchRange].lastIndex(of: "("),
                      let end = callEnd(
                          in: source,
                          openingParenthesis: openingParenthesis
                      )
                else {
                    continue
                }
                let call = String(source[openingParenthesis..<end])
                guard let value = topLevelStringArgument(
                    named: localizedArgument.argument,
                    in: call
                ), let key = interpolatedSemanticKey(in: value) else {
                    continue
                }
                keys.insert(key)
            }
        }
        return keys
    }

    private static func interpolatedSemanticKey(in value: String) -> String? {
        let semanticKey = "(?:reminder|settings|tags|common|data_unavailable|"
            + "notification_unavailable|privacy|recovery|localization)"
            + "(?:\\.[a-z0-9_-]+)+"
        let pattern = "^(\(semanticKey))\\s*\\\\\\("
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = expression.firstMatch(in: value, range: range),
              let keyRange = Range(match.range(at: 1), in: value)
        else {
            return nil
        }
        return String(value[keyRange])
    }

    private static func implicitSemanticLookups(
        in source: String
    ) -> Set<ImplicitSemanticLookup> {
        let semanticKey = "(?:reminder|settings|tags|common|data_unavailable|"
            + "notification_unavailable|privacy|recovery|localization)"
            + "(?:\\.[a-z0-9_-]+)+"
        var lookups: Set<ImplicitSemanticLookup> = []

        let initializerKinds = regularExpressionAlternation(for: localizedInitializerKinds)
        let viewPattern = "\\b(\(initializerKinds))\\s*\\(\\s*"
            + "\"(\(semanticKey))\""
        if let expression = try? NSRegularExpression(pattern: viewPattern) {
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in expression.matches(in: source, range: range) {
                guard let kindRange = Range(match.range(at: 1), in: source),
                      let keyRange = Range(match.range(at: 2), in: source)
                else {
                    continue
                }
                lookups.insert(
                    ImplicitSemanticLookup(
                        key: String(source[keyRange]),
                        callKind: String(source[kindRange])
                    )
                )
            }
        }

        let modifierKinds = regularExpressionAlternation(for: localizedModifierKinds)
        let modifierPattern = "\\.(\(modifierKinds))\\s*\\(\\s*\"(\(semanticKey))\""
        if let expression = try? NSRegularExpression(pattern: modifierPattern) {
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in expression.matches(in: source, range: range) {
                guard let kindRange = Range(match.range(at: 1), in: source),
                      let keyRange = Range(match.range(at: 2), in: source)
                else {
                    continue
                }
                lookups.insert(
                    ImplicitSemanticLookup(
                        key: String(source[keyRange]),
                        callKind: String(source[kindRange])
                    )
                )
            }
        }

        for localizedArgument in namedLocalizedArguments {
            let callKind = NSRegularExpression.escapedPattern(
                for: localizedArgument.callKind
            )
            let callPattern = "\\.\(callKind)\\s*\\("
            guard let expression = try? NSRegularExpression(pattern: callPattern) else {
                continue
            }
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in expression.matches(in: source, range: range) {
                guard let matchRange = Range(match.range(at: 0), in: source),
                      let openingParenthesis = source[matchRange].lastIndex(of: "("),
                      let end = callEnd(
                          in: source,
                          openingParenthesis: openingParenthesis
                      )
                else {
                    continue
                }
                let call = String(source[openingParenthesis..<end])
                guard let key = topLevelStringArgument(
                    named: localizedArgument.argument,
                    in: call
                ), isSemanticKey(key) else {
                    continue
                }
                lookups.insert(
                    ImplicitSemanticLookup(
                        key: key,
                        callKind: "\(localizedArgument.callKind)(\(localizedArgument.argument):)"
                    )
                )
            }
        }

        let resourcePattern = "\\bLocalizedStringResource\\s*\\(\\s*"
            + "\"(\(semanticKey))\""
        if let expression = try? NSRegularExpression(pattern: resourcePattern) {
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in expression.matches(in: source, range: range) {
                guard let matchRange = Range(match.range(at: 0), in: source),
                      let keyRange = Range(match.range(at: 1), in: source),
                      let openingParenthesis = source[matchRange].firstIndex(of: "("),
                      let end = callEnd(
                          in: source,
                          openingParenthesis: openingParenthesis
                      )
                else {
                    continue
                }
                let call = String(source[openingParenthesis..<end])
                guard topLevelStringArgument(named: "table", in: call) == nil else {
                    continue
                }
                lookups.insert(
                    ImplicitSemanticLookup(
                        key: String(source[keyRange]),
                        callKind: "LocalizedStringResource"
                    )
                )
            }
        }

        let stringPattern = "\\bString\\s*\\(\\s*localized\\s*:\\s*"
            + "\"(\(semanticKey))\""
        if let expression = try? NSRegularExpression(pattern: stringPattern) {
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in expression.matches(in: source, range: range) {
                guard let matchRange = Range(match.range(at: 0), in: source),
                      let keyRange = Range(match.range(at: 1), in: source),
                      let openingParenthesis = source[matchRange].firstIndex(of: "("),
                      let end = callEnd(
                          in: source,
                          openingParenthesis: openingParenthesis
                      )
                else {
                    continue
                }
                let call = String(source[openingParenthesis..<end])
                guard topLevelStringArgument(named: "table", in: call) == nil else {
                    continue
                }
                lookups.insert(
                    ImplicitSemanticLookup(
                        key: String(source[keyRange]),
                        callKind: "String(localized:)"
                    )
                )
            }
        }

        return lookups
    }

    private static func isSemanticKey(_ key: String) -> Bool {
        let pattern = #"^[a-z][a-z0-9_]*(?:\.[a-z0-9][a-z0-9_-]*)+$"#
        return key.range(of: pattern, options: .regularExpression) != nil
    }

    private static func placeholderSignature(for value: String) -> PlaceholderSignature {
        let matches = placeholderMatches(in: value)
        var nextSequentialPosition = 1
        var values: [Int: String] = [:]
        for match in matches {
            let position: Int
            if let explicit = match.position {
                position = explicit
            } else {
                position = nextSequentialPosition
                nextSequentialPosition += 1
            }
            values[position] = "\(match.length)\(match.type)"
        }
        return PlaceholderSignature(values: values)
    }

    private static func invalidPercentOffsets(in value: String) -> [Int] {
        let validRanges = placeholderMatches(in: value).map(\.range)
        let scalars = Array(value.utf8)
        var invalid: [Int] = []
        var index = 0
        while index < scalars.count {
            guard scalars[index] == Character("%").asciiValue else {
                index += 1
                continue
            }
            if index + 1 < scalars.count, scalars[index + 1] == Character("%").asciiValue {
                index += 2
                continue
            }
            if !validRanges.contains(where: { $0.contains(index) }) {
                invalid.append(index)
            }
            index += 1
        }
        return invalid
    }

    private struct PlaceholderMatch {
        let position: Int?
        let length: String
        let type: String
        let range: Range<Int>
    }

    private static func placeholderMatches(in value: String) -> [PlaceholderMatch] {
        let pattern = #"%(?:(\d+)\$)?[-+#0 ']*(?:\d+|\*)?(?:\.(?:\d+|\*))?(hh|h|ll|l|L|z|t|j|q)?([@diuoxXfFeEgGaAcCsSp])"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, range: range).compactMap { match in
            guard let fullRange = Range(match.range(at: 0), in: value) else { return nil }
            let utf8Lower = value.utf8.distance(
                from: value.utf8.startIndex,
                to: fullRange.lowerBound.samePosition(in: value.utf8)!
            )
            let utf8Upper = value.utf8.distance(
                from: value.utf8.startIndex,
                to: fullRange.upperBound.samePosition(in: value.utf8)!
            )
            let position = Range(match.range(at: 1), in: value).flatMap {
                Int(value[$0])
            }
            let length = Range(match.range(at: 2), in: value).map {
                String(value[$0])
            } ?? ""
            let type = Range(match.range(at: 3), in: value).map {
                String(value[$0])
            } ?? ""
            return PlaceholderMatch(
                position: position,
                length: length,
                type: type,
                range: utf8Lower..<utf8Upper
            )
        }
    }
}

private func inferredSourceRoot(catalogURL: URL) -> URL? {
    let candidate = catalogURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let appDirectory = candidate.appendingPathComponent("NotificationManager")
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: appDirectory.path, isDirectory: &isDirectory),
          isDirectory.boolValue
    else {
        return nil
    }
    return candidate
}

private func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard !arguments.isEmpty else {
        throw LintFailure(messages: [
            "Usage: swift Scripts/validate-localizations.swift <catalog>... "
                + "[--source-root <repository>]"
        ])
    }

    let catalogArguments: ArraySlice<String>
    let sourceRoot: URL?
    if let sourceRootIndex = arguments.firstIndex(of: "--source-root") {
        guard sourceRootIndex > 0, sourceRootIndex == arguments.count - 2 else {
            throw LintFailure(messages: [
                "Expected one or more catalogs followed by --source-root and a repository path."
            ])
        }
        catalogArguments = arguments[..<sourceRootIndex]
        sourceRoot = URL(
            fileURLWithPath: arguments[sourceRootIndex + 1]
        ).standardizedFileURL
    } else {
        guard arguments.allSatisfy({ !$0.hasPrefix("--") }) else {
            throw LintFailure(messages: [
                "Usage: swift Scripts/validate-localizations.swift <catalog>... "
                    + "[--source-root <repository>]"
            ])
        }
        catalogArguments = arguments[...]
        let firstCatalogURL = URL(
            fileURLWithPath: catalogArguments.first!
        ).standardizedFileURL
        sourceRoot = inferredSourceRoot(catalogURL: firstCatalogURL)
    }

    let catalogURLs = catalogArguments.map {
        URL(fileURLWithPath: $0).standardizedFileURL
    }
    let summary = try LocalizationValidator(
        catalogURLs: catalogURLs,
        sourceRoot: sourceRoot
    ).validate()
    print(
        "Validated \(summary.keyCount) localization keys across "
            + "\(summary.catalogCount) catalogs for English and Japanese."
    )
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("Localization validation failed:\n\(error)\n".utf8))
    exit(EXIT_FAILURE)
}
