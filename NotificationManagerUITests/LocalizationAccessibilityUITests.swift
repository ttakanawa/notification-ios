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
        let appIconRow = app.buttons["settings.app-icon"]
        XCTAssertTrue(appIconRow.exists)
        XCTAssertEqual(appIconRow.label, "アプリアイコン")
        appIconRow.tap()
        XCTAssertTrue(app.navigationBars["アプリアイコン"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["オーシャン"].exists)
        app.navigationBars["アプリアイコン"].buttons.firstMatch.tap()
        app.buttons["settings.about-privacy"].tap()
        XCTAssertTrue(app.navigationBars["このアプリとプライバシー"].waitForExistence(timeout: 1))
        XCTAssertTrue(
            app.descendants(matching: .any)["privacy.disclosure.automaticICloudSync"].exists
        )
        XCTAssertTrue(
            app.staticTexts[
                "リマインダーとタグは、OS が利用可能にしたときに SwiftData の自動 iCloud 同期を使用します。"
            ].exists
        )
    }

    @MainActor
    func testJapaneseRecoveryUsesBundledRecoveryAndCommonTranslations() {
        let app = launch(
            scenario: "data-unavailable",
            extraArguments: ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        )

        XCTAssertTrue(app.navigationBars["データを利用できません"].waitForExistence(timeout: 2))
        let retry = app.buttons["data-unavailable.retry"]
        scrollToHittable(retry, in: app)
        XCTAssertEqual(retry.label, "再試行")
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
        for identifier in [
            "data-unavailable.remove-pending",
            "data-unavailable.open-os-settings",
            "data-unavailable.retry"
        ] {
            let action = app.buttons[identifier]
            scrollToHittable(action, in: app)
            assertHorizontallyContained(action, in: root)
        }
    }

    @MainActor
    func testMaximumDynamicTypeKeepsDestructiveConfirmationActionsReachable() {
        let app = launch(
            scenario: "navigation",
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
            ]
        )

        app.buttons["reminder-row.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"].tap()
        let delete = app.buttons["reminder-form.delete"]
        scrollToHittable(delete, in: app)
        XCTAssertTrue(delete.waitForExistence(timeout: 2))
        XCTAssertGreaterThanOrEqual(delete.frame.height, 44)
        delete.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 1))
        for identifier in [
            "reminder-form.delete-confirm",
            "reminder-form.delete-cancel"
        ] {
            let action = alert.buttons[identifier].firstMatch
            XCTAssertTrue(action.waitForExistence(timeout: 1))
            XCTAssertTrue(action.isHittable)
        }
    }

    @MainActor
    func testPseudoLocalizationAndForcedRTLKeepLogicalActionsDiscoverable() {
        let app = launch(
            scenario: "data-unavailable",
            extraArguments: [
                "-AppleLanguages", "(en)",
                "-AppleLocale", "ar",
                "-NSDoubleLocalizedStrings", "YES",
                "-NSForceRightToLeftWritingDirection", "YES",
                "-NSForceRightToLeftLayoutDirection", "YES",
                "-AppleTextDirection", "YES"
            ]
        )

        let root = app.otherElements["data-unavailable.root"]
        XCTAssertTrue(root.waitForExistence(timeout: 2))
        let removePending = app.buttons["data-unavailable.remove-pending"]
        let openSettings = app.buttons["data-unavailable.open-os-settings"]
        XCTAssertTrue(removePending.waitForExistence(timeout: 1))
        XCTAssertTrue(openSettings.waitForExistence(timeout: 1))
        XCTAssertLessThan(removePending.frame.minY, openSettings.frame.minY)
        XCTAssertFalse(openSettings.label.localizedCaseInsensitiveContains("pending"))
        assertHorizontallyContained(removePending, in: root)
        assertHorizontallyContained(openSettings, in: root)

        let retry = app.buttons["data-unavailable.retry"]
        scrollToHittable(retry, in: app)
        XCTAssertFalse(retry.label.isEmpty)
        XCTAssertNotEqual(retry.label, "Retry", "Pseudo-localization did not activate visibly.")
        XCTAssertGreaterThan(
            retry.label.count,
            "Retry".count,
            "Double-length pseudo-localization did not expand the visible label."
        )
        assertHorizontallyContained(retry, in: root)
    }

    @MainActor
    private func scrollToHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        attempts: Int = 8
    ) {
        var remainingAttempts = attempts
        while !element.isHittable, remainingAttempts > 0 {
            app.swipeUp()
            remainingAttempts -= 1
        }
        XCTAssertTrue(element.exists)
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func assertHorizontallyContained(
        _ element: XCUIElement,
        in container: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let elementFrame = element.frame
        let containerFrame = container.frame
        XCTAssertGreaterThanOrEqual(
            elementFrame.minX,
            containerFrame.minX - 1,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            elementFrame.maxX,
            containerFrame.maxX + 1,
            file: file,
            line: line
        )
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
