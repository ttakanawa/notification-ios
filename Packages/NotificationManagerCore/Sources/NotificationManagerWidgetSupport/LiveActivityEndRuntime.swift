import Foundation

public enum LiveActivityOccurrenceDismissalStore {
    public static let knownActivitiesKey = "reminder-live-activities.known"
    public static let suppressedActivitiesKey = "reminder-live-activities.suppressed"
    public static let userDismissalsKey = "reminder-live-activities.user-dismissed"

    public static var preferences: UserDefaults {
        let shared =
            UserDefaults(suiteName: WidgetSnapshotConstants.appGroupIdentifier) ?? .standard
        let migrationKey = "reminder-live-activities.shared-state-migrated"
        if !shared.bool(forKey: migrationKey) {
            for key in [knownActivitiesKey, suppressedActivitiesKey]
            where shared.object(forKey: key) == nil {
                if let value = UserDefaults.standard.dictionary(forKey: key) {
                    shared.set(value, forKey: key)
                }
            }
            shared.set(true, forKey: migrationKey)
        }
        return shared
    }

    public static func markDismissed(eventID: String, notificationDate: Date) {
        let defaults = preferences
        var suppressed = defaults.dictionary(forKey: userDismissalsKey) as? [String: Double] ?? [:]
        suppressed = suppressed.filter { $0.value > Date().timeIntervalSince1970 }
        let expiry = notificationDate.addingTimeInterval(8 * 60 * 60).timeIntervalSince1970
        suppressed[eventID] = max(suppressed[eventID] ?? -.infinity, expiry)
        defaults.set(suppressed, forKey: userDismissalsKey)
    }
}

#if os(iOS)
    public actor LiveActivityEndRuntime {
        public static let shared = LiveActivityEndRuntime()
        private var cachedOutbox: LiveActivityEndOutbox?

        public func outbox() -> LiveActivityEndOutbox? {
            if let cachedOutbox { return cachedOutbox }
            let directory =
                FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: WidgetSnapshotConstants
                        .appGroupIdentifier
                )
                ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first
            guard let directory else { return nil }
            let configuration = Self.configuration()
            let root = directory.appending(path: "LiveActivityEnd", directoryHint: .isDirectory)
                .appending(
                    path: configuration?.storageNamespace ?? "unconfigured",
                    directoryHint: .isDirectory)
            var sender: (any LiveActivityEndJobSending)?
            if let configuration {
                sender = LiveActivityEndHTTPClient(
                    configuration: configuration, attester: SystemLiveActivityAppAttester(),
                    credentials: FileLiveActivityEndCredentialStore(
                        url: root.appending(path: "credentials.json")))
            }
            // A protected/unavailable store may become readable after unlock. Do
            // not cache failure or erase its persisted ownership/job information.
            cachedOutbox = try? LiveActivityEndOutbox(
                url: root.appending(path: "outbox.json"), sender: sender)
            return cachedOutbox
        }

        private static func configuration() -> LiveActivityEndAPIConfiguration? {
            guard
                let value = Bundle.main.object(forInfoDictionaryKey: "PunctualEndAPIBaseURL")
                    as? String,
                !value.isEmpty, !value.contains("$("), let url = URL(string: value),
                let environmentValue = Bundle.main.object(
                    forInfoDictionaryKey: "PunctualEndAPIEnvironment") as? String,
                let environment = LiveActivityEndAPIEnvironment(rawValue: environmentValue)
            else { return nil }
            let attestationValue =
                Bundle.main.object(forInfoDictionaryKey: "PunctualAppAttestEnvironment") as? String
            guard let attestationValue,
                let attestationEnvironment = LiveActivityEndAPIEnvironment(
                    rawValue: attestationValue)
            else { return nil }
            return try? LiveActivityEndAPIConfiguration(
                origin: url, environment: environment,
                attestationEnvironment: attestationEnvironment)
        }
    }
#endif
