import SwiftUI

struct TagFilterView: View {
    let tags: [ReminderTagPresentation]
    @Binding var selectedTagID: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterButton(
                    title: Text(
                        LocalizedStringResource(
                            "reminder.tag-filter.all",
                            table: "Reminder"
                        )
                    ),
                    tagID: nil,
                    identifier: "reminder.tag-filter.all"
                )

                ForEach(tags) { tag in
                    filterButton(
                        title: Text(verbatim: tag.name),
                        tagID: tag.id,
                        identifier: "reminder.tag-filter.\(tag.id.uuidString.lowercased())"
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("reminder.tag-filter.scroll")
        .listRowBackground(Color.clear)
        .listRowInsets(
            EdgeInsets(
                top: 0,
                leading: 0,
                bottom: 0,
                trailing: 0
            )
        )
        .listRowSeparator(.hidden)
    }

    private func filterButton(
        title: Text,
        tagID: UUID?,
        identifier: String
    ) -> some View {
        let selected = selectedTagID == tagID

        return Button {
            selectedTagID = tagID
        } label: {
            Label {
                title
                    .lineLimit(1)
            } icon: {
                Image(systemName: selected ? "checkmark" : "tag")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(
                selected
                    ? Color.accentColor.opacity(0.15)
                    : Color(uiColor: .tertiarySystemFill),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
