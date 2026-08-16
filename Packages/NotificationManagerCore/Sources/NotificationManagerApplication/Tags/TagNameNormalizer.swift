import NotificationManagerDomain

public struct TagNameNormalizerV1: TagNameNormalizing, Sendable {
    public init() {}

    public func normalize(_ name: String) throws -> String {
        guard name.utf8.count <= TagLimits.nameBytes else {
            throw TagValidationIssue.nameTooLarge
        }

        let input = Self.trimmedDisplayName(name).unicodeScalars.map(\.value)
        var mapped: [UInt32] = []
        mapped.reserveCapacity(input.count)
        for scalar in input {
            if let replacement = UnicodeNormalizationDataV1.nfkcCaseFoldMapping(for: scalar) {
                mapped.append(contentsOf: replacement)
            } else {
                mapped.append(scalar)
            }
        }

        let normalizedScalars = UnicodeNormalizationDataV1.nfc(mapped)
        var scalarView = String.UnicodeScalarView()
        scalarView.reserveCapacity(normalizedScalars.count)
        for scalar in normalizedScalars {
            guard let unicodeScalar = UnicodeScalar(scalar) else {
                preconditionFailure("Normalization data must contain valid Unicode scalars")
            }
            scalarView.append(unicodeScalar)
        }
        let normalized = String(scalarView)

        guard !normalized.isEmpty else {
            throw TagValidationIssue.normalizedNameEmpty
        }
        guard normalized.utf8.count <= TagLimits.normalizedNameBytes else {
            throw TagValidationIssue.normalizedNameTooLarge
        }
        return normalized
    }

    public static func trimmedDisplayName(_ name: String) -> String {
        let input = name.unicodeScalars.map(\.value)
        var lowerBound = input.startIndex
        var upperBound = input.endIndex
        while lowerBound < upperBound,
            UnicodeNormalizationDataV1.isWhiteSpace(input[lowerBound])
        {
            lowerBound += 1
        }
        while upperBound > lowerBound,
            UnicodeNormalizationDataV1.isWhiteSpace(input[upperBound - 1])
        {
            upperBound -= 1
        }

        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(upperBound - lowerBound)
        for value in input[lowerBound..<upperBound] {
            guard let scalar = UnicodeScalar(value) else {
                preconditionFailure("Unicode scalar input must remain valid")
            }
            scalars.append(scalar)
        }
        return String(scalars)
    }
}

enum UnicodeNormalizationDataV1 {
    private struct RangeMapping: Sendable {
        let lowerBound: UInt32
        let upperBound: UInt32
        let replacement: [UInt32]
    }

    private struct ScalarRange: Sendable {
        let lowerBound: UInt32
        let upperBound: UInt32
        let value: UInt8
    }

    private static let whiteSpace = parseRanges(TagNormalizationTablesV1.whiteSpaceRecords)
    private static let nfkcCaseFold = parseMappings(TagNormalizationTablesV1.nfkcCaseFoldRecords)
    private static let canonicalDecompositions = parseScalarMappings(
        TagNormalizationTablesV1.canonicalDecompositionRecords
    )
    private static let combiningClasses = parseValuedRanges(
        TagNormalizationTablesV1.canonicalCombiningClassRecords
    )
    private static let compositions = parseCompositions(TagNormalizationTablesV1.compositionRecords)

    static func isWhiteSpace(_ scalar: UInt32) -> Bool {
        rangeValue(for: scalar, in: whiteSpace) != nil
    }

    static func nfkcCaseFoldMapping(for scalar: UInt32) -> [UInt32]? {
        rangeValue(for: scalar, in: nfkcCaseFold)
    }

    static func nfc(_ scalars: [UInt32]) -> [UInt32] {
        var decomposed: [UInt32] = []
        decomposed.reserveCapacity(scalars.count)
        for scalar in scalars {
            appendCanonicalDecomposition(of: scalar, to: &decomposed)
        }
        reorderCanonicalCombiningMarks(&decomposed)
        return compose(decomposed)
    }

    private static func appendCanonicalDecomposition(of scalar: UInt32, to output: inout [UInt32]) {
        if let hangul = decomposeHangul(scalar) {
            output.append(contentsOf: hangul)
            return
        }
        guard let mapping = canonicalDecompositions[scalar] else {
            output.append(scalar)
            return
        }
        for component in mapping {
            appendCanonicalDecomposition(of: component, to: &output)
        }
    }

    private static func reorderCanonicalCombiningMarks(_ scalars: inout [UInt32]) {
        guard scalars.count > 1 else { return }
        for index in scalars.indices.dropFirst() {
            let currentClass = canonicalCombiningClass(of: scalars[index])
            guard currentClass != 0 else { continue }
            var insertionIndex = index
            while insertionIndex > scalars.startIndex {
                let previousClass = canonicalCombiningClass(of: scalars[insertionIndex - 1])
                guard previousClass != 0, previousClass > currentClass else { break }
                scalars.swapAt(insertionIndex - 1, insertionIndex)
                insertionIndex -= 1
            }
        }
    }

    private static func compose(_ scalars: [UInt32]) -> [UInt32] {
        guard let first = scalars.first else { return [] }
        var output = [first]
        var starterIndex: Int? = canonicalCombiningClass(of: first) == 0 ? 0 : nil
        var starter = first
        var previousClass = canonicalCombiningClass(of: first)

        for scalar in scalars.dropFirst() {
            let currentClass = canonicalCombiningClass(of: scalar)
            if let starterIndex,
                previousClass == 0 || previousClass < currentClass,
                let composite = composite(starter: starter, combining: scalar)
            {
                output[starterIndex] = composite
                starter = composite
                continue
            }

            if currentClass == 0 {
                starterIndex = output.count
                starter = scalar
            }
            output.append(scalar)
            previousClass = currentClass
        }
        return output
    }

