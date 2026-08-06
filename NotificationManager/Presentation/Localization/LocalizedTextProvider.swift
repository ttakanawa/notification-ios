import Foundation

struct LocalizedTextProvider: Sendable {
    typealias Lookup = @Sendable (_ key: String, _ locale: Locale) -> String

    static let live = Self { key, locale in
        String(
            localized: String.LocalizationValue(key),
            table: "Localizable",
            bundle: .main,
            locale: locale
        )
    }

    private let lookup: Lookup

    init(_ lookup: @escaping Lookup) {
        self.lookup = lookup
    }

    func value(for key: String, locale: Locale) -> String {
        lookup(key, locale)
    }
}
