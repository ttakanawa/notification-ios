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
    func pairedCountersAdvanceAcrossTheNotification(localeIdentifier: String) throws {
        let event = ReminderLiveActivityEvent(
            reminderID: UUID(), title: "Paired counters",
            startDate: notificationDate.addingTimeInterval(-300),
            endDate: notificationDate.addingTimeInterval(180), notificationDate: notificationDate)
        let state = ReminderActivityAttributes.ContentState(
            event: event, notificationHasOccurred: false)
        let locale = Locale(identifier: localeIdentifier)
        let countdown = ReminderLiveActivityTimePresentation.countdown(
            startDate: state.startDate, notificationDate: state.notificationDate
        ).locale(locale)
        let elapsed = ReminderLiveActivityTimePresentation.elapsed(
            since: state.notificationDate, until: state.activityEndDate
        ).locale(locale)
        let samples: [(offset: TimeInterval, countdown: String, elapsed: String)] = [
            (-80, "1:20", "0:00"),
            (-1, "0:01", "0:00"),
            (0, "0:00", "0:00"),
            (1, "0:00", "0:01"),
            (80, "0:00", "1:20"),
            (81, "0:00", "1:21"),
            (360, "0:00", "3:00")
        ]

        // Both native styles are created before the notification and reused across
        // the boundary; no phase flag or replacement content starts the elapsed row.
        for sample in samples {
            let date = state.notificationDate.addingTimeInterval(sample.offset)
            #expect(String(countdown.format(date).characters) == sample.countdown)
            #expect(String(elapsed.format(date).characters) == sample.elapsed)
        }
        let eightySecondsAfter = state.notificationDate.addingTimeInterval(80)
        let nextUpdate = try #require(elapsed.discreteInput(after: eightySecondsAfter))
        #expect(nextUpdate == state.notificationDate.addingTimeInterval(81))
    }

    @Test(arguments: ["en_US", "ja_JP"])
    func threeMinuteWindowStopsAtItsExactEnd(localeIdentifier: String) throws {
        let endDate = notificationDate.addingTimeInterval(180)
        let timer = ReminderLiveActivityTimePresentation.elapsed(
            since: notificationDate, until: endDate
        )
        .locale(Locale(identifier: localeIdentifier))

        #expect(String(timer.format(endDate.addingTimeInterval(-1)).characters) == "2:59")
        #expect(String(timer.format(endDate).characters) == "3:00")
        #expect(String(timer.format(endDate.addingTimeInterval(1)).characters) == "3:00")
        #expect(
            String(timer.format(notificationDate.addingTimeInterval(360)).characters) == "3:00")
        let lastUpdate = try #require(timer.discreteInput(after: endDate.addingTimeInterval(-1)))
        #expect(lastUpdate == endDate)
        #expect(timer.discreteInput(after: endDate) == nil)
    }

    @Test func zeroAfterWindowCannotCountPastTheNotification() {
        let timer = ReminderLiveActivityTimePresentation.elapsed(
            since: notificationDate, until: notificationDate)
        #expect(String(timer.format(notificationDate).characters) == "0:00")
        #expect(String(timer.format(notificationDate.addingTimeInterval(360)).characters) == "0:00")
        #expect(timer.discreteInput(after: notificationDate) == nil)
    }

    @Test func zeroBeforeWindowAndTheNotificationInstantAreSafe() {
        let countdown = ReminderLiveActivityTimePresentation.countdown(
            startDate: notificationDate, notificationDate: notificationDate
        ).locale(Locale(identifier: "ja_JP"))
        let elapsed = ReminderLiveActivityTimePresentation.elapsed(
            since: notificationDate, until: notificationDate.addingTimeInterval(600)
        )
        .locale(Locale(identifier: "ja_JP"))

        #expect(String(countdown.format(notificationDate).characters) == "0:00")
        #expect(String(elapsed.format(notificationDate).characters) == "0:00")
        #expect(
            String(elapsed.format(notificationDate.addingTimeInterval(1)).characters) == "0:01")
    }

    @Test func builtInStylesSurviveEncodingForSystemRendering() throws {
        let countdown = ReminderLiveActivityTimePresentation.countdown(
            startDate: notificationDate.addingTimeInterval(-300), notificationDate: notificationDate
        )
        let elapsed = ReminderLiveActivityTimePresentation.elapsed(
            since: notificationDate, until: notificationDate.addingTimeInterval(180))
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let restoredCountdown = try decoder.decode(
            SystemFormatStyle.Timer.self, from: encoder.encode(countdown))
        let restoredElapsed = try decoder.decode(
            SystemFormatStyle.Timer.self, from: encoder.encode(elapsed))

        #expect(restoredCountdown == countdown)
        #expect(restoredElapsed == elapsed)
        #expect(
            String(restoredElapsed.format(notificationDate.addingTimeInterval(360)).characters)
                == "3:00")
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
