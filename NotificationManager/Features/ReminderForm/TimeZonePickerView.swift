import Foundation
import SwiftUI

struct TimeZoneChoice: Identifiable, Sendable, Equatable {
    let identifier: String
    let localizedName: String?

    var id: String { identifier }

    static func all(locale: Locale) -> [TimeZoneChoice] {
        TimeZone.knownTimeZoneIdentifiers.compactMap { identifier in
            guard let timeZone = TimeZone(identifier: identifier) else { return nil }
            return TimeZoneChoice(
                identifier: identifier,
                localizedName: timeZone.localizedName(for: .generic, locale: locale)
            )
        }
        .sorted { $0.identifier < $1.identifier }
    }

    func matches(query: String) -> Bool {
        query.isEmpty
            || identifier.localizedCaseInsensitiveContains(query)
            || localizedName?.localizedCaseInsensitiveContains(query) == true
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
        .onChange(of: locale.identifier, initial: true) {
            choices = TimeZoneChoice.all(locale: locale)
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
                            Text(choice.identifier)
                            if let localizedName = choice.localizedName {
                                Text(localizedName)
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
