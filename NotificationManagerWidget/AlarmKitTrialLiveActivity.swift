import ActivityKit
import AlarmKit
import NotificationManagerWidgetSupport
import SwiftUI
import WidgetKit

@available(iOS 26.0, *)
struct AlarmKitTrialLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<AlarmKitTrialMetadata>.self) { context in
            HStack(alignment: .top, spacing: 12) {
                AlarmKitTrialAppIcon(size: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    title(for: context.attributes)
                        .font(.headline)
                        .lineLimit(3)
                    AlarmKitTrialCountdown(state: context.state)
                        .font(.title2.monospacedDigit())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .foregroundStyle(.primary)
            .activityBackgroundTint(Color(uiColor: .secondarySystemGroupedBackground))
            .activitySystemActionForegroundColor(.blue)
            .accessibilityElement(children: .combine)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    AlarmKitTrialAppIcon(size: 24)
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    AlarmKitTrialCountdown(state: context.state)
                        .font(.headline.monospacedDigit())
                        .frame(maxWidth: 110, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    title(for: context.attributes)
                        .font(.headline)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            } compactLeading: {
                AlarmKitTrialAppIcon(size: 20)
                    .accessibilityLabel(title(for: context.attributes))
            } compactTrailing: {
                AlarmKitTrialCountdown(state: context.state)
                    .font(.caption.monospacedDigit())
                    .frame(width: 70)
            } minimal: {
                AlarmKitTrialAppIcon(size: 20)
                    .accessibilityLabel(title(for: context.attributes))
            }
            .keylineTint(context.attributes.tintColor)
        }
    }

    private func title(for attributes: AlarmAttributes<AlarmKitTrialMetadata>) -> Text {
        if let metadata = attributes.metadata {
            return Text(verbatim: metadata.title)
        }
        return Text(attributes.presentation.alert.title)
    }
}

@available(iOS 26.0, *)
private struct AlarmKitTrialCountdown: View {
    let state: AlarmPresentationState

    var body: some View {
        Group {
            switch state.mode {
            case .countdown(let countdown):
                // AlarmKit supplies the current fire date, including after a resume.
                // Native timer text keeps ticking while the app is not running.
                let interval = countdown.startDate...max(countdown.startDate, countdown.fireDate)
                Text(
                    timerInterval: interval,
                    countsDown: true, showsHours: false)
            case .paused(let paused):
                let remaining = Duration.seconds(
                    max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration))
                Text(remaining, format: .time(pattern: .minuteSecond))
            case .alert:
                // The system renders the configured AlarmKit alert presentation.
                EmptyView()
            @unknown default:
                EmptyView()
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.65)
    }
}

private struct AlarmKitTrialAppIcon: View {
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
