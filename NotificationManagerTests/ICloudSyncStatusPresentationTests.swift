import Foundation
import Testing
import UIKit

@testable import NotificationManager

struct ICloudSyncStatusPresentationTests {
    @Test(
        arguments: [
            ICloudAccountAvailability.checking, .noAccount, .restricted,
            .temporarilyUnavailable, .couldNotDetermine
        ],
        [ICloudSyncActivity.notObserved, .inProgress, .succeeded, .failed]
    )
    func accountAvailabilityTakesPrecedenceOverObservedActivity(
        availability: ICloudAccountAvailability,
        activity: ICloudSyncActivity
    ) {
        let presentation = ICloudSyncStatusPresentation(
            accountAvailability: availability,
            syncActivity: activity
        )

        #expect(presentation == .account(availability))
        #expect(presentation.localizedResource.key == availability.localizedResource.key)
        #expect(presentation.systemImage != "checkmark.icloud")
    }

    @Test func accountAccessAloneDoesNotShowSuccessfulSync() {
        let presentation = ICloudSyncStatusPresentation(
            accountAvailability: .available,
            syncActivity: .notObserved
        )

        #expect(presentation == .activity(.notObserved))
        #expect(presentation.systemImage == "icloud")
        #expect(presentation.localizedResource.key == "settings.icloud.activity.not-observed")
    }

    @MainActor
    @Test func observedEventsUpdateTheIndicatorWithoutReplacingTheModel() {
        let model = ICloudSyncStatusModel(accountAvailability: .available)
        let identifier = UUID()

        model.receive(
            ICloudSyncEvent(identifier: identifier, kind: .export, endDate: nil, succeeded: false)
        )
        #expect(presentation(for: model) == .activity(.inProgress))

        model.receive(
            ICloudSyncEvent(identifier: identifier, kind: .export, endDate: Date(), succeeded: true)
        )
        let succeeded = presentation(for: model)
        #expect(succeeded == .activity(.succeeded))
        #expect(succeeded.localizedResource.key == "settings.icloud.activity.succeeded")
    }

    @MainActor
    @Test func indicatorSymbolsExistOnTheDevice() {
        let presentations: [ICloudSyncStatusPresentation] = [
            .account(.checking), .account(.noAccount), .account(.restricted),
            .account(.temporarilyUnavailable), .account(.couldNotDetermine),
            .activity(.notObserved), .activity(.inProgress), .activity(.succeeded),
            .activity(.failed)
        ]

        for presentation in presentations {
            #expect(UIImage(systemName: presentation.systemImage) != nil)
        }
    }

    @MainActor
    private func presentation(for model: ICloudSyncStatusModel) -> ICloudSyncStatusPresentation {
        ICloudSyncStatusPresentation(
            accountAvailability: model.accountAvailability,
            syncActivity: model.syncActivity
        )
    }
}
