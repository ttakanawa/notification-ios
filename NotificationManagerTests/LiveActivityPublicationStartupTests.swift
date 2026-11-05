import Foundation
import NotificationManagerDomain
import NotificationManagerWidgetSupport
import Testing

@testable import NotificationManager

@Suite("LiveActivityPublicationStartup")
@MainActor
struct LiveActivityPublicationStartupTests {
    @Test(.timeLimit(.minutes(1)))
    func unknownBootstrapBusyAndFailureStatesDoNotEndExistingActivities() async {
        let stateStore = DeviceSchedulingStateStore()
        let recorder = StartupPublicationRecorder()
        let environment = AppEnvironment(
            widgetSnapshotPublication: { _, _ in
                await recorder.recordWidgetPublication()
            },
            liveActivityPublication: { events, _ in
                recorder.recordLiveActivityPublication(events)
            }
        )
        // Production owns this environment for the process lifetime. Keep the test
        // owner alive until the weakly captured publication tasks have completed.
        defer { withExtendedLifetime(environment) {} }
        let snapshot = ongoingReminderSnapshot()

        await publishAndDrain(
            environment, snapshot: snapshot, state: await stateStore.snapshot(),
            recorder: recorder, widgetCount: 1)
        await stateStore.setReconcileInProgressOrQueued(true, revision: 1)
        await publishAndDrain(
            environment, snapshot: snapshot, state: await stateStore.snapshot(),
            recorder: recorder, widgetCount: 2)
        await stateStore.publishFailure(.inventory)
        await stateStore.setReconcileInProgressOrQueued(false, revision: 2)
        // A failed scheduling snapshot retains the previous Widget publication.
        await publishAndDrain(
            environment, snapshot: snapshot, state: await stateStore.snapshot(),
            recorder: recorder, widgetCount: 2)

        #expect(recorder.liveActivityPublications.isEmpty)
        #expect(environment.listModel.items.count == 1)
        #expect(recorder.widgetPublicationCount == 2)

        await publishSettings(stateStore, enabled: true)
        environment.publish(snapshot, deviceState: await stateStore.snapshot())
        await recorder.waitForLiveActivityCount(1)
        #expect(
            recorder.liveActivityPublications.first?.map(\.reminderID)
                == snapshot.reminders.map(\.id))

        await publishSettings(stateStore, enabled: false)
        environment.publish(snapshot, deviceState: await stateStore.snapshot())
        await recorder.waitForLiveActivityCount(2)
        #expect(recorder.liveActivityPublications.last?.isEmpty == true)
    }

    private func publishAndDrain(
        _ environment: AppEnvironment,
        snapshot: CompleteReminderSnapshot,
        state: DeviceSchedulingStateSnapshot,
        recorder: StartupPublicationRecorder,
        widgetCount: Int
    ) async {
        environment.publish(snapshot, deviceState: state)
        await recorder.waitForWidgetCount(widgetCount)
        await Task { @MainActor in }.value
    }

    private func publishSettings(_ store: DeviceSchedulingStateStore, enabled: Bool) async {
        await store.publish(
            deviceNotificationsEnabled: enabled,
            authorization: .init(state: .allowed, diagnostic: nil),
            outcomes: [:], scheduledThrough: [:], materializedKinds: [:],
            nextTriggerDates: [:], pendingOrAddedIdentifiers: []
        )
    }

    private func ongoingReminderSnapshot() -> CompleteReminderSnapshot {
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let schedule = ScheduleDefinition(
            source: .init(
                year: components.year ?? 2026, month: components.month ?? 1,
                day: components.day ?? 1, hour: components.hour ?? 0,
                minute: components.minute ?? 0,
                timeZoneIdentifier: "Africa/Abidjan"),
            rule: .none, end: .never, early: nil,
            liveActivityWindow: .init(beforeSeconds: 300, afterSeconds: 600))
        return CompleteReminderSnapshot(
            reminders: [
                ReminderSnapshot(
                    id: UUID(), title: "Existing Live Activity", notes: nil, urlString: nil,
                    enabled: true,
                    schedule: .valid(schedule, sourceVersion: 4, originalData: Data()), tagIDs: [],
                    createdAt: now, updatedAt: now)
            ],
            tags: [])
    }
}

@MainActor
private final class StartupPublicationRecorder {
    private(set) var liveActivityPublications: [[ReminderLiveActivityEvent]] = []
    private(set) var widgetPublicationCount = 0

    func recordLiveActivityPublication(_ events: [ReminderLiveActivityEvent]) {
        liveActivityPublications.append(events)
    }

    func recordWidgetPublication() {
        widgetPublicationCount += 1
    }

    func waitForWidgetCount(_ count: Int) async {
        await waitForCount(count, publication: "Widget") { self.widgetPublicationCount }
    }

    func waitForLiveActivityCount(_ count: Int) async {
        await waitForCount(count, publication: "Live Activity") {
            self.liveActivityPublications.count
        }
    }

    private func waitForCount(
        _ count: Int,
        publication: String,
        currentCount: () -> Int
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while currentCount() < count {
            guard !Task.isCancelled else { return }
            guard clock.now < deadline else {
                Issue.record(
                    "Timed out waiting for \(count) \(publication) publications; received \(currentCount())"
                )
                return
            }
            do {
                try await clock.sleep(for: .milliseconds(10))
            } catch {
                return
            }
        }
    }
}
