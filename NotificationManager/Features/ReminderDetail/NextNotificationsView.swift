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
                LabeledContent {
                    Text(directOSFire.authoritative, format: .dateTime)
                } label: {
                    Text(LocalizedStringResource(
                        "reminder.next.os-fire-authoritative",
                        table: "Reminder"
                    ))
                }
                .accessibilityIdentifier("reminder-detail.next-os-fire")

                if let preview = directOSFire.foundationPreview {
                    LabeledContent {
                        Text(preview, format: .dateTime)
                    } label: {
                        Text(LocalizedStringResource(
                            "reminder.next.foundation-preview-reference",
                            table: "Reminder"
                        ))
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("reminder-detail.foundation-preview")
                }
            }
        }

        if notifications.isEmpty {
            if directOSFire == nil {
                Text(LocalizedStringResource(
                    "reminder.next.none",
                    table: "Reminder"
                ))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            ForEach(Array(notifications.prefix(3).enumerated()), id: \.offset) { _, value in
                VStack(alignment: .leading, spacing: 6) {
                    Text(value.alertInstant, format: .dateTime)
                        .font(.headline)
                    ForEach(Array(value.reasons.enumerated()), id: \.offset) { _, reason in
                        LabeledContent {
                            VStack(alignment: .trailing, spacing: 2) {
                                Label(reason.kind.localizedResource, systemImage: "bell")
                                Text(
                                    verbatim: sourceFormatter.instant(
                                        reason.baseOccurrenceInstant,
                                        timeZoneIdentifier: sourceTimeZoneIdentifier(for: value),
                                        locale: locale
                                    )
                                )
                            }
                        } label: {
                            Text(reason.role.localizedResource)
                        }
                    }
                    LabeledContent {
                        Text(
                            verbatim: sourceFormatter.instant(
                                value.sourceTime,
                                timeZoneIdentifier: sourceTimeZoneIdentifier(for: value),
                                locale: locale
                            )
                        )
                    } label: {
                        Text(LocalizedStringResource(
                            "reminder.next.source-time",
                            table: "Reminder"
                        ))
                    }
                    LabeledContent {
                        Text(value.deviceLocalTime, format: .dateTime)
                    } label: {
                        Text(LocalizedStringResource(
                            "reminder.next.device-time",
                            table: "Reminder"
                        ))
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
