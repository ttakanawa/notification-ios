import Foundation
import NotificationManagerWidgetSupport
import SwiftUI
import Testing

@Suite("Live Activity second-resolution time presentation")
struct LiveActivityTimePresentationTests {
    private let notificationDate = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(arguments: ["en_US", "ja_JP"])
    func countdownChangesEverySecondAcrossTheMinuteBoundary(localeIdentifier: String) throws {
        let timer = ReminderLiveActivityTimePresentation.countdown(
            startDate: notificationDate.addingTimeInterval(-300), notificationDate: notificationDate
        ).locale(Locale(identifier: localeIdentifier))
        let oneMinuteBefore = notificationDate.addingTimeInterval(-60)

        #expect(String(timer.format(oneMinuteBefore).characters) == "1:00")
        #expect(String(timer.format(oneMinuteBefore.addingTimeInterval(1)).characters) == "0:59")
        let nextUpdate = try #require(timer.discreteInput(after: oneMinuteBefore))
        #expect(nextUpdate.timeIntervalSince(oneMinuteBefore) == 1)
    }

    @Test(arguments: ["en_US", "ja_JP"])
    func elapsedTimeKeepsSecondsBeyondTheDisplayWindow(localeIdentifier: String) throws {
        let stopwatch = ReminderLiveActivityTimePresentation.elapsed(since: notificationDate)
            .locale(Locale(identifier: localeIdentifier))
        let originalWindowEnd = notificationDate.addingTimeInterval(600)
        let oneHourLater = notificationDate.addingTimeInterval(3_661)

        #expect(String(stopwatch.format(originalWindowEnd).characters) == "10:00")
        #expect(
            String(stopwatch.format(originalWindowEnd.addingTimeInterval(1)).characters) == "10:01")
        #expect(String(stopwatch.format(oneHourLater).characters) == "61:01")
        let nextUpdate = try #require(stopwatch.discreteInput(after: originalWindowEnd))
        #expect(nextUpdate.timeIntervalSince(originalWindowEnd) == 1)
    }

    @Test func zeroBeforeWindowAndTheNotificationInstantAreSafe() {
        let countdown = ReminderLiveActivityTimePresentation.countdown(
            startDate: notificationDate, notificationDate: notificationDate
        ).locale(Locale(identifier: "ja_JP"))
        let elapsed = ReminderLiveActivityTimePresentation.elapsed(since: notificationDate)
            .locale(Locale(identifier: "ja_JP"))

        #expect(String(countdown.format(notificationDate).characters) == "0:00")
        #expect(String(elapsed.format(notificationDate).characters) == "00:00")
        #expect(
            String(elapsed.format(notificationDate.addingTimeInterval(1)).characters) == "00:01")
    }

    @Test func builtInStylesSurviveEncodingForSystemRendering() throws {
        let countdown = ReminderLiveActivityTimePresentation.countdown(
            startDate: notificationDate.addingTimeInterval(-300), notificationDate: notificationDate
        )
        let elapsed = ReminderLiveActivityTimePresentation.elapsed(since: notificationDate)
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let restoredCountdown = try decoder.decode(
            SystemFormatStyle.Timer.self, from: encoder.encode(countdown))
        let restoredElapsed = try decoder.decode(
            SystemFormatStyle.Stopwatch.self, from: encoder.encode(elapsed))

        #expect(restoredCountdown == countdown)
        #expect(restoredElapsed == elapsed)
    }

    @Test(arguments: [("en", " before", " elapsed"), ("ja", "前", "経過")])
    func widgetSuffixesDistinguishUpcomingFromElapsedTime(
        language: String, before: String, elapsed: String
    ) throws {
        let pluginsURL = try #require(Bundle.main.builtInPlugInsURL)
        let widgetBundle = try #require(
            Bundle(url: pluginsURL.appendingPathComponent("NotificationManagerWidget.appex")))
        let localizationURL = try #require(
            widgetBundle.url(forResource: language, withExtension: "lproj"))
        let localization = try #require(Bundle(url: localizationURL))

        #expect(
            localization.localizedString(
                forKey: "widget.live-activity.before", value: nil, table: "Widget") == before)
        #expect(
            localization.localizedString(
                forKey: "widget.live-activity.after", value: nil, table: "Widget") == elapsed)
    }
}
