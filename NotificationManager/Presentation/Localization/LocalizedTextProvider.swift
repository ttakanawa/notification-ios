import Foundation

struct LocalizedTextProvider: Sendable {
    typealias Lookup = @Sendable (_ key: String, _ locale: Locale) -> String

    static let live = Self { key, locale in
        String(
            localized: String.LocalizationValue(key),
            table: "Localizable",
            bundle: bundle(for: locale),
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

    private static func bundle(for locale: Locale) -> Bundle {
        guard let localization = Bundle.preferredLocalizations(
            from: Bundle.main.localizations,
            forPreferences: [locale.identifier]
        ).first,
        let languageBundleURL = Bundle.main.url(
                  forResource: localization,
                  withExtension: "lproj"
              ),
        let languageBundle = Bundle(url: languageBundleURL)
        else {
            return .main
        }
        return languageBundle
    }
}
