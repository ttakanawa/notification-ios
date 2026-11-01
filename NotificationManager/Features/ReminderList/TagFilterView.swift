import SwiftUI

struct TagFilterView: View {
    let tags: [ReminderTagPresentation]
    @Binding var selectedTagID: UUID?

    var body: some View {
        Section {
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
            .listRowInsets(
                EdgeInsets(
                    top: 8,
                    leading: 16,
                    bottom: 8,
                    trailing: 0
                )
            )
            .listRowSeparator(.hidden)
        }
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
            .foregroundStyle(selected ? Color.white : Color.accentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background {
                Capsule()
                    .fill(selected ? Color.accentColor : Color.clear)
            }
            .overlay {
                Capsule()
                    .strokeBorder(
                        selected ? Color.clear : Color.secondary.opacity(0.3),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
