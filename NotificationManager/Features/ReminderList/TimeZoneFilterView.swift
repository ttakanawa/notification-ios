import SwiftUI

struct TimeZoneFilterView: View {
    let identifiers: [String]
    @Binding var selectedIdentifier: String?

    var body: some View {
        Menu {
            Button {
                selectedIdentifier = nil
            } label: {
                filterLabel(
                    LocalizedStringResource(
                        "reminder.time-zone-filter.all",
                        table: "Reminder"
                    ),
                    selected: selectedIdentifier == nil
                )
            }
            .accessibilityIdentifier("reminder.time-zone-filter.all")

            ForEach(identifiers, id: \.self) { identifier in
                Button {
                    selectedIdentifier = identifier
                } label: {
                    Label {
                        Text(verbatim: identifier)
                    } icon: {
                        Image(
                            systemName: selectedIdentifier == identifier
                                ? "checkmark"
                                : "globe"
                        )
                    }
                }
                .accessibilityIdentifier("reminder.time-zone-filter.\(identifier)")
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .foregroundStyle(Color.secondary)
                    .accessibilityHidden(true)
                Text(verbatim: selectedTimeZoneName)
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .accessibilityHidden(true)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 44)
        }
        .accessibilityIdentifier("reminder.time-zone-filter.menu")
        .accessibilityLabel(
            Text(
                LocalizedStringResource(
                    "reminder.time-zone-filter.menu",
                    table: "Reminder"
                )
            )
        )
        .accessibilityValue(Text(verbatim: selectedTimeZoneName))
        .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var selectedTimeZoneName: String {
        selectedIdentifier
            ?? String(
                localized: "reminder.time-zone-filter.all",
                defaultValue: "All Time Zones",
                table: "Reminder"
            )
    }

    private func filterLabel(_ title: LocalizedStringResource, selected: Bool) -> some View {
        Label(title, systemImage: selected ? "checkmark" : "globe")
    }
}
