import XCTest

final class LocalizationAccessibilityUITests: XCTestCase {
    @MainActor
    func testJapaneseSettingsAndPrivacyUseBundledTranslations() {
        let app = launch(
            scenario: "settings",
            extraArguments: ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        )

        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["通知設定を開く"].exists)
        app.buttons["settings.about-privacy"].tap()
        XCTAssertTrue(app.navigationBars["このアプリとプライバシー"].waitForExistence(timeout: 1))
        XCTAssertTrue(
            app.descendants(matching: .any)["privacy.disclosure.automaticICloudSync"].exists
        )
    }

    @MainActor
    func testMaximumDynamicTypeKeepsRecoveryActionsReachable() {
        let app = launch(
            scenario: "data-unavailable",
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
            ]
        )

        let root = app.otherElements["data-unavailable.root"]
        XCTAssertTrue(root.waitForExistence(timeout: 2))
        app.swipeUp()
        XCTAssertTrue(app.buttons["data-unavailable.retry"].isHittable)
    }

    @MainActor
    func testPseudoLocalizationAndForcedRTLKeepLogicalActionsDiscoverable() {
        let app = launch(
            scenario: "data-unavailable",
            extraArguments: [
                "-AppleLanguages", "(en-XA)",
                "-AppleLocale", "ar",
                "-NSForceRightToLeftWritingDirection", "YES",
                "-AppleTextDirection", "YES"
            ]
        )

        XCTAssertTrue(app.otherElements["data-unavailable.root"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["data-unavailable.remove-pending"].exists)
        XCTAssertTrue(app.buttons["data-unavailable.open-os-settings"].exists)
    }

    @MainActor
    private func launch(
        scenario: String,
        extraArguments: [String]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-scenario", scenario]
        app.launchArguments += extraArguments
        app.launch()
        return app
    }
}
