import SwiftUI
import UIKit

struct AccessibilityErrorAnnouncementModifier: ViewModifier {
    @Environment(\.locale) private var locale
    @State private var previousIdentities: [AccessibilityErrorIdentity] = []

    let identities: [AccessibilityErrorIdentity]
    private let resolver = AccessibilityErrorAnnouncementResolver()

    func body(content: Content) -> some View {
        content
            .onAppear {
                announceNewIdentity(in: identities)
            }
            .onChange(of: identities) { _, current in
                announceNewIdentity(in: current)
            }
    }

    private func announceNewIdentity(in current: [AccessibilityErrorIdentity]) {
        defer { previousIdentities = current }
        guard let identity = resolver.newIdentity(
            previous: previousIdentities,
            current: current
        ) else {
            return
        }
        let message = String(
            localized: String.LocalizationValue(identity.rawValue),
            table: "Localizable",
            bundle: .main,
            locale: locale
        )
        let announcement = NSMutableAttributedString(string: message)
        announcement.addAttribute(
            .accessibilitySpeechAnnouncementPriority,
            value: UIAccessibilityPriority.high,
            range: NSRange(location: 0, length: announcement.length)
        )
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }
}

extension View {
    func announcesAccessibilityErrors(
        _ identities: [AccessibilityErrorIdentity]
    ) -> some View {
        modifier(AccessibilityErrorAnnouncementModifier(identities: identities))
    }
}
