import SwiftUI
import UIKit

struct AccessibilityIdentifierContainer: UIViewRepresentable {
    let identifier: String
    let value: String?

    init(identifier: String, value: String? = nil) {
        self.identifier = identifier
        self.value = value
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isAccessibilityElement = false
        view.accessibilityIdentifier = identifier
        view.accessibilityValue = value
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.accessibilityIdentifier = identifier
        uiView.accessibilityValue = value
    }
}

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
            table: identity.localizationTable.rawValue,
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
