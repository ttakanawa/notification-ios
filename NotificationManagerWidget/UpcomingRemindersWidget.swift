import NotificationManagerWidgetSupport
import SwiftUI
import WidgetKit

struct UpcomingRemindersWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetSnapshotConstants.widgetKind,
            provider: UpcomingRemindersTimelineProvider()
        ) { entry in
            UpcomingRemindersWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName(
            LocalizedStringResource("widget.gallery.title", table: "Widget")
        )
        .description(
            LocalizedStringResource("widget.gallery.description", table: "Widget")
        )
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

#Preview("Small", as: .systemSmall) {
    UpcomingRemindersWidget()
} timeline: {
    UpcomingReminderEntry.preview
}

#Preview("Medium", as: .systemMedium) {
    UpcomingRemindersWidget()
} timeline: {
    UpcomingReminderEntry.preview
}
