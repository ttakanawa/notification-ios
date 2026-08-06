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
                    ForEach(Array(value.reasons.enumerated()), id: \.offset) { _, reason in
                        LabeledContent(reason.role.semanticKey) {
                            VStack(alignment: .trailing, spacing: 2) {
                                Label(reason.kind.semanticKey, systemImage: "bell")
                                Text(reason.baseOccurrenceInstant, format: .dateTime)
                                    .environment(
                                        \.timeZone,
                                        sourceTimeZone(for: value) ?? .current
                                    )
                            }
                        }
                    }
                    LabeledContent("reminder.next.source-time") {
                        Text(value.sourceTime, format: .dateTime)
                            .environment(\.timeZone, sourceTimeZone(for: value) ?? .current)
                    }
                    LabeledContent("reminder.next.device-time") {
                        Text(value.deviceLocalTime, format: .dateTime)
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
