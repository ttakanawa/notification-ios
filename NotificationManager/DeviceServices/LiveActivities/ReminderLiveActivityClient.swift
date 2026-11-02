// ActivityKit's Activity reference lacks Sendable annotations for its async APIs.
// Keep that compatibility bridge inside this main-actor adapter.
@preconcurrency import ActivityKit
import Foundation
import NotificationManagerWidgetSupport

enum ReminderLiveActivityState: Sendable, Equatable {
    case pending
    case active
    case stale
    case ended
    case dismissed
}

struct ReminderLiveActivityRecord: Sendable, Equatable {
    let id: String
    let eventID: String
    let state: ReminderLiveActivityState
    let content: ReminderActivityAttributes.ContentState
}

@MainActor
protocol ReminderLiveActivityClient {
    var activitiesEnabled: Bool { get }
    var supportsScheduling: Bool { get }
    func currentActivities() -> [ReminderLiveActivityRecord]
    func request(_ event: ReminderLiveActivityEvent, scheduled: Bool) throws -> String
    func update(_ id: String, event: ReminderLiveActivityEvent) async
    func end(_ id: String) async
}

@MainActor
struct SystemReminderLiveActivityClient: ReminderLiveActivityClient {
    nonisolated static let scheduledStartSoundName = "LiveActivitySilence.wav"

    var activitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    var supportsScheduling: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    func currentActivities() -> [ReminderLiveActivityRecord] {
        Activity<ReminderActivityAttributes>.activities.map { activity in
            let state: ReminderLiveActivityState
            if #available(iOS 26.0, *), activity.activityState == .pending {
                state = .pending
            } else {
                switch activity.activityState {
                case .active: state = .active
                case .stale: state = .stale
                case .ended: state = .ended
                case .dismissed: state = .dismissed
                default: state = .ended
                }
            }
            return ReminderLiveActivityRecord(
                id: activity.id,
                eventID: activity.attributes.eventID,
                state: state,
                content: activity.content.state
            )
        }
    }

    func request(_ event: ReminderLiveActivityEvent, scheduled: Bool) throws -> String {
        let attributes = ReminderActivityAttributes(event: event)
        let content = Self.content(for: event, at: Date())
        let activity: Activity<ReminderActivityAttributes>
        if #available(iOS 26.0, *), scheduled {
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil,
                style: .standard,
                alertConfiguration: AlertConfiguration(
                    title: LocalizedStringResource("common.app-name", table: "Common"),
                    body: LocalizedStringResource(
                        "reminder.live-activity.started",
                        defaultValue: "\(event.title)",
                        table: "Reminder"
                    ),
                    // Scheduling requires an alert configuration. Starting the display
                    // window must not play the main notification sound ahead of time.
                    sound: .named(Self.scheduledStartSoundName)
                ),
                start: event.startDate
            )
        } else {
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
        }
        return activity.id
    }

    func update(_ id: String, event: ReminderLiveActivityEvent) async {
        guard let activity = activity(id) else { return }
        await activity.update(Self.content(for: event, at: Date()))
    }

    func end(_ id: String) async {
        guard let activity = activity(id) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    private func activity(_ id: String) -> Activity<ReminderActivityAttributes>? {
        Activity<ReminderActivityAttributes>.activities.first { $0.id == id }
    }

    nonisolated static func content(
        for event: ReminderLiveActivityEvent, at date: Date
    ) -> ActivityContent<ReminderActivityAttributes.ContentState> {
        let notificationHasOccurred = date >= event.notificationDate
        return ActivityContent(
            state: ReminderActivityAttributes.ContentState(
                event: event, notificationHasOccurred: notificationHasOccurred),
            // Native staleness is the phase boundary: it switches the widget from
            // "before" to "after" without requiring the app to execute at this time.
            // If the notification already fired, start with fresh content and an explicit
            // after-phase rather than creating an initially stale, potentially hidden card.
            staleDate: notificationHasOccurred ? event.activityEndDate : event.notificationDate,
            relevanceScore: 1
        )
    }
}
