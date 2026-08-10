import SwiftUI

struct LocalizationSourceCoverageValidFixture: View {
    var body: some View {
        Button("common.retry") {}
            .accessibilityIdentifier("settings.fixture-control")
            .background {
                AccessibilityIdentifierContainer(identifier: "settings.fixture-container")
            }
    }
}
