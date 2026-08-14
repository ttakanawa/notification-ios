import UIKit
import XCTest

final class NavigationUITests: XCTestCase {
    @MainActor
    func testCompactLayoutUsesStackAndOpensRegisteredForm() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("iPhone journey") }
        let app = launch()

        XCTAssertTrue(app.otherElements["adaptive-root.compact-stack"].waitForExistence(timeout: 2))
        app.buttons["reminder-row.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"].tap()
        XCTAssertTrue(app.otherElements["reminder-form.root"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["reminder-form.back"].exists)
    }

    @MainActor
    func testHomeRowOmitsEnabledToggleAndRegisteredFormControlsRemainReachable() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("iPhone journey") }
        let app = launch()
        let id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

        XCTAssertTrue(app.buttons["reminder-row.\(id)"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.switches["reminder-row.enabled.\(id)"].exists)

        app.buttons["reminder-row.\(id)"].tap()
        let enabled = app.switches["reminder-form.enabled"]
        scrollToHittable(enabled, in: app)
        XCTAssertTrue(enabled.waitForExistence(timeout: 1))
        let delete = app.buttons["reminder-form.delete"]
        scrollToHittable(delete, in: app)
        delete.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 1))
        let confirm = alert.buttons["reminder-form.delete-confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 1))
        confirm.tap()
        XCTAssertTrue(app.otherElements["reminder-list.root"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.otherElements["reminder-form.root"].exists)
    }

    @MainActor
    func testRegularLayoutPreservesRegisteredFormSelectionAcrossRotation() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad journey") }
        let app = launch()

        XCTAssertTrue(app.otherElements["adaptive-root.regular-split"].waitForExistence(timeout: 2))
        app.buttons["reminder-row.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"].tap()
        XCTAssertTrue(app.otherElements["reminder-form.root"].waitForExistence(timeout: 1))

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.otherElements["reminder-form.root"].waitForExistence(timeout: 2))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(
            app.buttons["reminder-row.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"].isSelected
        )
    }

    @MainActor
    func testRegularDeleteClearsRegisteredFormAndSelection() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad journey") }
        let app = launch()
        let row = app.buttons["reminder-row.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"]

        XCTAssertTrue(app.otherElements["adaptive-root.regular-split"].waitForExistence(timeout: 2))
        row.tap()
        let delete = app.buttons["reminder-form.delete"]
        scrollToHittable(delete, in: app)
        delete.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 1))
        let confirm = alert.buttons["reminder-form.delete-confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 1))
        confirm.tap()

        let emptyDetail = app.descendants(matching: .any)
            .matching(identifier: "adaptive-root.empty-detail")
            .firstMatch
        XCTAssertTrue(emptyDetail.waitForExistence(timeout: 1))
        XCTAssertFalse(row.isSelected)
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-scenario", "navigation"]
        app.launch()
        return app
    }

    @MainActor
    private func scrollToHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        attempts: Int = 8
    ) {
        var remaining = attempts
        while !element.isHittable, remaining > 0 {
            app.swipeUp()
            remaining -= 1
        }
    }
}
