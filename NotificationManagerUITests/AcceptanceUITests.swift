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
        XCTAssertTrue(app.buttons["reminder.tag-filter.all"].exists)
        let timeZoneFilter = app.buttons["reminder.time-zone-filter.menu"]
        XCTAssertTrue(timeZoneFilter.exists)
        XCTAssertEqual(timeZoneFilter.label, "Filter by Time Zone")
        XCTAssertEqual(timeZoneFilter.value as? String, "All Time Zones")
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
    func testTimeZoneFilterShowsOnlyMatchingConfiguredReminder() {
        let app = launchAcceptanceFixture(
            scenario: "time-zone-filter",
            arguments: englishManilaArguments
        )
        let newYork = app.buttons[
            "reminder-row.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        ]
        let manila = app.buttons[
            "reminder-row.12121212-1212-1212-1212-121212121212"
        ]

        XCTAssertTrue(newYork.waitForExistence(timeout: 2))
        XCTAssertTrue(manila.waitForExistence(timeout: 2))

        let timeZoneFilter = app.buttons["reminder.time-zone-filter.menu"]
        XCTAssertEqual(timeZoneFilter.label, "Filter by Time Zone")
        XCTAssertEqual(timeZoneFilter.value as? String, "All Time Zones")

        timeZoneFilter.tap()
        let manilaOption = app.buttons["reminder.time-zone-filter.Asia/Manila"]
        XCTAssertTrue(manilaOption.waitForExistence(timeout: 1))
        manilaOption.tap()

        XCTAssertTrue(manila.waitForExistence(timeout: 1))
        XCTAssertTrue(newYork.waitForNonExistence(timeout: 1))
        XCTAssertEqual(timeZoneFilter.label, "Filter by Time Zone")
        XCTAssertEqual(timeZoneFilter.value as? String, "Asia/Manila")

        timeZoneFilter.tap()
        let allTimeZones = app.buttons["reminder.time-zone-filter.all"]
        XCTAssertTrue(allTimeZones.waitForExistence(timeout: 1))
        allTimeZones.tap()

        XCTAssertTrue(newYork.waitForExistence(timeout: 1))
        XCTAssertTrue(manila.waitForExistence(timeout: 1))
        XCTAssertEqual(timeZoneFilter.value as? String, "All Time Zones")
    }

    @MainActor
    func testTagChipsScrollHorizontallyAndFilterReminders() {
        let app = launchAcceptanceFixture(
            scenario: "tag-filter",
            arguments: englishManilaArguments
        )
        let scrollView = app.scrollViews["reminder.tag-filter.scroll"]
        let allTags = app.buttons["reminder.tag-filter.all"]
        let family = app.buttons[
            "reminder.tag-filter.11111111-1111-1111-1111-111111111111"
        ]
        let tech = app.buttons[
            "reminder.tag-filter.44444444-4444-4444-4444-444444444444"
        ]
        let familyReminder = app.buttons[
            "reminder-row.00000000-0000-0000-0000-000000000001"
        ]
        let techReminder = app.buttons[
            "reminder-row.00000000-0000-0000-0000-000000000004"
        ]

        XCTAssertTrue(scrollView.waitForExistence(timeout: 2))
        XCTAssertTrue(allTags.exists)
        XCTAssertTrue(allTags.isSelected)
        XCTAssertGreaterThanOrEqual(allTags.frame.height, 44)
        XCTAssertTrue(family.exists)
        XCTAssertTrue(familyReminder.exists)
        XCTAssertTrue(techReminder.exists)

        XCTAssertTrue(tech.waitForExistence(timeout: 1))
        let initialTechMinX = tech.frame.minX
        for _ in 0..<8 {
            if tech.isHittable {
                break
            }
            scrollView.swipeLeft(velocity: .fast)
        }
        XCTAssertTrue(tech.isHittable)
        XCTAssertLessThan(tech.frame.minX, initialTechMinX)
        tech.tap()

        XCTAssertTrue(tech.isSelected)
        XCTAssertTrue(techReminder.waitForExistence(timeout: 1))
        XCTAssertTrue(familyReminder.waitForNonExistence(timeout: 1))

        XCTAssertTrue(allTags.waitForExistence(timeout: 1))
        let scrolledAllTagsMaxX = allTags.frame.maxX
        for _ in 0..<8 {
            if allTags.isHittable {
                break
            }
            scrollView.swipeRight(velocity: .fast)
        }
        XCTAssertTrue(allTags.isHittable)
        XCTAssertGreaterThan(allTags.frame.maxX, scrolledAllTagsMaxX)
        allTags.tap()

        XCTAssertTrue(allTags.isSelected)
        XCTAssertTrue(familyReminder.waitForExistence(timeout: 1))
        XCTAssertTrue(techReminder.exists)
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
        let expectedRoot =
            UIDevice.current.userInterfaceIdiom == .pad
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
