import SwiftUI
import WidgetKit

@main
struct NotificationManagerWidgetBundle: WidgetBundle {
    var body: some Widget {
        UpcomingRemindersWidget()
        ReminderLiveActivityWidget()
    }
}
