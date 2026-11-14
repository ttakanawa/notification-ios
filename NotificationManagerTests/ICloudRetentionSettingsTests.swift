import Foundation
import NotificationManagerDomain
import NotificationManagerPersistence
import Testing

@testable import NotificationManager

@Suite struct ICloudRetentionSettingsTests {
    @MainActor
    @Test func refusalTurnsSwitchOffAndStaysOffAfterResumeAndRelaunch() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "icloud-settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let repository = try RetainedReminderRepository(url: url)
        #expect(try await repository.checkAccount("old-account"))
        try await repository.saveGlobalDisplayCustomizationData(Data("{}".utf8))
        #expect(try await !repository.checkAccount("new-account"))
        let model = ICloudSyncStatusModel(repository: repository, accountStatus: { .available })
        await model.refreshAccountAvailability()
        #expect(model.retainedPhase == .confirmationRequired)
        await model.confirmAccount(false)
        #expect(!model.isSyncEnabled)
        await model.refreshAccountAvailability()
        #expect(model.retainedPhase == .off)
        let relaunched = try RetainedReminderRepository(url: url)
        let reopened = ICloudSyncStatusModel(repository: relaunched, accountStatus: { .available })
        await reopened.refreshAccountAvailability()
        #expect(!reopened.isSyncEnabled)
        #expect(reopened.retainedPhase == .off)
    }

    @MainActor
    @Test func switchIsDeviceLocalAndUnknownAccountNeverCreatesConsent() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "icloud-settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let repository = try RetainedReminderRepository(url: url)
        let model = ICloudSyncStatusModel(
            repository: repository, accountStatus: { .couldNotDetermine })
        await model.setSyncEnabled(false)
        #expect(!model.isSyncEnabled)
        try await repository.saveGlobalDisplayCustomizationData(Data([255, 0, 1]))
        await model.setSyncEnabled(true)
        _ = try await repository.checkAccount(nil)
        await model.refreshAccountAvailability()
        #expect(model.isSyncEnabled)
        #expect(model.retainedPhase == .unavailable)
        #expect(await repository.globalDisplayCustomizationData() == Data([255, 0, 1]))
        model.receive(
            ICloudSyncEvent(identifier: UUID(), kind: .export, endDate: Date(), succeeded: true))
        #expect(model.syncActivity == .notObserved)
    }
}
