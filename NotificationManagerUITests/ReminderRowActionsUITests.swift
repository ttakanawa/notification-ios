import XCTest

final class ReminderRowActionsUITests: XCTestCase {
    private let reminderID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

    @MainActor
    func testTrailingSwipeOffersEditDuplicateDeleteWithoutExecutingAnAction() {
        let app = launch()
        let row = app.buttons["reminder-row.\(reminderID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        XCTAssertEqual(row.switches.count, 0)
        row.swipeLeft()

        let edit = app.buttons["reminder-row.edit.\(reminderID)"]
        let duplicate = app.buttons["reminder-row.duplicate.\(reminderID)"]
        let delete = app.buttons["reminder-row.delete.\(reminderID)"]
        XCTAssertTrue(edit.waitForExistence(timeout: 2))
        XCTAssertTrue(duplicate.isEnabled)
        XCTAssertTrue(delete.exists)
        XCTAssertLessThan(edit.frame.minX, duplicate.frame.minX)
        XCTAssertLessThan(duplicate.frame.minX, delete.frame.minX)
        XCTAssertFalse(app.buttons["reminder-row.toggle-enabled.\(reminderID)"].exists)
        XCTAssertFalse(app.otherElements["reminder-form.root"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "reminder-trailing-swipe-actions"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        edit.tap()
        XCTAssertTrue(app.textFields["reminder-form.title"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.textFields["reminder-form.title"].value as? String, "Visa renewal")
    }

    @MainActor
    func testDuplicateOpensPrefilledUnsavedCreationForm() {
        let app = launch()
        let row = app.buttons["reminder-row.\(reminderID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        row.swipeLeft()
        let duplicate = app.buttons["reminder-row.duplicate.\(reminderID)"]
        XCTAssertTrue(duplicate.waitForExistence(timeout: 2))
        duplicate.tap()

        let title = app.textFields["reminder-form.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        XCTAssertEqual(title.value as? String, "Visa renewal")
        XCTAssertEqual(
            app.textFields["reminder-form.notes"].value as? String,
            "Renewal documents"
        )
        XCTAssertTrue(app.buttons["reminder-form.save"].isEnabled)
        XCTAssertFalse(app.buttons["reminder-form.back"].exists)
    }

    @MainActor
    func testSwipeDeleteCanBeCancelledThenConfirmed() {
        let app = launch()
        let row = app.buttons["reminder-row.\(reminderID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        row.swipeLeft()
        let delete = app.buttons["reminder-row.delete.\(reminderID)"]
        XCTAssertTrue(delete.waitForExistence(timeout: 2))
        delete.tap()

        let cancel = app.alerts.buttons["reminder-list.delete-cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 2))
        cancel.tap()
        XCTAssertTrue(row.exists)

        row.swipeLeft()
        XCTAssertTrue(delete.waitForExistence(timeout: 2))
        delete.tap()
        let confirm = app.alerts.buttons["reminder-list.delete-confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 2))
        confirm.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 2))
    }

    @MainActor
    func testLeadingSwipeToggleReflectsCurrentEnabledState() {
        let app = launch()
        let row = app.buttons["reminder-row.\(reminderID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        revealLeadingAction(on: row)

        let toggle = app.buttons["reminder-row.toggle-enabled.\(reminderID)"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        XCTAssertEqual(toggle.label, "Disable")
        toggle.tap()

        revealLeadingAction(on: row)
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        XCTAssertEqual(toggle.label, "Enable")
        toggle.tap()

        revealLeadingAction(on: row)
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        XCTAssertEqual(toggle.label, "Disable")
    }

    @MainActor
    func testLeadingFullSwipeTogglesWithoutAnotherTap() {
        let app = launch()
        let row = app.buttons["reminder-row.\(reminderID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        performLeadingFullSwipe(on: row)
        revealLeadingAction(on: row)

        let toggle = app.buttons["reminder-row.toggle-enabled.\(reminderID)"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        XCTAssertEqual(toggle.label, "Enable")
    }

    @MainActor
    func testEnablingFromSwipeUsesCapacityConfirmationAndSupportsCancel() {
        let app = launch(scenario: "enabled-capacity")
        let id = "ffffffff-ffff-ffff-ffff-ffffffffffff"
        let row = app.buttons["reminder-row.\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        performLeadingFullSwipe(on: row)

        let confirm = app.buttons["reminder-form.capacity-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 2))
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 2))

        revealLeadingAction(on: row)
        let toggle = app.buttons["reminder-row.toggle-enabled.\(id)"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        XCTAssertEqual(toggle.label, "Enable")
        toggle.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 2))
        confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 2))

        revealLeadingAction(on: row)
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        XCTAssertEqual(toggle.label, "Disable")
    }

    @MainActor
    func testUnsupportedScheduleCannotBeDuplicated() {
        let app = launch(scenario: "unsupported-schedule")
        let id = "cccccccc-cccc-cccc-cccc-cccccccccccc"
        let row = app.buttons["reminder-row.\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        row.swipeLeft()

        let edit = app.buttons["reminder-row.edit.\(id)"]
        XCTAssertTrue(edit.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["reminder-row.duplicate.\(id)"].exists)
        XCTAssertTrue(edit.isEnabled)
        XCTAssertTrue(app.buttons["reminder-row.delete.\(id)"].isEnabled)
    }

    @MainActor
    private func revealLeadingAction(on row: XCUIElement) {
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
        let end = row.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func performLeadingFullSwipe(on row: XCUIElement) {
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        let end = row.coordinate(withNormalizedOffset: CGVector(dx: 1.02, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func launch(scenario: String = "navigation") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "-ui-scenario", scenario,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_GB"
        ]
        app.launch()
        return app
    }
}
