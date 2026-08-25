import NotificationManagerApplication

enum AssistedRepeatInterpreterFactory {
    static func make() -> any AssistedRepeatInterpreting {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                return SystemAssistedRepeatInterpreter()
            }
        #endif
        return UnavailableAssistedRepeatInterpreter()
    }
}
