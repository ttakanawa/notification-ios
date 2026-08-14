import UIKit
import XCTest

final class AcceptanceUITests: XCTestCase {
    @MainActor
    func testReminderRowShowsOnlyCompactReminderInformation() {
        let app = launchAcceptanceFixture(
            scenario: "navigation",
            arguments: englishManilaArguments
        )
        let row = app.buttons["reminder-row.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"]

        XCTAssertTrue(row.waitForExistence(timeout: 2))
        XCTAssertFalse(
            app.switches[
                "reminder-row.enabled.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
            ].exists
        )
        XCTAssertTrue(app.staticTexts["Renewal documents"].exists)
        let compactSchedule = app.descendants(matching: .any)[
            "reminder-row.compact-schedule"
        ]
        let times = app.descendants(matching: .any)["reminder-row.times"]
        let dayOffset = app.descendants(matching: .any)["reminder-row.day-offset"]
        let recurrence = app.descendants(matching: .any)["reminder-row.recurrence"]
        XCTAssertTrue(compactSchedule.exists)
        XCTAssertTrue(times.label.localizedCaseInsensitiveContains("9:50 AM"), times.label)
        XCTAssertTrue(times.label.localizedCaseInsensitiveContains("9:50 PM"), times.label)
        XCTAssertTrue(times.label.localizedCaseInsensitiveContains("EDT"), times.label)
        XCTAssertEqual(dayOffset.label, "1 day ago")
        XCTAssertEqual(recurrence.label, "Repeat")
        XCTAssertEqual(recurrence.value as? String, "Every week")
        XCTAssertTrue(app.buttons["reminder.tag-filter.menu"].exists)
        XCTAssertFalse(row.label.localizedCaseInsensitiveContains("Travel"), row.label)
        XCTAssertFalse(app.descendants(matching: .any)["reminder-row.device-status"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["reminder-row.group-outcome"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["reminder-row.repeat-summary"].exists)

        row.tap()
        XCTAssertTrue(app.otherElements["reminder-form.root"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testRecurringReminderKeepsRepeatSummaryWhenNoNextAlertExists() {
        let app = launchAcceptanceFixture(
            scenario: "enabled-capacity",
            arguments: englishManilaArguments
        )
        let row = app.buttons["reminder-row.ffffffff-ffff-ffff-ffff-ffffffffffff"]

        XCTAssertTrue(row.waitForExistence(timeout: 2))
        let recurrence = app.descendants(matching: .any)["reminder-row.recurrence"]
        XCTAssertTrue(recurrence.exists)
        XCTAssertEqual(recurrence.label, "Repeat")
        XCTAssertEqual(recurrence.value as? String, "Every day")
    }

    @MainActor
    func testOneTimeReminderOmitsRecurrenceButKeepsTimes() {
        let app = launchAcceptanceFixture(scenario: "one-time-row")
        let row = app.buttons["reminder-row.99999999-9999-9999-9999-999999999999"]

        XCTAssertTrue(row.waitForExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any)["reminder-row.times"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["reminder-row.recurrence"].exists)
        XCTAssertFalse(row.label.localizedCaseInsensitiveContains("One time"), row.label)
    }

    @MainActor
    func testJapaneseMaximumDynamicTypeKeepsCompactRowInformationVisible() {
        let app = launchAcceptanceFixture(
            scenario: "localized-custom-rule",
            arguments: [
                "-AppleLanguages", "(ja)",
                "-AppleLocale", "ja_JP",
                "-AppleTimeZone", "Asia/Manila",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
            ]
        )
        let row = app.buttons["reminder-row.bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"]
        let recurrence = app.descendants(matching: .any)["reminder-row.recurrence"]

        XCTAssertTrue(row.waitForExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any)["reminder-row.times"].exists)
        XCTAssertEqual(recurrence.label, "繰り返し")
        XCTAssertEqual(recurrence.value as? String, "毎週月曜日に繰り返します。")
        XCTAssertLessThanOrEqual(row.frame.maxX, app.windows.firstMatch.frame.maxX + 1)
    }

    @MainActor
    func testAdaptiveFixtureExposesTheExpectedNavigationContract() {
        let app = launchAcceptanceFixture(scenario: "navigation")
        let expectedRoot = UIDevice.current.userInterfaceIdiom == .pad
            ? "adaptive-root.regular-split"
            : "adaptive-root.compact-stack"

        XCTAssertTrue(app.otherElements[expectedRoot].waitForExistence(timeout: 2))
        XCTAssertTrue(
            app.buttons["reminder-row.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"].exists
        )
        XCTAssertTrue(app.otherElements["reminder-list.section.upcoming"].exists)
    }

    @MainActor
    func testJapaneseFixtureKeepsPrivacyAndAccessibilityRoutesDiscoverable() {
        let app = launchAcceptanceFixture(
            scenario: "settings",
            arguments: ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        )

        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["settings.about-privacy"].label.isEmpty)
        app.buttons["settings.about-privacy"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["privacy.disclosure.automaticICloudSync"]
                .waitForExistence(timeout: 1)
        )
    }

    @MainActor
    func testMaximumDynamicTypeRecoveryFixtureKeepsEveryManualEscapeHatch() {
        let app = launchAcceptanceFixture(
            scenario: "data-unavailable",
            arguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
            ]
        )

        XCTAssertTrue(app.otherElements["data-unavailable.root"].waitForExistence(timeout: 2))
        for identifier in [
            "data-unavailable.remove-pending",
            "data-unavailable.open-os-settings",
            "data-unavailable.retry"
        ] {
            XCTAssertTrue(app.buttons[identifier].exists, identifier)
            XCTAssertFalse(app.buttons[identifier].label.isEmpty, identifier)
        }
    }

    @MainActor
    private func launchAcceptanceFixture(
        scenario: String,
        arguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-scenario", scenario]
        app.launchArguments += arguments
        app.launch()
        return app
    }

    private var englishManilaArguments: [String] {
        [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleTimeZone", "Asia/Manila"
        ]
    }
}
