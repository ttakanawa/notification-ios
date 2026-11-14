import Foundation
import Testing

@testable import NotificationManagerWidgetSupport

struct DisplayTemplateRendererTests {
    private let values = DisplayTemplateValues(
        title: "{notes}", notes: "研究 🐳", notificationTime: "09:30", timeZone: "Asia/Tokyo")

    @Test func valuesAreLiteralAndEscapedBracesAreSupported() throws {
        let rendered = try DisplayTemplateRenderer.notification(
            title: "{{{title}}}", body: "{notes}\n{notificationTime} {timeZone}", values: values)
        #expect(rendered.title == "{{notes}}")
        #expect(rendered.body == "研究 🐳\n09:30 Asia/Tokyo")
    }

    @Test func timersRemainNativeSegmentsAndAreRejectedInNotifications() throws {
        let rendered = try DisplayTemplateRenderer.liveActivity(
            title: "{title}", body: "あと {remaining} / {elapsed}", values: values)
        #expect(rendered.body.map(\.kind) == [.text, .remaining, .text, .elapsed])
        #expect(throws: DisplayTemplateError.timerUnavailable) {
            try DisplayTemplateRenderer.notification(
                title: "Title", body: "{remaining}", values: values)
        }
    }

    @Test func invalidAndOversizeTemplatesCannotCreateBrokenActivityPayloads() {
        for text in ["{unknown}", "{title", "title}", "{nested{title}"] {
            #expect(throws: (any Error).self) {
                try DisplayTemplateRenderer.render(text, values: values, allowsTimers: true)
            }
        }
        #expect(throws: DisplayTemplateError.emptyTitle) {
            try DisplayTemplateRenderer.liveActivity(title: "  ", body: "", values: values)
        }
        let largeValues = DisplayTemplateValues(
            title: "title", notes: String(repeating: "🐳", count: 1_000), notificationTime: "",
            timeZone: "")
        #expect(throws: DisplayTemplateError.tooLong) {
            try DisplayTemplateRenderer.liveActivity(
                title: "{title}", body: "{notes}", values: largeValues)
        }
    }
}
