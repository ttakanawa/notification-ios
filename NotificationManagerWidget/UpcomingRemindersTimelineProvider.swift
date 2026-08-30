import Foundation
import NotificationManagerWidgetSupport
import WidgetKit

struct UpcomingReminderEntry: TimelineEntry {
    let date: Date
    let state: UpcomingReminderWidgetState
}

enum UpcomingReminderWidgetState: Sendable, Equatable {
    case events([WidgetReminderEvent])
    case noUpcoming
    case refreshRequired
    case unavailable
}

struct UpcomingRemindersTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UpcomingReminderEntry {
        .preview
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (UpcomingReminderEntry) -> Void
    ) {
        guard !context.isPreview else {
            completion(.preview)
            return
        }

        let date = Date()
        completion(
            makeTimeline(at: date, for: context.family).entries.first
                ?? UpcomingReminderEntry(date: date, state: .unavailable)
        )
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<UpcomingReminderEntry>) -> Void
    ) {
        let date = Date()
        completion(makeTimeline(at: date, for: context.family))
    }

    private func makeTimeline(
        at date: Date,
        for family: WidgetFamily
    ) -> Timeline<UpcomingReminderEntry> {
        guard let store = WidgetSnapshotFileStore.live() else {
            return singleEntryTimeline(date: date, state: .unavailable)
        }

        switch store.read() {
        case .missing:
            return singleEntryTimeline(date: date, state: .noUpcoming)
        case .invalid:
            return singleEntryTimeline(date: date, state: .unavailable)
        case .available(let snapshot):
            let plan = WidgetTimelinePlanner.make(
                snapshot: snapshot,
                at: date,
                limit: eventLimit(for: family)
            )
            let entries = plan.moments.map { moment in
                UpcomingReminderEntry(
                    date: moment.date,
                    state: widgetState(for: moment.content)
                )
            }
            return Timeline(entries: entries, policy: reloadPolicy(for: plan.reload))
        }
    }

    private func eventLimit(for family: WidgetFamily) -> Int {
        family == .systemMedium ? 3 : 1
    }

    private func singleEntryTimeline(
        date: Date,
        state: UpcomingReminderWidgetState
    ) -> Timeline<UpcomingReminderEntry> {
        Timeline(entries: [.init(date: date, state: state)], policy: .never)
    }

    private func widgetState(for content: WidgetContentState) -> UpcomingReminderWidgetState {
        switch content {
        case .events(let events):
            .events(events)
        case .noUpcoming:
            .noUpcoming
        case .refreshRequired:
            .refreshRequired
        }
    }

    private func reloadPolicy(
        for instruction: WidgetTimelineReloadInstruction
    ) -> TimelineReloadPolicy {
        switch instruction {
        case .never:
            .never
        case .after(let date):
            .after(date)
        }
    }
}

extension UpcomingReminderEntry {
    static let preview: UpcomingReminderEntry = {
        let referenceDate = Date(timeIntervalSinceReferenceDate: 850_000_000)
        return UpcomingReminderEntry(
            date: referenceDate,
            state: .events([
                WidgetReminderEvent(
                    reminderID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    title: "Sample reminder",
                    fireDate: referenceDate.addingTimeInterval(3_600)
                ),
                WidgetReminderEvent(
                    reminderID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    title: "Another reminder",
                    fireDate: referenceDate.addingTimeInterval(7_200)
                ),
                WidgetReminderEvent(
                    reminderID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    title: "Final reminder",
                    fireDate: referenceDate.addingTimeInterval(10_800)
                )
            ])
        )
    }()
}
