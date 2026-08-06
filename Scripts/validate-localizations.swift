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
    let catalogURL: URL
    let sourceRoot: URL?

    func validate() throws -> Int {
        let data: Data
        do {
            data = try Data(contentsOf: catalogURL)
        } catch {
            throw LintFailure(messages: [
                "Unable to read catalog at \(catalogURL.path): \(error.localizedDescription)"
            ])
        }

        let catalog: Catalog
        do {
            catalog = try JSONDecoder().decode(Catalog.self, from: data)
        } catch {
            throw LintFailure(messages: ["Invalid String Catalog JSON: \(error)"])
        }

        var failures: [String] = []
        if catalog.version != "1.0" {
            failures.append("Catalog version must be 1.0, found \(catalog.version).")
        }
        if catalog.sourceLanguage != "en" {
            failures.append("Catalog sourceLanguage must be en, found \(catalog.sourceLanguage).")
        }
        if catalog.strings.isEmpty {
            failures.append("Catalog must contain at least one semantic key.")
        }

        for key in catalog.strings.keys.sorted() {
            guard let entry = catalog.strings[key] else { continue }
            validate(key: key, entry: entry, failures: &failures)
        }

        let undeclaredPluralKeys = catalog.strings.keys.filter { key in
            guard let localizations = catalog.strings[key]?.localizations else { return false }
            return localizations.values.contains { $0.variations?.plural != nil }
                && !declaredPluralKeys.contains(key)
        }
        for key in undeclaredPluralKeys.sorted() {
            failures.append("\(key): plural variations exist but the key is not explicitly declared.")
        }

        for key in declaredPluralKeys.sorted() where catalog.strings[key] == nil {
            failures.append("\(key): explicitly declared plural key is missing from the catalog.")
        }

        if let sourceRoot {
            validateSourceCoverage(
                catalogKeys: Set(catalog.strings.keys),
                sourceRoot: sourceRoot,
                failures: &failures
            )
        }

        guard failures.isEmpty else { throw LintFailure(messages: failures) }
        return catalog.strings.count
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
        catalogKeys: Set<String>,
        sourceRoot: URL,
        failures: inout [String]
    ) {
        let sourceDirectory = sourceRoot.appendingPathComponent("NotificationManager")
        guard let enumerator = FileManager.default.enumerator(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            failures.append("Unable to enumerate app sources at \(sourceDirectory.path).")
            return
        }

        var references: Set<String> = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            references.formUnion(Self.semanticReferences(
                in: Self.excludingAccessibilityIdentifierCalls(from: source)
            ))
        }
        for missing in references.subtracting(catalogKeys).sorted() {
            failures.append("\(missing): referenced by app source but missing from the catalog.")
        }
    }

    private static func excludingAccessibilityIdentifierCalls(from source: String) -> String {
        let marker = ".accessibilityIdentifier"
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
    guard arguments.count == 1 || arguments.count == 3 else {
        throw LintFailure(messages: [
            "Usage: swift Scripts/validate-localizations.swift <catalog> [--source-root <repository>]"
        ])
    }
    let catalogURL = URL(fileURLWithPath: arguments[0]).standardizedFileURL
    let sourceRoot: URL?
    if arguments.count == 3 {
        guard arguments[1] == "--source-root" else {
            throw LintFailure(messages: ["Expected --source-root as the second argument."])
        }
        sourceRoot = URL(fileURLWithPath: arguments[2]).standardizedFileURL
    } else {
        sourceRoot = inferredSourceRoot(catalogURL: catalogURL)
    }

    let count = try LocalizationValidator(catalogURL: catalogURL, sourceRoot: sourceRoot).validate()
    print("Validated \(count) localization keys for English and Japanese.")
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("Localization validation failed:\n\(error)\n".utf8))
    exit(EXIT_FAILURE)
}
