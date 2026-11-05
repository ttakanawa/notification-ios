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
                    ReminderLiveActivityAppIcon(size: 24)
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ReminderLiveActivityRelativeTime(context: context)
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
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            } compactLeading: {
                ReminderLiveActivityAppIcon(size: 20)
                    .accessibilityLabel(Text(verbatim: context.state.title))
            } compactTrailing: {
                ReminderLiveActivityRelativeTime(context: context)
                    .font(.caption.monospacedDigit())
                    .frame(width: 90)
                    .minimumScaleFactor(0.7)
            } minimal: {
                ReminderLiveActivityAppIcon(size: 20)
                    .accessibilityLabel(Text(verbatim: context.state.title))
            }
            .widgetURL(PunctualDeepLinkCodec().url(for: .reminder(context.attributes.reminderID)))
            .keylineTint(.orange)
        }
    }
}

private struct ReminderLiveActivityAppIcon: View {
    let size: CGFloat

    var body: some View {
        Image("LiveActivityAppIcon")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

private struct ReminderLiveActivityContent: View {
    let context: ActivityViewContext<ReminderActivityAttributes>

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ReminderLiveActivityAppIcon(size: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: context.state.title)
                    .font(.headline)
                    .lineLimit(3)
                ReminderLiveActivityRange(state: context.state)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ReminderLiveActivityRelativeTime(context: context)
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
            Text(LocalizedStringResource("widget.live-activity.notification-time", table: "Widget"))
                .lineLimit(1)
                .layoutPriority(1)
            Text(
                state.notificationDate, format: .dateTime.month(.abbreviated).day().hour().minute()
            )
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ReminderLiveActivityRelativeTime: View {
    let context: ActivityViewContext<ReminderActivityAttributes>
    @Environment(\.locale) private var locale

    var body: some View {
        relativeTime
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.65)
    }

    private var relativeTime: Text {
        let afterNotification = context.state.notificationHasOccurred || context.isStale
        if afterNotification {
            let elapsed = ReminderLiveActivityTimePresentation.elapsed(
                since: context.state.notificationDate, until: context.state.activityEndDate
            ).locale(locale)
            return Text(.currentDate, format: elapsed)
                + Text(LocalizedStringResource("widget.live-activity.after", table: "Widget"))
        }
        let countdown = ReminderLiveActivityTimePresentation.countdown(
            startDate: context.state.startDate, notificationDate: context.state.notificationDate
        ).locale(locale)
        return Text(.currentDate, format: countdown)
            + Text(LocalizedStringResource("widget.live-activity.before", table: "Widget"))
    }
}
