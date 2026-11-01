import SwiftUI

struct ICloudSyncStatusButton: View {
    let model: ICloudSyncStatusModel
    let action: () -> Void

    var body: some View {
        let presentation = ICloudSyncStatusPresentation(
            accountAvailability: model.accountAvailability,
            syncActivity: model.syncActivity
        )

        Button(action: action) {
            Label(
                LocalizedStringResource("settings.section.icloud", table: "Settings"),
                systemImage: presentation.systemImage
            )
            .labelStyle(.iconOnly)
        }
        .tint(presentation.tint)
        .accessibilityValue(Text(presentation.localizedResource))
        .accessibilityIdentifier("reminder-list.icloud-status")
    }
}

enum ICloudSyncStatusPresentation: Equatable {
    case account(ICloudAccountAvailability)
    case activity(ICloudSyncActivity)

    init(accountAvailability: ICloudAccountAvailability, syncActivity: ICloudSyncActivity) {
        self =
            accountAvailability == .available
            ? .activity(syncActivity) : .account(accountAvailability)
    }

    var systemImage: String {
        switch self {
        case .account(.checking), .account(.available), .activity(.notObserved):
            "icloud"
        case .account(.noAccount), .account(.restricted):
            "icloud.slash"
        case .account(.temporarilyUnavailable), .account(.couldNotDetermine), .activity(.failed):
            "exclamationmark.icloud"
        case .activity(.inProgress):
            "arrow.triangle.2.circlepath.icloud"
        case .activity(.succeeded):
            "checkmark.icloud"
        }
    }

    var tint: Color {
        switch self {
        case .account(.checking), .account(.available), .account(.noAccount), .account(.restricted),
            .activity(.notObserved):
            .secondary
        case .account(.temporarilyUnavailable), .account(.couldNotDetermine), .activity(.failed):
            .orange
        case .activity(.inProgress):
            .blue
        case .activity(.succeeded):
            .green
        }
    }

    var localizedResource: LocalizedStringResource {
        switch self {
        case .account(let availability):
            availability.localizedResource
        case .activity(let activity):
            activity.localizedResource
        }
    }
}
