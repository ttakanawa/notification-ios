import SwiftUI

struct LocalizationSourceCoverageMissingFixture: View {
    var body: some View {
        Button("settings.same-line-missing") {}.accessibilityIdentifier("settings.fixture-control")
    }
}
