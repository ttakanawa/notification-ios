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
        let content = content(for: event)
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
                    sound: .default
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
        await activity.update(content(for: event))
    }

    func end(_ id: String) async {
        guard let activity = activity(id) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    private func activity(_ id: String) -> Activity<ReminderActivityAttributes>? {
        Activity<ReminderActivityAttributes>.activities.first { $0.id == id }
    }

    private func content(
        for event: ReminderLiveActivityEvent
    ) -> ActivityContent<ReminderActivityAttributes.ContentState> {
        ActivityContent(
            state: ReminderActivityAttributes.ContentState(event: event),
            staleDate: event.activityEndDate,
            relevanceScore: 1
        )
    }
}
