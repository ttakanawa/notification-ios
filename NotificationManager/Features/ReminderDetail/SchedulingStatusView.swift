import NotificationManagerDomain
import SwiftUI

struct SchedulingStatusView: View {
    let status: DeviceSchedulingStatus
    let alertGroups: [AlertGroupSchedulingPresentation]
    let scheduledThrough: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(status.localizedResource, systemImage: status.systemImage)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("reminder-detail.device-status")

            if let scheduledThrough {
                LabeledContent {
                    Text(scheduledThrough, format: .dateTime)
                } label: {
                    Text(LocalizedStringResource(
                        "reminder.scheduling.scheduled-through",
                        table: "Reminder"
                    ))
                }
            }

            ForEach(alertGroups) { group in
                HStack(alignment: .firstTextBaseline) {
                    Text(group.groupID.baseOccurrenceInstant, format: .dateTime)
                    Spacer(minLength: 12)
                    Label(group.outcome.localizedResource, systemImage: group.outcome.systemImage)
                }
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
