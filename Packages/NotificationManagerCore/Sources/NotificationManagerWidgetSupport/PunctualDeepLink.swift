import Foundation

public enum PunctualDeepLink: Sendable, Equatable {
    case list
    case reminder(UUID)
}

public struct PunctualDeepLinkCodec: Sendable {
    public init() {}

    public func url(for link: PunctualDeepLink) -> URL {
        let rawURL =
            switch link {
            case .list:
                "punctual://reminders"
            case .reminder(let reminderID):
                "punctual://reminders/\(reminderID.uuidString.lowercased())"
            }
        guard let url = URL(string: rawURL) else {
            preconditionFailure("The fixed Punctual Deep Link format must produce a valid URL.")
        }
        return url
    }

    public func parse(_ url: URL) -> PunctualDeepLink? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme == "punctual",
            components.host == "reminders",
            components.user == nil,
            components.password == nil,
            components.port == nil,
            components.query == nil,
            components.fragment == nil
        else {
            return nil
        }

        let deepLink: PunctualDeepLink
        switch components.percentEncodedPath {
        case "":
            deepLink = .list
        case let path where path.utf8.count == 37 && path.first == "/":
            let rawIdentifier = String(path.dropFirst())
            guard let identifier = canonicalUUID(rawIdentifier) else { return nil }
            deepLink = .reminder(identifier)
        default:
            return nil
        }

        guard url.absoluteString == self.url(for: deepLink).absoluteString else { return nil }
        return deepLink
    }

    private func canonicalUUID(_ rawValue: String) -> UUID? {
        guard rawValue.utf8.count == 36,
            rawValue == rawValue.lowercased(),
            let uuid = UUID(uuidString: rawValue),
            uuid.uuidString.lowercased() == rawValue
        else {
            return nil
        }
        return uuid
    }
}
