import UIKit
import XCTest

final class AcceptanceUITests: XCTestCase {
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
}
