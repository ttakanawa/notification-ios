import SwiftUI

struct TagFilterView: View {
    let tags: [ReminderTagPresentation]
    @Binding var selectedTagID: UUID?

    var body: some View {
        Section {
            Menu {
                Button {
                    selectedTagID = nil
                } label: {
                    filterLabel("reminder.tag-filter.all", selected: selectedTagID == nil)
                }

                ForEach(tags) { tag in
                    Button {
                        selectedTagID = tag.id
                    } label: {
                        Label {
                            Text(verbatim: tag.name)
                        } icon: {
                            Image(systemName: selectedTagID == tag.id ? "checkmark" : "tag")
                        }
                    }
                    .accessibilityIdentifier("reminder.tag-filter.\(tag.id.uuidString.lowercased())")
                }
            } label: {
                Label(selectedTagName, systemImage: "line.3.horizontal.decrease.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("reminder.tag-filter.menu")
        }
    }

    private var selectedTagName: String {
        guard let selectedTagID,
              let tag = tags.first(where: { $0.id == selectedTagID })
        else {
            return String(localized: "reminder.tag-filter.all", defaultValue: "All Tags")
        }
        return tag.name
    }

    private func filterLabel(_ title: LocalizedStringKey, selected: Bool) -> some View {
        Label(title, systemImage: selected ? "checkmark" : "tag")
    }
}
