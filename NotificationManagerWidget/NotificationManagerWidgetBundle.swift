import SwiftUI
import WidgetKit

@main
struct NotificationManagerWidgetBundle: WidgetBundle {
    var body: some Widget {
        UpcomingRemindersWidget()
        ReminderLiveActivityWidget()
        if #available(iOS 26.0, *) {
            AlarmKitTrialLiveActivity()
        }
    }
}
