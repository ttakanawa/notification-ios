import Testing

@testable import NotificationManager

@Suite("App icon selection")
@MainActor
struct AppIconSelectionModelTests {
    // Break caught: registry must map nil and each supported alternate name exactly.
    @Test func registryMapsPrimaryAndAlternates() {
        #expect(AppIconOption.matching(alternateIconName: nil) == .primary)
        #expect(AppIconOption.matching(alternateIconName: "AppIcon-Ocean") == .ocean)
        #expect(AppIconOption.matching(alternateIconName: "AppIcon-Sunset") == .sunset)
        #expect(AppIconOption.matching(alternateIconName: "Unknown") == nil)
    }

    // Break caught: initial load must map every known system selection and support state.
    @Test(arguments: [
        (nil, AppIconOption.primary),
        ("AppIcon-Ocean", AppIconOption.ocean),
        ("AppIcon-Sunset", AppIconOption.sunset)
    ])
    func initialLoadMapsKnownSystemSelections(alternateName: String?, expected: AppIconOption) {
        let service = RecordingAppIconService(
            supportsAlternateIcons: true, alternateIconName: alternateName)
        let model = AppIconSelectionModel(service: service)

        model.load()

        #expect(model.availability == .available)
        #expect(model.selectedOption == expected)
    }

    // Break caught: loading must preserve the current known system selection and support state.
    @Test func loadUsesSystemSelectionAndSupportState() {
        let service = RecordingAppIconService(
            supportsAlternateIcons: true, alternateIconName: "AppIcon-Ocean")
        let model = AppIconSelectionModel(service: service)

        model.load()

        #expect(model.availability == .available)
        #expect(model.selectedOption == .ocean)
        #expect(!model.isChanging)
        #expect(model.actionError == nil)
    }

    // Break caught: unsupported devices must retain known selection and reject changes.
    @Test func unsupportedDeviceKeepsKnownSelectionButDisablesChanges() async {
        let service = RecordingAppIconService(supportsAlternateIcons: false, alternateIconName: nil)
        let model = AppIconSelectionModel(service: service)

        model.load()
        await model.select(.ocean)

        #expect(model.availability == .unsupported)
        #expect(model.selectedOption == .primary)
        #expect(service.requests.isEmpty)
    }

    // Break caught: unregistered system names must surface configuration failure.
    @Test func unknownSystemNameProducesConfigurationError() {
        let service = RecordingAppIconService(
            supportsAlternateIcons: true, alternateIconName: "Unregistered")
        let model = AppIconSelectionModel(service: service)

        model.load()

        #expect(model.availability == .configurationError)
        #expect(model.selectedOption == nil)
    }

    // Break caught: selecting the already active option must not call the system service.
    @Test func selectingCurrentOptionIsANoOp() async {
        let service = RecordingAppIconService(supportsAlternateIcons: true, alternateIconName: nil)
        let model = AppIconSelectionModel(service: service)
        model.load()

        await model.select(.primary)

        #expect(service.requests.isEmpty)
    }

    // Break caught: successful changes must re-read the system selection and clear transient state.
    @Test func successfulChangeReReadsSystemSelection() async {
        let service = RecordingAppIconService(supportsAlternateIcons: true, alternateIconName: nil)
        let model = AppIconSelectionModel(service: service)
        model.load()

        await model.select(.sunset)

        #expect(service.requests == ["AppIcon-Sunset"])
        #expect(model.selectedOption == .sunset)
        #expect(model.actionError == nil)
        #expect(!model.isChanging)
    }

    // Break caught: failed changes must preserve selection and expose a stable error identity.
    @Test func failedChangePreservesSelectionAndSurfacesError() async {
        let service = RecordingAppIconService(
            supportsAlternateIcons: true,
            alternateIconName: nil,
            changeError: AppIconTestError.changeFailed
        )
        let model = AppIconSelectionModel(service: service)
        model.load()

        await model.select(.ocean)

        #expect(model.selectedOption == .primary)
        #expect(model.actionError == .changeFailed)
        #expect(!model.isChanging)
    }

    // Break caught: an in-flight change must serialize selection attempts.
    @Test func concurrentSelectionIsIgnoredUntilFirstChangeCompletes() async {
        let service = RecordingAppIconService(
            supportsAlternateIcons: true, alternateIconName: nil, suspendsChanges: true)
        let model = AppIconSelectionModel(service: service)
        model.load()

        let first = Task { @MainActor in await model.select(.ocean) }
        while service.requests.isEmpty { await Task.yield() }

        #expect(model.isChanging)
        await model.select(.sunset)
        #expect(service.requests == ["AppIcon-Ocean"])

        service.resumeChange()
        await first.value
        #expect(model.selectedOption == .ocean)
        #expect(!model.isChanging)
    }
}

private enum AppIconTestError: Error { case changeFailed }

@MainActor
private final class RecordingAppIconService: AppIconServicing {
    let supportsAlternateIcons: Bool
    private(set) var alternateIconName: String?
    private(set) var requests: [String?] = []
    private let changeError: (any Error)?
    private let suspendsChanges: Bool
    private var continuation: CheckedContinuation<Void, Never>?

    init(
        supportsAlternateIcons: Bool, alternateIconName: String?, changeError: (any Error)? = nil,
        suspendsChanges: Bool = false
    ) {
        self.supportsAlternateIcons = supportsAlternateIcons
        self.alternateIconName = alternateIconName
        self.changeError = changeError
        self.suspendsChanges = suspendsChanges
    }

    func setAlternateIconName(_ name: String?) async throws {
        requests.append(name)
        if suspendsChanges { await withCheckedContinuation { continuation = $0 } }
        if let changeError { throw changeError }
        alternateIconName = name
    }

    func resumeChange() {
        continuation?.resume()
        continuation = nil
    }
}
