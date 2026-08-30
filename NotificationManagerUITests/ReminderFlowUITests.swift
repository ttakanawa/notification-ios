import XCTest

final class ReminderFlowUITests: XCTestCase {
    @MainActor
    func testNewReminderStartsAtNextWholeHourAndOffersSelectableScheduleControls() throws {
        let app = launch(
            scenario: "empty-list",
            extraArguments: deterministicEnglish24HourArguments
        )
        app.buttons["reminder-list.add"].tap()

        let form = app.otherElements["reminder-form.root"]
        XCTAssertTrue(form.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["reminder-form.save"].isEnabled)

        let identifiers = [
            "reminder-form.section.basic-information",
            "reminder-form.section.date-time",
            "reminder-form.section.repeat"
        ]
        let frames = identifiers.map { identifier in
            let element = app.otherElements[identifier]
            XCTAssertTrue(element.waitForExistence(timeout: 1), identifier)
            return element.frame.minY
        }
        XCTAssertEqual(frames, frames.sorted())

        let dateRow = app.otherElements["reminder-form.date"]
        XCTAssertTrue(dateRow.waitForExistence(timeout: 1))
        XCTAssertEqual(dateRow.value as? String, "2040-07-04")
        XCTAssertTrue(app.buttons["Date Picker"].waitForExistence(timeout: 1))
        app.buttons["Date Picker"].tap()
        app.buttons["Thursday 5 July"].tap()
        app.buttons["PopoverDismissRegion"].tap()
        XCTAssertEqual(dateRow.value as? String, "2040-07-05")

        let timeRow = app.otherElements["reminder-form.time"]
        XCTAssertTrue(timeRow.waitForExistence(timeout: 1))
        XCTAssertEqual(timeRow.value as? String, "23:00")
        let time = app.buttons["Time Picker"]
        XCTAssertTrue(time.waitForExistence(timeout: 1))
        XCTAssertTrue(time.isEnabled)
        time.tap()
        let timeWheels = app.pickerWheels
        XCTAssertEqual(timeWheels.count, 2)
        timeWheels.element(boundBy: 0).adjust(toPickerWheelValue: "22")
        timeWheels.element(boundBy: 1).adjust(toPickerWheelValue: "30")
        app.buttons["PopoverDismissRegion"].tap()
        XCTAssertEqual(timeRow.value as? String, "22:30")

        let timeZone = app.buttons["reminder-form.time-zone"]
        XCTAssertTrue(timeZone.waitForExistence(timeout: 1))
        XCTAssertTrue(timeZone.label.contains("Africa/Abidjan"))
        timeZone.tap()

        let search = app.textFields["reminder-form.time-zone-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 1))
        search.tap()
        search.typeText("New York")

        let newYork = app.buttons["reminder-form.time-zone-option.America/New_York"]
        XCTAssertTrue(newYork.waitForExistence(timeout: 1))
        XCTAssertTrue(newYork.label.contains("New York, United States"))
        XCTAssertTrue(newYork.label.contains("Eastern Time ("))
        newYork.tap()
        XCTAssertTrue(timeZone.waitForExistence(timeout: 1))
        XCTAssertTrue(timeZone.label.contains("America/New_York"))
        XCTAssertFalse(app.buttons["reminder-form.save"].isEnabled)

        for identifier in [
            "reminder-form.section.early-reminder",
            "reminder-form.section.organization"
        ] {
            let section = app.otherElements[identifier]
            scrollToHittable(section, in: app)
            XCTAssertTrue(section.exists, identifier)
        }
    }

    @MainActor
    func testRepeatEndDateCanBeSelectedFromTheMissingValueSheet() {
        let app = launch(
            scenario: "empty-list",
            extraArguments: deterministicEnglish24HourArguments
        )
        app.buttons["reminder-list.add"].tap()

        let repeatPicker = app.buttons["reminder-form.repeat-picker"]
        scrollToHittable(repeatPicker, in: app)
        repeatPicker.tap()
        app.buttons["Daily"].tap()

        let repeatEndPicker = app.buttons["reminder-form.repeat-end-picker"]
        scrollToHittable(repeatEndPicker, in: app)
        repeatEndPicker.tap()
        app.buttons["On Date"].tap()

        let selectEndDate = app.buttons["reminder-form.repeat-end-date"]
        scrollToHittable(selectEndDate, in: app)
        XCTAssertTrue(selectEndDate.waitForExistence(timeout: 1))
        selectEndDate.tap()
        app.buttons["Done"].tap()

        let endDateRow = app.otherElements["reminder-form.repeat-end-date"]
        XCTAssertTrue(endDateRow.waitForExistence(timeout: 1))
        XCTAssertEqual(endDateRow.value as? String, "2040-07-04")
    }

    @MainActor
    func testNewExpiredReminderWarnsBeforeSavingWithoutNotification() {
        let app = launch(scenario: "new-expired-schedule")
        app.buttons["reminder-list.add"].tap()
        app.buttons["reminder-form.save"].tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 1))
        XCTAssertTrue(
            alert.buttons["reminder-form.expired-confirm"].firstMatch
                .waitForExistence(timeout: 1)
        )
        alert.buttons["reminder-form.expired-confirm"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["reminder-list.root"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testRegisteredReminderInvalidInputKeepsConditionalSaveVisibleAndDisabled() {
        let app = launch(scenario: "navigation")
        app.buttons["reminder-row.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"].tap()

        let url = app.textFields["reminder-form.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 2))
        url.tap()
        url.typeText("not-a-url")

        let save = app.buttons["reminder-form.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 1))
        XCTAssertFalse(save.isEnabled)
    }

    @MainActor
    func testRegisteredReminderShowsSaveOnlyForRealChanges() {
        let app = launch(scenario: "navigation")
        app.buttons["reminder-row.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"].tap()

        let save = app.buttons["reminder-form.save"]
        let title = app.textFields["reminder-form.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        XCTAssertFalse(save.exists)

        replaceText(in: title, with: "Changed")
        XCTAssertTrue(save.waitForExistence(timeout: 1))
        XCTAssertTrue(save.isEnabled)

        replaceText(in: title, with: "Visa renewal")
        XCTAssertTrue(save.waitForNonExistence(timeout: 1))
    }

    @MainActor
    func testRegisteredReminderBackCancelsThenDiscardsChanges() {
        let app = launch(scenario: "navigation")
        let row = app.buttons["reminder-row.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"]
        row.tap()

        let title = app.textFields["reminder-form.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        replaceText(in: title, with: "Changed")

        app.buttons["reminder-form.back"].tap()
        var alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 1))
        alert.buttons["reminder-form.discard-cancel"].firstMatch.tap()
        XCTAssertEqual(title.value as? String, "Changed")

        app.buttons["reminder-form.back"].tap()
        alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 1))
        alert.buttons["reminder-form.discard-confirm"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["reminder-list.root"].waitForExistence(timeout: 1))

        row.tap()
        let reopenedTitle = app.textFields["reminder-form.title"]
        XCTAssertTrue(reopenedTitle.waitForExistence(timeout: 1))
        XCTAssertEqual(reopenedTitle.value as? String, "Visa renewal")
    }

    @MainActor
    func testRegisteredReminderSaveReturnsToList() {
        let app = launch(scenario: "navigation")
        app.buttons["reminder-row.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"].tap()

        let title = app.textFields["reminder-form.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        replaceText(in: title, with: "Changed")
        app.buttons["reminder-form.save"].tap()

        XCTAssertTrue(app.otherElements["reminder-list.root"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testRegisteredReminderOmitsAutomaticNextNotificationPreview() {
        let app = launch(scenario: "navigation")
        app.buttons["reminder-row.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"].tap()

        let preview = app.otherElements["reminder-form.preview"]
        scrollToHittable(preview, in: app)
        XCTAssertFalse(preview.exists)
    }

    @MainActor
    func testRegisteredReminderDeleteSectionFollowsEveryInputSection() {
        let app = launch(scenario: "navigation-with-tags")
        app.buttons["reminder-row.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"].tap()

        assertDeleteSectionFollowsInputSections(
            [],
            additionalInputs: [app.textFields["tags.picker.new-name"]],
            in: app
        )
    }

    @MainActor
    func testTagPickerOffersInlineCaseSensitiveCreationSuggestion() {
        let app = launch(scenario: "navigation-with-tags")
        app.buttons["reminder-row.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"].tap()

        let input = app.textFields["tags.picker.new-name"]
        scrollToHittable(input, in: app)
        let emptyInputValue = input.value as? String ?? ""
        XCTAssertFalse(app.buttons["tags.picker.create"].exists)

        input.tap()
        input.typeText("work")
        let workID = "88888888-8888-8888-8888-888888888888"
        let existingWork = app.buttons["tags.picker.tag.\(workID)"]
        XCTAssertTrue(existingWork.waitForExistence(timeout: 1))
        let createSuggestion = app.buttons["tags.picker.create-suggestion"]
        XCTAssertTrue(createSuggestion.waitForExistence(timeout: 1))

        createSuggestion.tap()
        let queryCleared = NSPredicate(format: "value == %@", emptyInputValue)
        expectation(for: queryCleared, evaluatedWith: input)
        waitForExpectations(timeout: 2)

        input.tap()
        input.typeText("work")
        XCTAssertTrue(createSuggestion.waitForNonExistence(timeout: 1))
        XCTAssertTrue(existingWork.waitForExistence(timeout: 1))
        let createdWork = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "tags.picker.tag.")
        ).matching(NSPredicate(format: "label == %@", "Remove work")).firstMatch
        XCTAssertTrue(
            createdWork.waitForExistence(timeout: 1)
        )
    }

    @MainActor
    func testTagPickerUsesExplicitAddAndRemoveActions() {
        let app = launch(scenario: "navigation-with-tags")
        app.buttons["reminder-row.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"].tap()

        let input = app.textFields["tags.picker.new-name"]
        scrollToHittable(input, in: app)
        let workID = "88888888-8888-8888-8888-888888888888"
        let work = app.buttons["tags.picker.tag.\(workID)"]
        XCTAssertTrue(work.waitForExistence(timeout: 1))
        XCTAssertEqual(work.label, "Add Work")
        XCTAssertFalse(app.switches["tags.picker.tag.\(workID)"].exists)

        work.tap()
        let removeWork = app.buttons.matching(
            identifier: "tags.picker.tag.\(workID)"
        ).matching(NSPredicate(format: "label == %@", "Remove Work")).firstMatch
        XCTAssertTrue(removeWork.waitForExistence(timeout: 1))

        removeWork.tap()
        XCTAssertTrue(work.waitForNonExistence(timeout: 1))
    }

    @MainActor
    func testTagRemovalImmediatelyDisablesRegisteredFormActions() {
        let app = launch(scenario: "slow-tag-removal")
        app.buttons["reminder-row.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"].tap()

        let delete = app.buttons["reminder-form.delete"]
        scrollToHittable(delete, in: app)
        XCTAssertTrue(delete.exists)

        let input = app.textFields["tags.picker.new-name"]
        scrollToHittable(input, in: app)
        let workID = "88888888-8888-8888-8888-888888888888"
        let work = app.buttons["tags.picker.tag.\(workID)"]
        XCTAssertTrue(work.waitForExistence(timeout: 1))
        work.tap()

        let removeWork = app.buttons.matching(
            identifier: "tags.picker.tag.\(workID)"
        ).matching(NSPredicate(format: "label == %@", "Remove Work")).firstMatch
        XCTAssertTrue(removeWork.waitForExistence(timeout: 1))
        let back = app.buttons["reminder-form.back"]
        let save = app.buttons["reminder-form.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 1))

        removeWork.tap()

        XCTAssertFalse(back.isEnabled)
        XCTAssertFalse(save.isEnabled)
        XCTAssertFalse(delete.isEnabled)
        XCTAssertTrue(work.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testPersistenceStartImmediatelyDisablesRegisteredFormActions() {
        let app = launch(scenario: "slow-persistence")
        app.buttons["reminder-row.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"].tap()

        let title = app.textFields["reminder-form.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        replaceText(in: title, with: "Changed")
        app.keyboards.buttons["Return"].tap()

        let delete = app.buttons["reminder-form.delete"]
        scrollToHittable(delete, in: app)
        XCTAssertTrue(delete.exists)
        let back = app.buttons["reminder-form.back"]
        let save = app.buttons["reminder-form.save"]
        save.tap()

        XCTAssertFalse(back.isEnabled)
        XCTAssertFalse(save.isEnabled)
        XCTAssertFalse(delete.isEnabled)
        XCTAssertTrue(app.otherElements["reminder-list.root"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testConfirmedDeleteKeepsBackDisabledUntilPersistenceCompletes() {
        let app = launch(scenario: "slow-persistence")
        app.buttons["reminder-row.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"].tap()

        let delete = app.buttons["reminder-form.delete"]
        scrollToHittable(delete, in: app)
        delete.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 1))
        let confirm = alert.buttons["reminder-form.delete-confirm"].firstMatch
        confirm.tap()

        XCTAssertTrue(alert.waitForNonExistence(timeout: 1))
        XCTAssertFalse(app.buttons["reminder-form.back"].isEnabled)
        XCTAssertTrue(app.otherElements["reminder-list.root"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLocalizedCustomRuleStaysSummaryUntilExplicitEmptyReplacement() {
        let app = launch(scenario: "localized-custom-rule")
        app.buttons["reminder-row.bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"].tap()

        XCTAssertTrue(app.otherElements["reminder-form.custom.current-summary"].exists)
        XCTAssertFalse(app.textFields["reminder-form.custom.input"].exists)
        XCTAssertFalse(app.buttons["reminder-form.save"].exists)

        app.buttons["reminder-form.custom.replace"].tap()

        let input = app.textFields["reminder-form.custom.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 1))
        input.tap()
        input.typeText("every 3 ")
        XCTAssertEqual(input.value as? String, "every 3 ")
        XCTAssertFalse(app.buttons["reminder-form.save"].isEnabled)
    }

    @MainActor
    func testCustomRepeatAlwaysShowsAppleIntelligenceStatus() {
        let app = launch(
            scenario: "localized-custom-rule",
            extraArguments: deterministicEnglish24HourArguments
        )
        app.buttons["reminder-row.bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"].tap()
        app.buttons["reminder-form.custom.replace"].tap()

        let icon = app.images["reminder-form.custom.apple-intelligence-icon"]
        let status = app.staticTexts["reminder-form.custom.apple-intelligence-status"]

        XCTAssertTrue(icon.waitForExistence(timeout: 2))
        XCTAssertTrue(status.waitForExistence(timeout: 2))
        XCTAssertEqual(status.label, "Apple Intelligence is unavailable on this system.")
    }

    @MainActor
    func testEnglishSuggestionsOfferCandidatesAndExplicitAssistanceBeforeSelection() {
        let app = launch(scenario: "localized-custom-rule")
        app.buttons["reminder-row.bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"].tap()
        app.buttons["reminder-form.custom.replace"].tap()

        let input = app.textFields["reminder-form.custom.input"]
        input.tap()
        input.typeText("Every mont")
        app.buttons["reminder-form.custom.preview-button"].tap()

        let monday = app.buttons["reminder-form.custom.suggestion-0"]
        let month = app.buttons["reminder-form.custom.suggestion-1"]
        let assisted = app.buttons["reminder-form.custom.assisted"]
        XCTAssertTrue(monday.waitForExistence(timeout: 1))
        XCTAssertTrue(month.exists)
        XCTAssertTrue(assisted.exists)
        XCTAssertEqual(monday.label, "Every Monday")
        XCTAssertEqual(month.label, "Every month")
        XCTAssertEqual(input.value as? String, "Every mont")
        XCTAssertFalse(app.buttons["reminder-form.save"].isEnabled)

        monday.tap()

        let preview = app.descendants(matching: .any)
            .matching(identifier: "reminder-form.custom.preview-result")
            .firstMatch
        let apply = app.buttons["reminder-form.custom.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 3))
        scrollToHittable(preview, in: app)
        XCTAssertTrue(
            preview.waitForExistence(timeout: 1)
        )
        XCTAssertEqual(input.value as? String, "Every Monday")
        XCTAssertFalse(app.buttons["reminder-form.save"].isEnabled)

        scrollToHittable(apply, in: app)
        apply.tap()
        XCTAssertTrue(app.buttons["reminder-form.save"].isEnabled)
    }

    @MainActor
    func testCustomRepeatPreviewShowsOnlyTheCanonicalSentence() {
        let app = launch(scenario: "localized-custom-rule")
        app.buttons["reminder-row.bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"].tap()
        app.buttons["reminder-form.custom.replace"].tap()

        let input = app.textFields["reminder-form.custom.input"]
        input.tap()
        input.typeText("Every month on the first fri")
        app.buttons["reminder-form.custom.preview-button"].tap()

        let preview = app.descendants(matching: .any)
            .matching(identifier: "reminder-form.custom.preview-result")
            .firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        XCTAssertEqual(preview.label, "Every month on the 1st Friday")
        XCTAssertFalse(app.staticTexts["reminder-form.preview.primary-reason"].exists)
    }

    @MainActor
    func testOpaqueScheduleKeepsMetadataEditableAndScheduleReadOnly() {
        let app = launch(
            scenario: "unsupported-schedule",
            extraArguments: deterministicEnglish24HourArguments
        )
        app.buttons["reminder-row.cccccccc-cccc-cccc-cccc-cccccccccccc"].tap()

        XCTAssertTrue(app.textFields["reminder-form.title"].isEnabled)
        XCTAssertTrue(app.switches["reminder-form.enabled"].isEnabled)
        XCTAssertTrue(app.otherElements["reminder-form.schedule-read-only"].exists)
        for identifier in [
            "reminder-form.date",
            "reminder-form.time",
            "reminder-form.time-zone"
        ] {
            let row = app.descendants(matching: .any)
                .matching(identifier: identifier)
                .firstMatch
            scrollToHittable(row, in: app)
            XCTAssertTrue(row.waitForExistence(timeout: 1), identifier)
            XCTAssertFalse(app.datePickers[identifier].exists, identifier)
            XCTAssertFalse(app.buttons[identifier].exists, identifier)
            XCTAssertEqual(app.datePickers.count, 0, identifier)
            if let nativePickerLabel = [
                "reminder-form.date": "Date Picker",
                "reminder-form.time": "Time Picker"
            ][identifier] {
                XCTAssertFalse(
                    app.buttons[nativePickerLabel].exists,
                    "Read-only schedules must not expose an enabled native \(nativePickerLabel)"
                )
            }
        }
        assertDeleteSectionFollowsInputSections(
            ["reminder-form.section.early-reminder"],
            in: app
        )
        XCTAssertTrue(app.buttons["reminder-form.delete"].isEnabled)

        app.buttons["reminder-form.delete"].tap()
        var alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 1))
        XCTAssertTrue(
            alert.buttons["reminder-form.delete-confirm"].firstMatch
                .waitForExistence(timeout: 1)
        )
        alert.buttons["reminder-form.delete-cancel"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["reminder-form.root"].exists)

        app.buttons["reminder-form.delete"].tap()
        alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 1))
        let confirm = alert.buttons["reminder-form.delete-confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 1))
        confirm.tap()
        XCTAssertTrue(app.otherElements["reminder-list.root"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testCapacityThenExpiredConsentKeepsFormValuesUntilSaveCompletes() {
        let app = launch(scenario: "capacity-and-expired-confirmations")
        app.buttons["reminder-row.dddddddd-dddd-dddd-dddd-dddddddddddd"].tap()
        let title = app.textFields["reminder-form.title"]
        title.tap()
        title.typeText(" updated")

        app.buttons["reminder-form.save"].tap()
        XCTAssertTrue(
            app.otherElements["reminder-form.capacity-confirmation"].waitForExistence(timeout: 1)
        )
        let confirmationMessage = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "60")
        ).firstMatch
        XCTAssertTrue(confirmationMessage.waitForExistence(timeout: 1))
        XCTAssertFalse(
            confirmationMessage.label.contains(
                "reminder.form.capacity-confirmation.message"
            ))
        XCTAssertTrue(confirmationMessage.label.contains("60"))
        app.buttons["reminder-form.capacity-confirm"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 1))
        XCTAssertTrue(
            alert.buttons["reminder-form.expired-confirm"].firstMatch
                .waitForExistence(timeout: 1)
        )
        XCTAssertTrue(title.value as? String == "Capacity edit updated")
        alert.buttons["reminder-form.expired-confirm"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["reminder-list.root"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testEarlyReminderExposesThirtySecondPresetAndCustomWheel() {
        let app = launch(scenario: "empty-list")
        app.buttons["reminder-list.add"].tap()

        let picker = app.buttons["reminder-form.early-choice"]
        scrollToHittable(picker, in: app)
        XCTAssertTrue(picker.waitForExistence(timeout: 1))
        picker.tap()
        XCTAssertTrue(app.buttons["reminder.early.thirty-seconds-before"].exists)
        XCTAssertTrue(app.buttons["reminder.early.one-minute-before"].exists)
        XCTAssertTrue(app.buttons["reminder.early.five-minutes-before"].exists)
        app.buttons["reminder.early.custom"].tap()

        let amountPicker = app.pickers["reminder-form.early-value"]
        XCTAssertTrue(amountPicker.waitForExistence(timeout: 1))
        let wheel = amountPicker.pickerWheels.element
        wheel.adjust(toPickerWheelValue: "6")
        XCTAssertEqual(wheel.value as? String, "6")

        let unitPicker = app.buttons["reminder-form.early-unit"]
        unitPicker.tap()
        XCTAssertTrue(app.buttons["reminder.early-unit.seconds"].exists)
        XCTAssertTrue(app.switches["reminder-form.main-enabled"].exists)
    }

    @MainActor
    private func replaceText(in field: XCUIElement, with value: String) {
        field.tap()
        let currentValue = field.value as? String ?? ""
        field.typeText(
            String(
                repeating: XCUIKeyboardKey.delete.rawValue,
                count: currentValue.count
            ))
        field.typeText(value)
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

    @MainActor
    private func assertDeleteSectionFollowsInputSections(
        _ identifiers: [String],
        additionalInputs: [XCUIElement] = [],
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let delete = app.buttons["reminder-form.delete"]
        scrollToHittable(delete, in: app)
        XCTAssertTrue(delete.exists, file: file, line: line)
        let deleteSection = app.otherElements["reminder-form.section.delete"]
        XCTAssertTrue(deleteSection.exists, file: file, line: line)
        for identifier in identifiers {
            let section = app.otherElements[identifier]
            XCTAssertTrue(section.exists, identifier, file: file, line: line)
            XCTAssertLessThan(
                section.frame.minY,
                deleteSection.frame.minY,
                identifier,
                file: file,
                line: line
            )
        }
        for input in additionalInputs {
            XCTAssertTrue(input.exists, input.identifier, file: file, line: line)
            XCTAssertLessThan(
                input.frame.maxY,
                delete.frame.minY,
                input.identifier,
                file: file,
                line: line
            )
        }
    }

    @MainActor
    private var deterministicEnglish24HourArguments: [String] {
        ["-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]
    }

    @MainActor
    private func launch(
        scenario: String,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments +=
            ["-ui-testing", "-ui-scenario", scenario]
            + extraArguments
        app.launch()
        return app
    }
}
