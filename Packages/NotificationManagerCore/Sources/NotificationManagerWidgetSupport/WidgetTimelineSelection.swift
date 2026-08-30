import Foundation

public enum WidgetContentState: Sendable, Equatable {
    case events([WidgetReminderEvent])
    case noUpcoming
    case refreshRequired
}

public enum WidgetTextSizeTier: Sendable, Equatable {
    case standard
    case enlarged
    case accessibility
}

public enum WidgetMediumRowLimit {
    public static func maximum(for textSizeTier: WidgetTextSizeTier) -> Int {
        switch textSizeTier {
        case .standard:
            3
        case .enlarged:
            2
        case .accessibility:
            1
        }
    }
}

public enum WidgetTimelineSelection {
    public static func select(
        snapshot: WidgetSnapshot,
        at date: Date,
        limit: Int
    ) -> WidgetContentState {
        let upcoming = snapshot.events.filter { $0.fireDate > date }
        guard !upcoming.isEmpty else {
            return snapshot.isTruncated ? .refreshRequired : .noUpcoming
        }
        return .events(Array(upcoming.prefix(max(0, limit))))
    }
}

public struct WidgetTimelineMoment: Sendable, Equatable {
    public let date: Date
    public let content: WidgetContentState

    public init(date: Date, content: WidgetContentState) {
        self.date = date
        self.content = content
    }
}

public enum WidgetTimelineReloadInstruction: Sendable, Equatable {
    case never
    case after(Date)
}

public struct WidgetTimelinePlan: Sendable, Equatable {
    public let moments: [WidgetTimelineMoment]
    public let reload: WidgetTimelineReloadInstruction

    public init(moments: [WidgetTimelineMoment], reload: WidgetTimelineReloadInstruction) {
        self.moments = moments
        self.reload = reload
    }
}

public enum WidgetTimelinePlanner {
    public static func make(
        snapshot: WidgetSnapshot,
        at date: Date,
        limit: Int
    ) -> WidgetTimelinePlan {
        let futureDates = Set(snapshot.events.map(\.fireDate)).filter { $0 > date }.sorted()
        let moments =
            [
                WidgetTimelineMoment(
                    date: date,
                    content: WidgetTimelineSelection.select(
                        snapshot: snapshot, at: date, limit: limit)
                )
            ]
            + futureDates.map { momentDate in
                WidgetTimelineMoment(
                    date: momentDate,
                    content: WidgetTimelineSelection.select(
                        snapshot: snapshot, at: momentDate, limit: limit)
                )
            }
        let reload: WidgetTimelineReloadInstruction
        if snapshot.isTruncated, let lastEventDate = snapshot.events.last?.fireDate {
            reload = .after(lastEventDate)
        } else {
            reload = .never
        }
        return WidgetTimelinePlan(moments: moments, reload: reload)
    }
}
