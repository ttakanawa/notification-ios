#if os(iOS) && canImport(ActivityKit)
    @preconcurrency import ActivityKit
    import AppIntents
    import Foundation
    import OSLog

    public struct PunctualWidgetIntentsPackage: AppIntentsPackage {}

    public struct DismissReminderLiveActivityIntent: LiveActivityIntent {
        public static var title: LocalizedStringResource {
            LocalizedStringResource(
                "widget.live-activity.close", defaultValue: "Close this Live Activity",
                table: "Widget")
        }
        public static var isDiscoverable: Bool { false }
        public static var openAppWhenRun: Bool { false }
        @available(iOS 26.0, *)
        public static var supportedModes: IntentModes { .background }

        @Parameter(title: "Occurrence") public var eventID: String
        @Parameter(title: "Notification time") public var notificationDate: Date

        public init() {}

        public init(eventID: String, notificationDate: Date) {
            self.eventID = eventID
            self.notificationDate = notificationDate
        }

        public func perform() async throws -> some IntentResult {
            LiveActivityOccurrenceDismissalStore.markDismissed(
                eventID: eventID, notificationDate: notificationDate)
            let outbox = await LiveActivityEndRuntime.shared.outbox()
            do {
                try await outbox?.dismiss(eventID: eventID, notificationDate: notificationDate)
            } catch {
                Logger(subsystem: "org.tknw.punctual", category: "LiveActivities")
                    .error(
                        "Unable to persist remote cancellation; local dismissal remains recorded")
            }
            for activity in Activity<ReminderActivityAttributes>.activities
            where activity.attributes.eventID == eventID {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            // This action closes the display before waiting for the network and never
            // publishes restored schedule changes during a background intent launch.
            await outbox?.flush(cancellationsOnly: true)
            return .result()
        }
    }
#endif
