import Foundation

enum TimeZoneRegionCatalog {
    struct Entry: Sendable {
        let identifier: String
        let regionCode: String
        let isAlias: Bool
    }

    static func regionCode(for identifier: String) -> String? {
        entriesByIdentifier[identifier]?.regionCode
    }

    static func isAlias(_ identifier: String) -> Bool {
        entriesByIdentifier[identifier]?.isAlias == true
    }

    static let entries: [Entry] = {
        guard
            let url = Bundle.main.url(
                forResource: "time-zone-regions",
                withExtension: "tab"
            ),
            let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            assertionFailure("Missing time-zone region catalog")
            return []
        }

        let aliasMarker = "# Foundation-compatible aliases follow."
        let lines = contents.split(whereSeparator: \.isNewline)
        var isReadingAliases = false
        var seenIdentifiers = Set<String>()
        var entries: [Entry] = []

        for line in lines {
            if line == aliasMarker {
                isReadingAliases = true
                continue
            }
            guard !line.hasPrefix("#") else { continue }

            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 2 else {
                assertionFailure("Malformed time-zone region catalog row")
                continue
            }

            let identifier = String(fields[1])
            guard seenIdentifiers.insert(identifier).inserted else {
                assertionFailure("Duplicate time-zone region catalog identifier")
                continue
            }
            entries.append(
                Entry(
                    identifier: identifier,
                    regionCode: String(fields[0]),
                    isAlias: isReadingAliases
                )
            )
        }

        return entries
    }()

    private static let entriesByIdentifier = Dictionary(
        uniqueKeysWithValues: entries.map { ($0.identifier, $0) }
    )
}
