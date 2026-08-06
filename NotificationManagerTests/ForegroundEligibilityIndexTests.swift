import Foundation
import Testing
@testable import NotificationManager

struct ForegroundEligibilityIndexTests {
    @Test func unpublishedIndexSuppressesEveryReminder() {
        let store = ForegroundEligibilityIndexStore()
        let reminderID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!

        let index = store.snapshot()

        #expect(index.generation == 0)
        #expect(index.isStale)
        #expect(!index.eligibleReminderIDs.contains(reminderID))
        #expect(!store.isEligible(reminderID))
    }

    @Test func modelObservationMakesPriorImmutableGenerationStaleWithoutChangingMembership() {
        let store = ForegroundEligibilityIndexStore()
        let reminderID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        store.publish(eligibleReminderIDs: [reminderID])
        let published = store.snapshot()

        store.markStale()
        let stale = store.snapshot()

        #expect(published.generation == 1)
        #expect(!published.isStale)
        #expect(published.eligibleReminderIDs == [reminderID])
        #expect(stale.generation == published.generation)
        #expect(stale.isStale)
        #expect(stale.eligibleReminderIDs == published.eligibleReminderIDs)
        #expect(!store.isEligible(reminderID))
    }

    @Test func completePublicationAtomicallyReplacesMembershipAndAdvancesGeneration() {
        let store = ForegroundEligibilityIndexStore()
        let oldID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let newID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        store.publish(eligibleReminderIDs: [oldID])
        store.markStale()

        store.publish(eligibleReminderIDs: [newID])
        let index = store.snapshot()

        #expect(index.generation == 2)
        #expect(!index.isStale)
        #expect(index.eligibleReminderIDs == [newID])
        #expect(!store.isEligible(oldID))
        #expect(store.isEligible(newID))
    }
}