    private static func canonicalCombiningClass(of scalar: UInt32) -> UInt8 {
        rangeValue(for: scalar, in: combiningClasses) ?? 0
    }

    private static func composite(starter: UInt32, combining: UInt32) -> UInt32? {
        if let hangul = composeHangul(starter: starter, combining: combining) {
            return hangul
        }
        return compositions[(UInt64(starter) << 21) | UInt64(combining)]
    }

    private static func decomposeHangul(_ scalar: UInt32) -> [UInt32]? {
        let sBase: UInt32 = 0xAC00
        let lBase: UInt32 = 0x1100
        let vBase: UInt32 = 0x1161
        let tBase: UInt32 = 0x11A7
        let lCount: UInt32 = 19
        let vCount: UInt32 = 21
        let tCount: UInt32 = 28
        let nCount = vCount * tCount
        let sCount = lCount * nCount
        guard scalar >= sBase, scalar < sBase + sCount else { return nil }
        let index = scalar - sBase
        let leading = lBase + index / nCount
        let vowel = vBase + (index % nCount) / tCount
        let trailing = tBase + index % tCount
        return trailing == tBase ? [leading, vowel] : [leading, vowel, trailing]
    }

    private static func composeHangul(starter: UInt32, combining: UInt32) -> UInt32? {
        let sBase: UInt32 = 0xAC00
        let lBase: UInt32 = 0x1100
        let vBase: UInt32 = 0x1161
        let tBase: UInt32 = 0x11A7
        let lCount: UInt32 = 19
        let vCount: UInt32 = 21
        let tCount: UInt32 = 28
        let nCount = vCount * tCount
        let sCount = lCount * nCount

        if starter >= lBase, starter < lBase + lCount,
            combining >= vBase, combining < vBase + vCount
        {
            return sBase + (starter - lBase) * nCount + (combining - vBase) * tCount
        }
        if starter >= sBase, starter < sBase + sCount,
            (starter - sBase) % tCount == 0,
            combining > tBase, combining < tBase + tCount
        {
            return starter + combining - tBase
        }
        return nil
    }

    private static func parseMappings(_ records: String) -> [RangeMapping] {
        records.split(separator: "\n").map { line in
            let fields = line.split(separator: ";", omittingEmptySubsequences: false)
            let bounds = parseBounds(fields[0])
            return RangeMapping(
                lowerBound: bounds.lower,
                upperBound: bounds.upper,
                replacement: parseScalars(fields[1])
            )
        }
    }

    private static func parseScalarMappings(_ records: String) -> [UInt32: [UInt32]] {
        Dictionary(
            uniqueKeysWithValues: records.split(separator: "\n").map { line in
                let fields = line.split(separator: ";", omittingEmptySubsequences: false)
                return (requiredHexScalar(fields[0]), parseScalars(fields[1]))
            })
    }

    private static func parseRanges(_ records: String) -> [ScalarRange] {
        records.split(separator: "\n").map { line in
            let bounds = parseBounds(line)
            return ScalarRange(lowerBound: bounds.lower, upperBound: bounds.upper, value: 1)
        }
    }

    private static func parseValuedRanges(_ records: String) -> [ScalarRange] {
        records.split(separator: "\n").map { line in
            let fields = line.split(separator: ";", omittingEmptySubsequences: false)
            let bounds = parseBounds(fields[0])
            return ScalarRange(
                lowerBound: bounds.lower,
                upperBound: bounds.upper,
                value: requiredCombiningClass(fields[1])
            )
        }.sorted { $0.lowerBound < $1.lowerBound }
    }

    private static func parseCompositions(_ records: String) -> [UInt64: UInt32] {
        Dictionary(
            uniqueKeysWithValues: records.split(separator: "\n").map { line in
                let fields = line.split(separator: ";", omittingEmptySubsequences: false)
                let pair = parseScalars(fields[0])
                let key = (UInt64(pair[0]) << 21) | UInt64(pair[1])
                return (key, requiredHexScalar(fields[1]))
            })
    }

    private static func parseBounds(_ field: Substring) -> (lower: UInt32, upper: UInt32) {
        let components = field.split(separator: ".")
        let lower = requiredHexScalar(components[0])
        return (lower, components.count == 1 ? lower : requiredHexScalar(components[1]))
    }

    private static func parseScalars(_ field: Substring) -> [UInt32] {
        field.split(separator: " ").map(requiredHexScalar)
    }

    private static func requiredHexScalar(_ field: Substring) -> UInt32 {
        guard let scalar = UInt32(field, radix: 16) else {
            preconditionFailure("Unicode normalization data contains an invalid hexadecimal scalar")
        }
        return scalar
    }

    private static func requiredCombiningClass(_ field: Substring) -> UInt8 {
        guard let value = UInt8(field) else {
            preconditionFailure("Unicode normalization data contains an invalid combining class")
        }
        return value
    }

    private static func rangeValue(
        for scalar: UInt32,
        in ranges: [RangeMapping]
    ) -> [UInt32]? {
        var lower = ranges.startIndex
        var upper = ranges.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            let range = ranges[middle]
            if scalar < range.lowerBound {
                upper = middle
            } else if scalar > range.upperBound {
                lower = middle + 1
            } else {
                return range.replacement
            }
        }
        return nil
    }

    private static func rangeValue(for scalar: UInt32, in ranges: [ScalarRange]) -> UInt8? {
        var lower = ranges.startIndex
        var upper = ranges.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            let range = ranges[middle]
            if scalar < range.lowerBound {
                upper = middle
            } else if scalar > range.upperBound {
                lower = middle + 1
            } else {
                return range.value
            }
        }
        return nil
    }
}
