#if canImport(AlarmKit) && os(iOS)
    import AlarmKit

    @available(iOS 26.0, *)
    @available(macCatalyst, unavailable)
    public struct AlarmKitTrialMetadata: AlarmMetadata, Sendable {
        public let title: String

        public init(title: String) {
            self.title = title
        }
    }
#endif
