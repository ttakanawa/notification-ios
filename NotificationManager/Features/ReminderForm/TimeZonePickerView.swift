import Foundation
import SwiftUI

struct TimeZoneChoice: Identifiable, Sendable, Equatable {
    let identifier: String
    let locationName: String
    let localizedName: String?
    let abbreviation: String?

    var id: String { identifier }

    var detailName: String? {
        switch (localizedName, abbreviation) {
        case (let localizedName?, let abbreviation?)
        where localizedName.compare(
            abbreviation,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != .orderedSame:
            return "\(localizedName) (\(abbreviation))"
        case (let localizedName?, _):
            return localizedName
        case (_, let abbreviation?):
            return abbreviation
        case (nil, nil):
            return nil
        }
    }

    static func all(
        locale: Locale,
        at date: Date = .now,
        preservingIdentifier: String? = nil
    ) -> [TimeZoneChoice] {
        var identifiers = Set(TimeZone.knownTimeZoneIdentifiers)
        if let preservingIdentifier,
            TimeZone(identifier: preservingIdentifier) != nil
        {
            identifiers.insert(preservingIdentifier)
        }

        let choices: [TimeZoneChoice] = identifiers.compactMap { identifier in
            guard let timeZone = TimeZone(identifier: identifier) else { return nil }
            return TimeZoneChoice(
                identifier: identifier,
                locationName: locationName(
                    for: timeZone,
                    at: date,
                    locale: locale
                ),
                localizedName: timeZone.localizedName(for: .generic, locale: locale),
                abbreviation: timeZone.abbreviation(for: date)
            )
        }
        .filter {
            !TimeZoneRegionCatalog.isAlias($0.identifier)
                || $0.identifier == preservingIdentifier
        }
        .sorted {
            if $0.identifier == preservingIdentifier { return true }
            if $1.identifier == preservingIdentifier { return false }
            return $0.identifier < $1.identifier
        }

        var seenPresentations = Set<Presentation>()
        return choices.filter { choice in
            seenPresentations.insert(
                Presentation(
                    locationName: choice.locationName,
                    detailName: choice.detailName
                )
            ).inserted
        }
        .sorted { $0.identifier < $1.identifier }
    }

    func matches(query: String) -> Bool {
        query.isEmpty
            || identifier.localizedCaseInsensitiveContains(query)
            || identifier
                .replacingOccurrences(of: "/", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .localizedCaseInsensitiveContains(query)
            || locationName.localizedCaseInsensitiveContains(query)
            || localizedName?.localizedCaseInsensitiveContains(query) == true
            || abbreviation?.localizedCaseInsensitiveContains(query) == true
            || detailName?.localizedCaseInsensitiveContains(query) == true
    }

    private static func locationName(
        for timeZone: TimeZone,
        at date: Date,
        locale: Locale
    ) -> String {
        let formatStyle = Date.FormatStyle(locale: locale, timeZone: timeZone)
        let city = date.formatted(formatStyle.timeZone(.exemplarLocation))

        if let regionCode = TimeZoneRegionCatalog.regionCode(for: timeZone.identifier),
            let country = locale.localizedString(forRegionCode: regionCode)
        {
            return [city, country].formatted(
                .list(type: .and, width: .narrow).locale(locale)
            )
        }

        return date.formatted(formatStyle.timeZone(.genericLocation))
    }

    private struct Presentation: Hashable {
        let locationName: String
        let detailName: String?
    }
}

actor TimeZoneChoiceLoader {
    static let shared = TimeZoneChoiceLoader()

    private var cachedChoices: [CacheKey: [TimeZoneChoice]] = [:]

    func choices(
        locale: Locale,
        at date: Date = .now,
        preservingIdentifier: String?
    ) -> [TimeZoneChoice] {
        let key = CacheKey(
            localeIdentifier: locale.identifier,
            minute: Int(date.timeIntervalSinceReferenceDate / 60),
            preservingIdentifier: preservingIdentifier
        )
        if let cached = cachedChoices[key] {
            return cached
        }

        let choices = TimeZoneChoice.all(
            locale: locale,
            at: date,
            preservingIdentifier: preservingIdentifier
        )
        cachedChoices = [key: choices]
        return choices
    }

    private struct CacheKey: Hashable {
        let localeIdentifier: String
        let minute: Int
        let preservingIdentifier: String?
    }
}

struct TimeZonePickerView: View {
    let selectedIdentifier: String?
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var query = ""
    @State private var choices: [TimeZoneChoice]?

    init(
        selectedIdentifier: String?,
        onSelect: @escaping (String) -> Void
    ) {
        self.selectedIdentifier = selectedIdentifier
        self.onSelect = onSelect
    }

    var body: some View {
        let filteredChoices = choices?.filter { $0.matches(query: query) }

        NavigationStack {
            List {
                TextField(text: $query) {
                    Text(
                        LocalizedStringResource(
                            "reminder.form.time-zone-picker.search",
                            table: "ReminderForm"
                        ))
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("reminder-form.time-zone-search")

                if let filteredChoices {
                    choiceRows(filteredChoices)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(
                LocalizedStringResource(
                    "reminder.form.time-zone-picker.title",
                    table: "ReminderForm"
                ))
        }
        .accessibilityIdentifier("reminder-form.time-zone-picker")
        .task(id: locale.identifier) {
            choices = nil
            let loadedChoices = await TimeZoneChoiceLoader.shared.choices(
                locale: locale,
                preservingIdentifier: selectedIdentifier
            )
            guard !Task.isCancelled else { return }
            choices = loadedChoices
        }
    }

    @ViewBuilder
    private func choiceRows(_ filteredChoices: [TimeZoneChoice]) -> some View {
        if filteredChoices.isEmpty {
            Text(
                LocalizedStringResource(
                    "reminder.form.time-zone-picker.empty",
                    table: "ReminderForm"
                )
            )
            .foregroundStyle(.secondary)
        } else {
            ForEach(filteredChoices) { choice in
                Button {
                    onSelect(choice.identifier)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(choice.locationName)
                            if let detailName = choice.detailName {
                                Text(detailName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if choice.identifier == selectedIdentifier {
                            Image(systemName: "checkmark")
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(
                    "reminder-form.time-zone-option.\(choice.identifier)"
                )
                .accessibilityAddTraits(
                    choice.identifier == selectedIdentifier ? .isSelected : []
                )
            }
        }
    }
}
