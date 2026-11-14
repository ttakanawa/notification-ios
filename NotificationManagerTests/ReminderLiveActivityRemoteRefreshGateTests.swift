import Testing

@testable import NotificationManager

@Suite("Live Activity remote reconciliation ordering")
@MainActor
struct LiveActivityRemoteRefreshTests {
    @Test func aNewActivitySnapshotCannotBeOverwrittenByASuspendedOlderRefresh() async {
        let gate = ReminderLiveActivityRemoteRefreshGate()
        let (started, didStart) = AsyncStream<Void>.makeStream()
        let (release, resume) = AsyncStream<Void>.makeStream()
        var activities = ["existing"]
        var applied: [[String]] = []
        var calls = 0
        let refresh = Task { @MainActor in
            await gate.run {
                let snapshot = activities
                calls += 1
                if calls == 1 {
                    didStart.yield(())
                    var iterator = release.makeAsyncIterator()
                    _ = await iterator.next()
                }
                applied.append(snapshot)
            }
        }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        activities.append("new")
        await gate.run {
            // The active drain must own the queued refresh, so this closure never runs.
            Issue.record("Overlapping reconciliation was allowed")
        }
        resume.yield(())
        await refresh.value

        #expect(applied == [["existing"], ["existing", "new"]])
        #expect(applied.last == activities)
        didStart.finish()
        resume.finish()
    }
}
