import CloudKit
import Foundation
import Testing

@testable import NotificationManager

@Suite struct ICloudSyncStatusModelTests {
    @MainActor
    @Test func refreshingAccountAvailabilityPublishesTheProviderResult() async {
        let model = ICloudSyncStatusModel(
            notificationCenter: NotificationCenter(),
            accountStatus: { .available }
        )

        await model.refreshAccountAvailability()

        #expect(model.accountAvailability == .available)
    }

    @MainActor
    @Test func accountLookupFailurePublishesCouldNotDetermine() async {
        let model = ICloudSyncStatusModel(
            notificationCenter: NotificationCenter(),
            accountStatus: { throw ICloudStatusTestError.lookupFailed }
        )

        await model.refreshAccountAvailability()

        #expect(model.accountAvailability == .couldNotDetermine)
    }

    @Test func cloudKitAccountStatusesMapWithoutClaimingSyncCompletion() {
        #expect(ICloudAccountAvailability(cloudKitStatus: .available) == .available)
        #expect(ICloudAccountAvailability(cloudKitStatus: .noAccount) == .noAccount)
        #expect(ICloudAccountAvailability(cloudKitStatus: .restricted) == .restricted)
        #expect(
            ICloudAccountAvailability(cloudKitStatus: .temporarilyUnavailable)
                == .temporarilyUnavailable
        )
        #expect(
            ICloudAccountAvailability(cloudKitStatus: .couldNotDetermine)
                == .couldNotDetermine
        )
    }

    @MainActor
    @Test func startingAnEventPublishesInProgressAndSuccessfulCompletionPublishesSuccess() {
        let identifier = UUID()
        let model = makeModel()

        model.receive(
            ICloudSyncEvent(
                identifier: identifier,
                kind: .export,
                endDate: nil,
                succeeded: false
            ))

        #expect(model.syncActivity == .inProgress)

        model.receive(
            ICloudSyncEvent(
                identifier: identifier,
                kind: .export,
                endDate: Date(timeIntervalSince1970: 200),
                succeeded: true
            ))

        #expect(model.syncActivity == .succeeded)
    }

    @MainActor
    @Test func overlappingEventsRemainInProgressUntilEveryEventEnds() {
        let firstIdentifier = UUID()
        let secondIdentifier = UUID()
        let model = makeModel()

        model.receive(
            ICloudSyncEvent(
                identifier: firstIdentifier,
                kind: .import,
                endDate: nil,
                succeeded: false
            ))
        model.receive(
            ICloudSyncEvent(
                identifier: secondIdentifier,
                kind: .export,
                endDate: nil,
                succeeded: false
            ))
        model.receive(
            ICloudSyncEvent(
                identifier: firstIdentifier,
                kind: .import,
                endDate: Date(timeIntervalSince1970: 200),
                succeeded: true
            ))

        #expect(model.syncActivity == .inProgress)

        model.receive(
            ICloudSyncEvent(
                identifier: secondIdentifier,
                kind: .export,
                endDate: Date(timeIntervalSince1970: 300),
                succeeded: false
            ))

        #expect(model.syncActivity == .failed)
    }

    @MainActor
    @Test func olderCompletionCannotReplaceTheLatestObservedOutcome() {
        let model = makeModel()

        model.receive(
            ICloudSyncEvent(
                identifier: UUID(),
                kind: .export,
                endDate: Date(timeIntervalSince1970: 300),
                succeeded: true
            ))
        model.receive(
            ICloudSyncEvent(
                identifier: UUID(),
                kind: .import,
                endDate: Date(timeIntervalSince1970: 200),
                succeeded: false
            ))

        #expect(model.syncActivity == .succeeded)
    }

    @MainActor
    private func makeModel() -> ICloudSyncStatusModel {
        ICloudSyncStatusModel(
            notificationCenter: NotificationCenter(),
            accountStatus: { .available }
        )
    }
}

private enum ICloudStatusTestError: Error {
    case lookupFailed
}
