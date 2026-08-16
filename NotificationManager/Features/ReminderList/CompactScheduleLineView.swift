import SwiftUI

struct CompactScheduleLineView: View {
    @Environment(\.locale) private var locale
    let presentation: CompactScheduleTimePresentation?
    let localizedRepeatSummary: String?

    private let localizer = LocalizedTextProvider.live

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                timeContent
                repeatContent
            }
            VStack(alignment: .leading, spacing: 2) {
                timeContent
                repeatContent
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reminder-row.compact-schedule")
    }

    private var repeatSummary: String? {
        let trimmed = localizedRepeatSummary?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    @ViewBuilder
    private var timeContent: some View {
        if let presentation {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: presentation.localTime)
                if let sourceTime = presentation.sourceTime,
                    let sourceZone = presentation.sourceTimeZoneLabel
                {
                    Text(verbatim: "(\(sourceTime)")
                    if let dayOffsetLabel = presentation.dayOffsetLabel {
                        Text(verbatim: dayOffsetLabel)
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                Color.secondary.opacity(0.18),
                                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                            )
                            .accessibilityLabel(
                                Text(
                                    verbatim: presentation.accessibilityDayOffsetLabel
                                        ?? dayOffsetLabel
                                )
                            )
                            .accessibilityIdentifier("reminder-row.day-offset")
                    }
                    Text(verbatim: "\(sourceZone))")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("reminder-row.times")
        }
    }

    @ViewBuilder
    private var repeatContent: some View {
        if let repeatSummary {
            Label {
                Text(verbatim: repeatSummary)
            } icon: {
                Image(systemName: "repeat")
            }
            .labelStyle(.titleAndIcon)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text(verbatim: localizer.value(for: "reminder.field.repeat", locale: locale))
            )
            .accessibilityValue(Text(verbatim: repeatSummary))
            .accessibilityIdentifier("reminder-row.recurrence")
        }
    }
}
