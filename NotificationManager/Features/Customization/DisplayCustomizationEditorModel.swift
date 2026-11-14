import Foundation
import NotificationManagerDomain
import NotificationManagerWidgetSupport
import Observation

@MainActor
@Observable
final class DisplayCustomizationEditorModel {
    var notificationEnabled = false
    var notificationTitle = "{title}"
    var notificationBody = "{notes}\n{notificationTime} {timeZone}"
    var liveActivityEnabled = false
    var liveActivityTitle = "{title}"
    var liveActivityBody = "{notes}\n{notificationTime} {timeZone}\n{remaining} / {elapsed}"
    private(set) var isLoading = true
    private(set) var isSaving = false
    private(set) var isUnsupported = false
    private(set) var errorKey: String?
    private(set) var didSave = false

    @ObservationIgnored private let loadData: @MainActor () async throws -> Data?
    @ObservationIgnored private let saveData: @MainActor (Data?) async throws -> Void
    @ObservationIgnored private let canEdit: @MainActor () -> Bool
    @ObservationIgnored private var hasLoaded = false

    init(
        load: @escaping @MainActor () async throws -> Data?,
        save: @escaping @MainActor (Data?) async throws -> Void,
        canEdit: @escaping @MainActor () -> Bool
    ) {
        loadData = load
        saveData = save
        self.canEdit = canEdit
    }

    func load() async {
        guard !hasLoaded else { return }
        isLoading = true
        errorKey = nil
        defer { isLoading = false }
        do {
            let data = try await loadData()
            hasLoaded = true
            guard let data else { return }
            guard let value = DisplayCustomization.decodeSupported(data) else {
                isUnsupported = true
                return
            }
            notificationEnabled = value.notification != nil
            notificationTitle = value.notification?.title ?? notificationTitle
            notificationBody = value.notification?.body ?? notificationBody
            liveActivityEnabled = value.liveActivity != nil
            liveActivityTitle = value.liveActivity?.title ?? liveActivityTitle
            liveActivityBody = value.liveActivity?.body ?? liveActivityBody
        } catch {
            errorKey = "customization.error.load"
        }
    }

    func replaceUnsupported() {
        guard canEdit() else { return }
        isUnsupported = false
        notificationEnabled = false
        liveActivityEnabled = false
    }

    func save() async {
        guard hasLoaded, !isLoading, !isSaving, !isUnsupported, canEdit() else { return }
        isSaving = true
        errorKey = nil
        defer { isSaving = false }
        do {
            let previewValues = Self.previewValues
            if notificationEnabled {
                _ = try DisplayTemplateRenderer.notification(
                    title: notificationTitle, body: notificationBody, values: previewValues)
            }
            if liveActivityEnabled {
                _ = try DisplayTemplateRenderer.liveActivity(
                    title: liveActivityTitle, body: liveActivityBody, values: previewValues)
            }
            let value = DisplayCustomization(
                notification: notificationEnabled
                    ? DisplayTemplate(title: notificationTitle, body: notificationBody) : nil,
                liveActivity: liveActivityEnabled
                    ? DisplayTemplate(title: liveActivityTitle, body: liveActivityBody) : nil)
            let data =
                notificationEnabled || liveActivityEnabled ? try JSONEncoder().encode(value) : nil
            guard canEdit() else { return }
            try await saveData(data)
            didSave = true
        } catch is DisplayTemplateError {
            errorKey = "customization.error.template"
        } catch {
            errorKey = "customization.error.save"
        }
    }

    nonisolated static var previewValues: DisplayTemplateValues {
        DisplayTemplateValues(
            title: "Punctual", notes: "Sample", notificationTime: "09:30", timeZone: "Asia/Tokyo")
    }
}
