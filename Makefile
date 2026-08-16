.DEFAULT_GOAL := help

PROJECT := NotificationManager.xcodeproj
SCHEME := NotificationManager
SIMULATOR_NAME ?= iPhone 17e
SIMULATOR_OS ?= latest
SIMULATOR_DESTINATION := platform=iOS Simulator,name=$(SIMULATOR_NAME),OS=$(SIMULATOR_OS)

SWIFT_PATHS := \
	NotificationManager \
	NotificationManagerTests \
	NotificationManagerIntegrationTests \
	NotificationManagerUITests \
	Packages/NotificationManagerCore/Sources \
	Packages/NotificationManagerCore/Tests \
	Scripts/validate-localizations.swift

LOCALIZATION_CATALOGS := \
	NotificationManager/Resources/Common.xcstrings \
	NotificationManager/Resources/ReminderForm.xcstrings \
	NotificationManager/Resources/Reminder.xcstrings \
	NotificationManager/Resources/NotificationText.xcstrings \
	NotificationManager/Resources/Settings.xcstrings \
	NotificationManager/Resources/Tags.xcstrings \
	NotificationManager/Resources/Recovery.xcstrings

.PHONY: help format lint test-unit test-integration test-ui build-release \
	validate-localizations test-localization-validator validate-testflight

help:
	@echo "make format                       Format maintained Swift sources"
	@echo "make lint                         Verify Swift format and SwiftLint"
	@echo "make test-unit                    Run package and Xcode unit tests"
	@echo "make test-integration             Run Xcode integration tests"
	@echo "make test-ui                      Run Xcode UI tests"
	@echo "make build-release                Build Release for iOS Simulator"
	@echo "make validate-localizations       Validate string catalogs and source coverage"
	@echo "make test-localization-validator  Test localization validator fixtures"
	@echo "make validate-testflight          Validate TestFlight configuration"

format:
	swift format --configuration .swift-format --in-place --recursive $(SWIFT_PATHS)

lint:
	swift format lint --configuration .swift-format --recursive --strict $(SWIFT_PATHS)
	swiftlint lint --strict --no-cache $(SWIFT_PATHS)

test-unit:
	swift test --package-path Packages/NotificationManagerCore
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(SIMULATOR_DESTINATION)' \
		-only-testing:NotificationManagerTests

test-integration:
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(SIMULATOR_DESTINATION)' \
		-only-testing:NotificationManagerIntegrationTests

test-ui:
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(SIMULATOR_DESTINATION)' \
		-only-testing:NotificationManagerUITests

build-release:
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
		-configuration Release \
		-destination 'generic/platform=iOS Simulator' \
		CODE_SIGNING_ALLOWED=NO

validate-localizations:
	swift Scripts/validate-localizations.swift $(LOCALIZATION_CATALOGS) --source-root .

test-localization-validator:
	sh Scripts/Tests/validate-localization-source-coverage.sh

validate-testflight:
	sh Scripts/validate-testflight-configuration.sh
