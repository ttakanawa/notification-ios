import XCTest

final class SettingsRecoveryUITests: XCTestCase {
    @MainActor
    func testSettingsExposeDevicePreferenceAuthorizationTagsAndPrivacy() {
        let app = launch(scenario: "settings")

        XCTAssertTrue(app.otherElements["settings.root"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.switches["settings.notifications-this-device"].exists)
        XCTAssertTrue(app.staticTexts["settings.authorization-status"].exists)
        XCTAssertTrue(app.staticTexts["settings.authorization-raw-value"].exists)
        XCTAssertTrue(app.buttons["settings.open-os-settings"].exists)

        app.buttons["settings.tags"].tap()
        XCTAssertTrue(app.otherElements["tags.management.root"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["Travel"].exists)
    }

    @MainActor
    func testTagCreateKeepsUserNameVerbatimAndDeleteExplainsRelationshipBehavior() {
        let app = launch(scenario: "settings")
        let tagsButton = app.buttons["settings.tags"]
        XCTAssertTrue(tagsButton.waitForExistence(timeout: 2))
        tagsButton.tap()

        let name = app.textFields["tags.management.new-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 1))
        name.tap()
        name.typeText("日本 Travel")
        app.buttons["tags.management.create"].tap()

        XCTAssertTrue(app.staticTexts["日本 Travel"].waitForExistence(timeout: 1))
        app.buttons["tags.management.delete.11111111-1111-1111-1111-111111111111"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 1))
        XCTAssertTrue(
            alert.buttons["tags.management.delete-confirm"].firstMatch
                .waitForExistence(timeout: 1)
        )
        XCTAssertTrue(
            app.staticTexts[
                "Deleting this tag removes it from reminders but does not delete any reminder."
            ].exists
        )
    }

    @MainActor
    func testDataUnavailablePreservesStoreByDefaultAndOffersIndependentActions() {
        let app = launch(scenario: "data-unavailable")

        XCTAssertTrue(app.otherElements["data-unavailable.root"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["data-unavailable.notifications-may-continue"].exists)
        XCTAssertTrue(app.switches["data-unavailable.notifications-this-device"].exists)
        XCTAssertTrue(app.buttons["data-unavailable.remove-pending"].exists)
        XCTAssertTrue(app.buttons["data-unavailable.open-os-settings"].exists)
        XCTAssertTrue(app.buttons["data-unavailable.retry"].exists)
        XCTAssertFalse(app.buttons["data-unavailable.delete-store"].exists)
    }

    @MainActor
    func testNotificationUnavailableScreenNeverDisplaysReminderContentOrLink() {
        let app = launch(scenario: "notification-unavailable")

        XCTAssertTrue(
            app.otherElements["notification-unavailable.root"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Sensitive Visa Title"].exists)
        XCTAssertFalse(app.staticTexts["Sensitive Notes"].exists)
        XCTAssertFalse(app.links["https://sensitive.example"].exists)
    }

    @MainActor
    private func launch(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-scenario", scenario]
        app.launch()
        return app
    }
}
