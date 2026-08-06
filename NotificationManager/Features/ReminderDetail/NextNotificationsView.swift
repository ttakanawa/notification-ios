import Foundation
import SwiftUI

struct NextNotificationsView: View {
    let directOSFire: (authoritative: Date, foundationPreview: Date?)?
    let notifications: [PhysicalNotificationPresentation]

    var body: some View {
        if let directOSFire {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("reminder.next.os-fire-authoritative") {
                    Text(directOSFire.authoritative, format: .dateTime)
                }
                .accessibilityIdentifier("reminder-detail.next-os-fire")

                if let preview = directOSFire.foundationPreview {
                    LabeledContent("reminder.next.foundation-preview-reference") {
                        Text(preview, format: .dateTime)
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("reminder-detail.foundation-preview")
                }
            }
        }

        if notifications.isEmpty {
            if directOSFire == nil {
                Text("reminder.next.none")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            ForEach(Array(notifications.prefix(3).enumerated()), id: \.offset) { _, value in
                VStack(alignment: .leading, spacing: 6) {
                    Text(value.alertInstant, format: .dateTime)
                        .font(.headline)
                    Label(value.primaryReason.semanticKey, systemImage: "bell")
                    if value.secondaryEarlyReasonCount > 0 {
                        Text("reminder.next.secondary-early \(value.secondaryEarlyReasonCount)")
                            .font(.subheadline)
                    }
                    LabeledContent("reminder.next.source-time") {
                        Text(value.sourceTime, format: .dateTime)
                            .environment(\.timeZone, sourceTimeZone(for: value) ?? .current)
                    }
                    LabeledContent("reminder.next.device-time") {
                        Text(value.deviceLocalTime, format: .dateTime)
                    }
                    ForEach(Array(value.baseOccurrenceInstants.enumerated()), id: \.offset) {
                        _, occurrence in
                        LabeledContent("reminder.next.base-occurrence") {
                            Text(occurrence, format: .dateTime)
                                .environment(\.timeZone, sourceTimeZone(for: value) ?? .current)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("reminder-detail.next-notification")
            }
        }
    }

    private func sourceTimeZone(for value: PhysicalNotificationPresentation) -> TimeZone? {
        value.sourceTimeZoneIdentifier.flatMap(TimeZone.init(identifier:))
    }
}
