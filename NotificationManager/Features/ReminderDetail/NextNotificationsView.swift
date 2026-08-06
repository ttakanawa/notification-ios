import Foundation
import SwiftUI

struct NextNotificationsView: View {
    @Environment(\.locale) private var locale
    let directOSFire: (authoritative: Date, foundationPreview: Date?)?
    let notifications: [PhysicalNotificationPresentation]

    private let sourceFormatter = SourceDateTimePresentationFormatter()

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
                                Text(
                                    verbatim: sourceFormatter.instant(
                                        reason.baseOccurrenceInstant,
                                        timeZoneIdentifier: sourceTimeZoneIdentifier(for: value),
                                        locale: locale
                                    )
                                )
                            }
                        }
                    }
                    LabeledContent("reminder.next.source-time") {
                        Text(
                            verbatim: sourceFormatter.instant(
                                value.sourceTime,
                                timeZoneIdentifier: sourceTimeZoneIdentifier(for: value),
                                locale: locale
                            )
                        )
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

    private func sourceTimeZoneIdentifier(
        for value: PhysicalNotificationPresentation
    ) -> String {
        value.sourceTimeZoneIdentifier ?? TimeZone.current.identifier
    }
}
