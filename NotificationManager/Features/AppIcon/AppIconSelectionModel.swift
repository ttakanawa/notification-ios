import Observation

enum AppIconAvailability: Sendable, Equatable {
    case loading
    case available
    case unsupported
    case configurationError
}

enum AppIconSelectionActionErrorIdentity: Sendable, Equatable {
    case changeFailed
}

@MainActor
@Observable
final class AppIconSelectionModel {
    private(set) var availability: AppIconAvailability = .loading
    private(set) var selectedOption: AppIconOption?
    private(set) var isChanging = false
    private(set) var actionError: AppIconSelectionActionErrorIdentity?

    @ObservationIgnored private let service: any AppIconServicing

    init(service: any AppIconServicing) {
        self.service = service
    }

    func load() {
        actionError = nil
        refreshSelection()
    }

    func select(_ option: AppIconOption) async {
        guard availability == .available,
            !isChanging,
            option != selectedOption
        else { return }

        isChanging = true
        actionError = nil
        defer { isChanging = false }

        do {
            try await service.setAlternateIconName(option.alternateIconName)
            refreshSelection()
        } catch {
            actionError = .changeFailed
        }
    }

    private func refreshSelection() {
        guard let selected = AppIconOption.matching(alternateIconName: service.alternateIconName)
        else {
            selectedOption = nil
            availability = .configurationError
            return
        }

        selectedOption = selected
        availability = service.supportsAlternateIcons ? .available : .unsupported
    }
}
