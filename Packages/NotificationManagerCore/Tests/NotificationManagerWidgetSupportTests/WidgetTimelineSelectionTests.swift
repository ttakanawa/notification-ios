import Foundation
import Testing

@testable import NotificationManagerWidgetSupport

@Suite("WidgetTimelineSelection")
struct WidgetTimelineSelectionTests {
    @Test func selectionDropsEventsAtBoundary() throws {
        let snapshot = try fixtureSnapshot(
            isTruncated: false,
            fireDates: [date("2026-09-01T10:00:00Z"), date("2026-09-01T11:00:00Z")]
        )

        let result = WidgetTimelineSelection.select(
            snapshot: snapshot,
            at: date("2026-09-01T10:00:00Z"),
            limit: 1
        )

        #expect(result == .events([snapshot.events[1]]))
    }

    @Test func selectionUsesAtMostThreeEventsForMediumContent() throws {
        let snapshot = try fixtureSnapshot(
            isTruncated: false,
            fireDates: [
                date("2026-09-01T10:00:00Z"), date("2026-09-01T11:00:00Z"),
                date("2026-09-01T12:00:00Z"), date("2026-09-01T13:00:00Z")
            ]
        )

        let result = WidgetTimelineSelection.select(
            snapshot: snapshot,
            at: date("2026-09-01T09:00:00Z"),
            limit: 3
        )

        #expect(result == .events(Array(snapshot.events.prefix(3))))
    }

    @Test func completeExhaustedSnapshotHasNoUpcomingContent() throws {
        let snapshot = try fixtureSnapshot(
            isTruncated: false,
            fireDates: [date("2026-09-01T10:00:00Z")]
        )

        #expect(
            WidgetTimelineSelection.select(
                snapshot: snapshot, at: date("2026-09-01T10:00:00Z"), limit: 1)
                == .noUpcoming
        )
    }

    @Test func truncatedExhaustedSnapshotRequestsRefresh() throws {
        let snapshot = try fixtureSnapshot(
            isTruncated: true,
            fireDates: [date("2026-09-01T10:00:00Z")]
        )

        #expect(
            WidgetTimelineSelection.select(
                snapshot: snapshot, at: date("2026-09-01T10:00:00Z"), limit: 1)
                == .refreshRequired
        )
    }

    @Test func truncatedTimelineAdvancesAndReloadsAfterItsLastEvent() throws {
        let now = date("2026-09-01T09:00:00Z")
        let snapshot = try fixtureSnapshot(
            isTruncated: true,
            fireDates: [date("2026-09-01T10:00:00Z"), date("2026-09-01T11:00:00Z")]
        )

        let plan = WidgetTimelinePlanner.make(snapshot: snapshot, at: now, limit: 1)

        #expect(
            plan.moments.map(\.date) == [
                now,
                date("2026-09-01T10:00:00Z"),
                date("2026-09-01T11:00:00Z")
            ])
        #expect(plan.moments.last?.content == .refreshRequired)
        #expect(plan.reload == .after(date("2026-09-01T11:00:00Z")))
    }

    @Test func mediumRowLimitAdaptsToTextSizeTier() {
        #expect(WidgetMediumRowLimit.maximum(for: .standard) == 3)
        #expect(WidgetMediumRowLimit.maximum(for: .enlarged) == 2)
        #expect(WidgetMediumRowLimit.maximum(for: .accessibility) == 1)
    }
}

func fixtureSnapshot(isTruncated: Bool, fireDates: [Date]) throws -> WidgetSnapshot {
    try WidgetSnapshot(
        generatedAt: date("2026-09-01T09:00:00Z"),
        isTruncated: isTruncated,
        events: fireDates.enumerated().map { index, fireDate in
            makeEvent(
                id: String(format: "aaaaaaaa-aaaa-aaaa-aaaa-%012d", index + 1),
                fireDate: ISO8601DateFormatter().string(from: fireDate)
            )
        }
    )
}
