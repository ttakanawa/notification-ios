import NotificationManagerDomain
import SwiftUI

struct SchedulingStatusView: View {
    let status: DeviceSchedulingStatus
    let alertGroups: [AlertGroupSchedulingPresentation]
    let scheduledThrough: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(status.semanticKey, systemImage: status.systemImage)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("reminder-detail.device-status")

            if let scheduledThrough {
                LabeledContent("reminder.scheduling.scheduled-through") {
                    Text(scheduledThrough, format: .dateTime)
                }
            }

            ForEach(alertGroups) { group in
                HStack(alignment: .firstTextBaseline) {
                    Text(group.groupID.baseOccurrenceInstant, format: .dateTime)
                    Spacer(minLength: 12)
                    Label(group.outcome.semanticKey, systemImage: group.outcome.systemImage)
                }
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
