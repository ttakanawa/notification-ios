import BackgroundTasks
import Foundation
import OSLog

@MainActor
final class ReminderLiveActivityBackgroundRefresh {
    nonisolated static let identifier = "org.tknw.punctual.live-activity-expiration"
    static let shared = ReminderLiveActivityBackgroundRefresh()

    private let submit: @MainActor (Date) throws -> Void
    private let cancel: @MainActor () -> Void
    private let logger = Logger(subsystem: "org.tknw.punctual", category: "LiveActivities")

    init(
        submit: @escaping @MainActor (Date) throws -> Void = { date in
            let request = BGAppRefreshTaskRequest(identifier: identifier)
            // This is the earliest execution time, not a guaranteed deadline.
            request.earliestBeginDate = date
            try BGTaskScheduler.shared.submit(request)
        },
        cancel: @escaping @MainActor () -> Void = {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        }
    ) {
        self.submit = submit
        self.cancel = cancel
    }

    func schedule(activities: [ReminderLiveActivityRecord]) {
        guard
            let endDate = activities.filter({ $0.state != .dismissed })
                .map(\.content.activityEndDate).filter({ $0.timeIntervalSince1970.isFinite }).min()
        else {
            cancel()
            return
        }
        do {
            // Submitting the same identifier replaces its previous request. Keep the
            // old request if submission fails, rather than cancelling it first.
            try submit(endDate)
        } catch {
            logger.error(
                "Unable to schedule Live Activity cleanup: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
