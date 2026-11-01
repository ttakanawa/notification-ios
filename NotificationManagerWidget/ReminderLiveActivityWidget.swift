import ActivityKit
import NotificationManagerWidgetSupport
import SwiftUI
import WidgetKit

struct ReminderLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReminderActivityAttributes.self) { context in
            ReminderLiveActivityContent(context: context)
                .padding()
                .activityBackgroundTint(.black.opacity(0.9))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(
                    PunctualDeepLinkCodec().url(for: .reminder(context.attributes.reminderID)))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.isStale ? "bell.slash.fill" : "bell.fill")
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ReminderLiveActivityCountdown(context: context)
                        .font(.headline.monospacedDigit())
                        .frame(maxWidth: 110, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: context.state.title)
                            .font(.headline)
                            .lineLimit(2)
                        ReminderLiveActivityRange(state: context.state)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: context.isStale ? "bell.slash.fill" : "bell.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(Text(verbatim: context.state.title))
            } compactTrailing: {
                ReminderLiveActivityCountdown(context: context)
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: 54)
            } minimal: {
                Image(systemName: context.isStale ? "bell.slash.fill" : "bell.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(Text(verbatim: context.state.title))
            }
            .widgetURL(PunctualDeepLinkCodec().url(for: .reminder(context.attributes.reminderID)))
            .keylineTint(.orange)
        }
    }
}

private struct ReminderLiveActivityContent: View {
    let context: ActivityViewContext<ReminderActivityAttributes>

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: context.isStale ? "bell.slash.fill" : "bell.fill")
                .foregroundStyle(.orange)
                .font(.title2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: context.state.title)
                    .font(.headline)
                    .lineLimit(3)
                ReminderLiveActivityRange(state: context.state)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ReminderLiveActivityCountdown(context: context)
                    .font(.title3.monospacedDigit())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }
}

private struct ReminderLiveActivityRange: View {
    let state: ReminderActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 4) {
            Text(state.startDate, format: .dateTime.month(.abbreviated).day().hour().minute())
            Text(verbatim: "–")
            Text(state.endDate, format: .dateTime.month(.abbreviated).day().hour().minute())
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ReminderLiveActivityCountdown: View {
    let context: ActivityViewContext<ReminderActivityAttributes>

    var body: some View {
        if context.isStale {
            Text(LocalizedStringResource("widget.live-activity.ended", table: "Widget"))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else {
            Text(timerInterval: context.state.startDate...context.state.endDate, countsDown: true)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .accessibilityLabel(
                    Text(LocalizedStringResource("widget.live-activity.remaining", table: "Widget"))
                )
        }
    }
}
