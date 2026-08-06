import UIKit
import XCTest

final class NavigationUITests: XCTestCase {
    @MainActor
    func testCompactLayoutUsesStackAndOpensDetail() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("iPhone journey") }
        let app = launch()

        XCTAssertTrue(app.otherElements["adaptive-root.compact-stack"].waitForExistence(timeout: 2))
        app.buttons["reminder-row.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"].tap()
        XCTAssertTrue(app.otherElements["reminder-detail.root"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.exists)
    }

    @MainActor
    func testEnabledAndDeleteControlsAreReachable() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("iPhone journey") }
        let app = launch()
        let id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

        let enabled = app.switches["reminder-row.enabled.\(id)"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 2))
        XCTAssertTrue(enabled.isEnabled)

        app.buttons["reminder-row.\(id)"].tap()
        XCTAssertTrue(app.switches["reminder-detail.enabled"].waitForExistence(timeout: 1))
        app.buttons["reminder-detail.delete"].tap()

        XCTAssertTrue(app.buttons["reminder-detail.delete-confirm"].waitForExistence(timeout: 1))
        app.buttons["reminder-detail.delete-confirm"].tap()
        XCTAssertTrue(app.otherElements["reminder-list.root"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.otherElements["reminder-detail.root"].exists)
    }

    @MainActor
    func testRegularLayoutUsesSplitViewAndPreservesSelectionAcrossRotation() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad journey") }
        let app = launch()

        XCTAssertTrue(app.otherElements["adaptive-root.regular-split"].waitForExistence(timeout: 2))
        app.buttons["reminder-row.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"].tap()
        XCTAssertTrue(app.otherElements["reminder-detail.root"].waitForExistence(timeout: 1))

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.otherElements["reminder-detail.root"].waitForExistence(timeout: 2))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(
            app.buttons["reminder-row.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"].isSelected
        )
    }

    @MainActor
    func testRegularDeleteClearsDetailAndSelection() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad journey") }
        let app = launch()
        let row = app.buttons["reminder-row.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"]

        XCTAssertTrue(app.otherElements["adaptive-root.regular-split"].waitForExistence(timeout: 2))
        row.tap()
        app.buttons["reminder-detail.delete"].tap()
        let confirm = app.buttons["reminder-detail.delete-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 1))
        confirm.tap()

        XCTAssertTrue(app.otherElements["adaptive-root.empty-detail"].waitForExistence(timeout: 1))
        XCTAssertFalse(row.isSelected)
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-scenario", "navigation"]
        app.launch()
        return app
    }
}
