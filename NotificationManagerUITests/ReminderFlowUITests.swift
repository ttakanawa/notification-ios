import XCTest

final class ReminderFlowUITests: XCTestCase {
    @MainActor
    func testNewReminderBeginsWithBlankScheduleAndOrderedSections() throws {
        let app = launch(scenario: "empty-list")
        app.buttons["reminder-list.add"].tap()

        let form = app.otherElements["reminder-form.root"]
        XCTAssertTrue(form.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["reminder-form.save"].isEnabled)

        let identifiers = [
            "reminder-form.section.basic-information",
            "reminder-form.section.date-time",
            "reminder-form.section.repeat",
            "reminder-form.section.early-reminder",
            "reminder-form.section.organization"
        ]
        let frames = identifiers.map { identifier in
            let element = app.otherElements[identifier]
            XCTAssertTrue(element.waitForExistence(timeout: 1), identifier)
            return element.frame.minY
        }
        XCTAssertEqual(frames, frames.sorted())

        let date = app.textFields["reminder-form.date"]
        date.tap()
        date.typeText("2040-")
        XCTAssertEqual(date.value as? String, "2040-")

        let time = app.textFields["reminder-form.time"]
        time.tap()
        time.typeText("09:")
        XCTAssertEqual(time.value as? String, "09:")

        let timeZone = app.textFields["reminder-form.time-zone"]
        timeZone.tap()
        timeZone.typeText("America/")
        XCTAssertEqual(timeZone.value as? String, "America/")
        XCTAssertFalse(app.buttons["reminder-form.save"].isEnabled)
    }

    @MainActor
    func testLocalizedCustomRuleStaysSummaryUntilExplicitEmptyReplacement() {
        let app = launch(scenario: "localized-custom-rule")
        app.buttons["reminder-row.bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"].tap()
        app.buttons["reminder-detail.edit"].tap()

        XCTAssertTrue(app.otherElements["reminder-form.custom.current-summary"].exists)
        XCTAssertFalse(app.textFields["reminder-form.custom.input"].exists)
        XCTAssertTrue(app.buttons["reminder-form.save"].isEnabled)

        app.buttons["reminder-form.custom.replace"].tap()

        let input = app.textFields["reminder-form.custom.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 1))
        input.tap()
        input.typeText("every 3 ")
        XCTAssertEqual(input.value as? String, "every 3 ")
        XCTAssertFalse(app.buttons["reminder-form.save"].isEnabled)
    }

    @MainActor
    func testEnglishTypoSuggestionRequiresSelectionAndApply() {
        let app = launch(scenario: "localized-custom-rule")
        app.buttons["reminder-row.bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"].tap()
        app.buttons["reminder-detail.edit"].tap()
        app.buttons["reminder-form.custom.replace"].tap()

        let input = app.textFields["reminder-form.custom.input"]
        input.tap()
        input.typeText("Every Tuseday")
        app.buttons["reminder-form.custom.preview-button"].tap()

        let suggestion = app.buttons["reminder-form.custom.suggestion"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 1))
        XCTAssertEqual(input.value as? String, "Every Tuseday")
        XCTAssertFalse(app.buttons["reminder-form.save"].isEnabled)

        suggestion.tap()

        XCTAssertTrue(
            app.otherElements["reminder-form.custom.preview-result"]
                .waitForExistence(timeout: 1)
        )
        XCTAssertEqual(input.value as? String, "Every Tuesday")
        XCTAssertFalse(app.buttons["reminder-form.save"].isEnabled)

        app.buttons["reminder-form.custom.apply"].tap()
        XCTAssertTrue(app.buttons["reminder-form.save"].isEnabled)
    }

    @MainActor
    func testOpaqueScheduleKeepsMetadataEditableAndScheduleReadOnly() {
        let app = launch(scenario: "unsupported-schedule")
        app.buttons["reminder-row.cccccccc-cccc-cccc-cccc-cccccccccccc"].tap()
        app.buttons["reminder-detail.edit"].tap()

        XCTAssertTrue(app.textFields["reminder-form.title"].isEnabled)
        XCTAssertTrue(app.switches["reminder-form.enabled"].isEnabled)
        XCTAssertTrue(app.buttons["reminder-form.delete"].isEnabled)
        XCTAssertTrue(app.otherElements["reminder-form.schedule-read-only"].exists)
        XCTAssertFalse(app.textFields["reminder-form.date"].isEnabled)
        XCTAssertFalse(app.textFields["reminder-form.time"].isEnabled)
        XCTAssertFalse(app.textFields["reminder-form.time-zone"].isEnabled)

        app.buttons["reminder-form.delete"].tap()
        XCTAssertTrue(app.buttons["reminder-form.delete-confirm"].waitForExistence(timeout: 1))
        app.buttons["reminder-form.delete-cancel"].tap()
        XCTAssertTrue(app.otherElements["reminder-form.root"].exists)

        app.buttons["reminder-form.delete"].tap()
        let confirm = app.buttons["reminder-form.delete-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 1))
        confirm.tap()
        XCTAssertTrue(app.otherElements["reminder-list.root"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testCapacityThenExpiredConsentKeepsFormValuesUntilSaveCompletes() {
        let app = launch(scenario: "capacity-and-expired-confirmations")
        app.buttons["reminder-row.dddddddd-dddd-dddd-dddd-dddddddddddd"].tap()
        app.buttons["reminder-detail.edit"].tap()
        let title = app.textFields["reminder-form.title"]
        title.tap()
        title.typeText(" updated")

        app.buttons["reminder-form.save"].tap()
        XCTAssertTrue(
            app.otherElements["reminder-form.capacity-confirmation"].waitForExistence(timeout: 1)
        )
        app.buttons["reminder-form.capacity-confirm"].tap()
        XCTAssertTrue(app.buttons["reminder-form.expired-confirm"].waitForExistence(timeout: 1))
        XCTAssertTrue(title.value as? String == "Capacity edit updated")
    }

    @MainActor
    private func launch(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-scenario", scenario]
        app.launch()
        return app
    }
}
