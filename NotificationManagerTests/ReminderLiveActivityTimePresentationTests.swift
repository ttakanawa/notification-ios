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

    @Test func zeroBeforeWindowAndTheNotificationInstantAreSafe() {
        let countdown = ReminderLiveActivityTimePresentation.countdown(
            startDate: notificationDate, notificationDate: notificationDate
        ).locale(Locale(identifier: "ja_JP"))
        #expect(String(countdown.format(notificationDate).characters) == "0:00")
    }

    @Test func countdownSurvivesEncodingForSystemRendering() throws {
        let countdown = ReminderLiveActivityTimePresentation.countdown(
            startDate: notificationDate.addingTimeInterval(-300), notificationDate: notificationDate
        )
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let restoredCountdown = try decoder.decode(
            SystemFormatStyle.Timer.self, from: encoder.encode(countdown))
        #expect(restoredCountdown == countdown)
    }

    @Test func anEightHourCapBeforeTheNotificationCannotCreateAnInvertedTimerInterval() {
        let event = ReminderLiveActivityEvent(
            reminderID: UUID(), title: "Long lead time",
            startDate: notificationDate.addingTimeInterval(-9 * 3_600),
            endDate: notificationDate.addingTimeInterval(180), notificationDate: notificationDate)
        let state = ReminderActivityAttributes.ContentState(event: event)
        #expect(state.activityEndDate < state.notificationDate)
        let interval = ReminderLiveActivityTimePresentation.elapsedInterval(
            since: state.notificationDate, until: state.activityEndDate)
        #expect(interval.lowerBound == notificationDate)
        #expect(interval.upperBound == notificationDate)
    }

    @Test(arguments: [("en", "Due in ", " elapsed"), ("ja", "通知まで ", "経過")])
    func widgetLabelsIdentifyCountdownAndElapsedCounters(
        language: String, countdownPrefix: String, elapsed: String
    ) throws {
        let pluginsURL = try #require(Bundle.main.builtInPlugInsURL)
        let widgetBundle = try #require(
            Bundle(url: pluginsURL.appendingPathComponent("NotificationManagerWidget.appex")))
        let localizationURL = try #require(
            widgetBundle.url(forResource: language, withExtension: "lproj"))
        let localization = try #require(Bundle(url: localizationURL))

        #expect(
            localization.localizedString(
                forKey: "widget.live-activity.countdown-prefix", value: nil, table: "Widget")
                == countdownPrefix)
        #expect(
            localization.localizedString(
                forKey: "widget.live-activity.after", value: nil, table: "Widget") == elapsed)
    }
}
