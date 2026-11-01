import SwiftUI

struct TimeZoneFilterView: View {
    let identifiers: [String]
    @Binding var selectedIdentifier: String?

    var body: some View {
        Section {
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
                Label {
                    Text(verbatim: selectedTimeZoneName)
                } icon: {
                    Image(systemName: "globe")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
        }
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
