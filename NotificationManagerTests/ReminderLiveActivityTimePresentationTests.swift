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

    @Test(arguments: [0.0, 60.0, 180.0])
    func elapsedTimerOutlastsCleanupWithoutExtendingTheActivityWindow(afterSeconds: TimeInterval) {
        let event = ReminderLiveActivityEvent(
            reminderID: UUID(), title: "Continued elapsed display",
            startDate: notificationDate.addingTimeInterval(-300),
            endDate: notificationDate.addingTimeInterval(afterSeconds),
            notificationDate: notificationDate)
        let state = ReminderActivityAttributes.ContentState(event: event)
        let interval = ReminderLiveActivityTimePresentation.elapsedInterval(
            since: state.notificationDate)
        #expect(interval.lowerBound == notificationDate)
        #expect(interval.contains(state.activityEndDate.addingTimeInterval(1)))
        #expect(interval.contains(state.activityEndDate.addingTimeInterval(80)))
        #expect(state.activityEndDate == notificationDate.addingTimeInterval(afterSeconds))
        #expect(
            ReminderLiveActivitySelection.select(
                events: [event], at: state.activityEndDate, supportsScheduling: true
            ).isEmpty)
    }

    @Test func elapsedTimerCoversLateRecoveryAndTheSystemLockScreenLifetime() {
        let event = ReminderLiveActivityEvent(
            reminderID: UUID(), title: "Late recovery", startDate: notificationDate,
            endDate: notificationDate.addingTimeInterval(8 * 3_600),
            notificationDate: notificationDate)
        let lastRecovery = event.activityEndDate.addingTimeInterval(-1)
        #expect(
            ReminderLiveActivitySelection.select(
                events: [event], at: lastRecovery, supportsScheduling: true
            ) == [event])
        let interval = ReminderLiveActivityTimePresentation.elapsedInterval(
            since: notificationDate)
        #expect(interval.contains(lastRecovery.addingTimeInterval(12 * 3_600)))
        #expect(interval.upperBound.timeIntervalSince1970.isFinite)
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
