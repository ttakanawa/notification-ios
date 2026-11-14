import SwiftUI

struct AppSymbolTile: View {
    let systemName: String
    let color: Color

    @ScaledMetric(relativeTo: .body) private var size = 28

    var body: some View {
        let tileSize = min(size, 36)
        Image(systemName: systemName)
            .font(.system(size: tileSize * 0.57, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: tileSize, height: tileSize)
            .background(color, in: RoundedRectangle(cornerRadius: tileSize * 0.25))
            .accessibilityHidden(true)
    }
}

struct AppRowLabel: View {
    let title: LocalizedStringResource
    let systemImage: String
    let color: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            AppSymbolTile(systemName: systemImage, color: color)
        }
    }
}
