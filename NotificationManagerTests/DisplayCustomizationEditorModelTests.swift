import Foundation
import NotificationManagerDomain
import Testing

@testable import NotificationManager

@MainActor
struct DisplayCustomizationEditorModelTests {
    @Test func futureCustomizationRequiresExplicitReplacementBeforeSave() async throws {
        let opaque = Data(#"{"schemaVersion":42,"future":"keep"}"#.utf8)
        var saved: [Data?] = []
        let editor = DisplayCustomizationEditorModel(
            load: { opaque }, save: { saved.append($0) }, canEdit: { true })
        await editor.load()
        #expect(editor.isUnsupported)
        await editor.save()
        #expect(saved.isEmpty)
        editor.replaceUnsupported()
        editor.notificationEnabled = true
        await editor.save()
        #expect(saved.count == 1)
        let value = DisplayCustomization.decodeSupported(try #require(saved.first ?? nil))
        #expect(value?.notification?.title == "{title}")
    }

    @Test func revocationRetainsTemplatesAndPreventsWrites() async throws {
        let value = DisplayCustomization(
            notification: DisplayTemplate(title: "Saved", body: "{notes}"))
        let data = try JSONEncoder().encode(value)
        var purchased = true
        var writes = 0
        let editor = DisplayCustomizationEditorModel(
            load: { data }, save: { _ in writes += 1 }, canEdit: { purchased })
        await editor.load()
        purchased = false
        await editor.save()
        #expect(writes == 0)
        #expect(editor.notificationTitle == "Saved")
        #expect(editor.notificationEnabled)
    }

    @Test func invalidNotificationTimerDoesNotWriteAndLoadingFailureCannotEraseData() async {
        var writes = 0
        let editor = DisplayCustomizationEditorModel(
            load: { nil }, save: { _ in writes += 1 }, canEdit: { true })
        await editor.load()
        editor.notificationEnabled = true
        editor.notificationBody = "{remaining}"
        await editor.save()
        #expect(writes == 0)
        #expect(editor.errorKey == "customization.error.template")
        let failed = DisplayCustomizationEditorModel(
            load: { throw CocoaError(.fileReadNoPermission) }, save: { _ in writes += 1 },
            canEdit: { true })
        await failed.load()
        await failed.save()
        #expect(writes == 0)
    }
}
