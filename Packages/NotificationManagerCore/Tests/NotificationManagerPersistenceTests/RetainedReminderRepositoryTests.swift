import CloudKit
import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import SwiftData
import Testing

@testable import NotificationManagerPersistence

@Suite struct RetainedReminderRepositoryTests {
    private let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
    private let accountA = "container/development/account-a"
    private let accountB = "container/development/account-b"

    @Test func unknownOriginRequiresConsentAndRefusalPersistsAcrossLaunch() async throws {
        let fixture = try fixture()
        defer { fixture.clean() }
        let saved = try await fixture.repository.save(mutation())
        #expect(try await !fixture.repository.checkAccount(accountA))
        #expect(await fixture.repository.status().phase == .confirmationRequired)
        #expect(await !fixture.repository.canPublish(saved))
        #expect(await fixture.repository.pendingRevisions(account: accountA).isEmpty)
        try await fixture.repository.confirmAccount(false)
        let reopened = try RetainedReminderRepository(url: fixture.url)
        #expect(await !reopened.status().isEnabled)
        #expect(try await !reopened.checkAccount(accountA))
        #expect(await reopened.canPublish(saved))
        #expect(try await reopened.reminder(id: saved.id) == saved)
    }

    @Test func offlineIdentityDoesNotImplySwitchOrGrantUploadConsent() async throws {
        let fixture = try fixture()
        defer { fixture.clean() }
        #expect(try await fixture.repository.checkAccount(accountA))
        let saved = try await fixture.repository.save(mutation())
        #expect(try await !fixture.repository.checkAccount(nil))
        #expect(await fixture.repository.status().phase == .unavailable)
        #expect(await !fixture.repository.canPublish(saved))
        #expect(try await fixture.repository.checkAccount(accountA))
        #expect(try await !fixture.repository.checkAccount(accountB))
        #expect(await fixture.repository.status().phase == .confirmationRequired)
    }

    @Test func exactCommitCannotAcknowledgeNewEditWithSameTimestamp() async throws {
        let fixture = try fixture()
        defer { fixture.clean() }
        #expect(try await fixture.repository.checkAccount(accountA))
        let initial = try await fixture.repository.save(mutation())
        let first = try #require(await fixture.repository.pendingRevisions(account: accountA).first)
        let edited = try await fixture.repository.save(
            mutation(
                id: initial.id, title: "Edited", command: .updateMetadataPreservingCurrentSchedule))
        try await fixture.repository.acknowledge(first, account: accountA)
        #expect(await !fixture.repository.canPublish(initial))
        #expect(await !fixture.repository.canPublish(edited))
        let pending = await fixture.repository.pendingRevisions(account: accountA)
        for revision in pending {
            try await fixture.repository.acknowledge(revision, account: accountA)
        }
        #expect(await fixture.repository.canPublish(edited))
        let reopened = try RetainedReminderRepository(url: fixture.url)
        #expect(await !reopened.canPublish(edited))
        #expect(try await reopened.checkAccount(accountA))
        #expect(await reopened.canPublish(edited))
    }

    @Test func signedOutAndSystemDisabledKeepDurableValuesAndGateLocally() async throws {
        let fixture = try fixture()
        defer { fixture.clean() }
        #expect(try await fixture.repository.checkAccount(accountA))
        let saved = try await fixture.repository.save(mutation())
        #expect(try await !fixture.repository.checkAccount(nil, systemUnavailable: true))
        #expect(await fixture.repository.canPublish(saved))
        #expect(try await fixture.repository.reminder(id: saved.id) == saved)
        try await fixture.repository.setSyncEnabled(false)
        let reopened = try RetainedReminderRepository(url: fixture.url)
        #expect(try await reopened.reminder(id: saved.id) == saved)
        #expect(await reopened.canPublish(saved))
        try await reopened.setSyncEnabled(true)
        #expect(try await reopened.checkAccount(accountA))
        #expect(await !reopened.canPublish(saved))
    }

    @Test func newAccountNeverReusesOldReceipts() async throws {
        let fixture = try fixture()
        defer { fixture.clean() }
        #expect(try await fixture.repository.checkAccount(accountA))
        let saved = try await fixture.repository.save(mutation())
        let revision = try #require(
            await fixture.repository.pendingRevisions(account: accountA).first)
        try await fixture.repository.acknowledge(revision, account: accountA)
        #expect(try await !fixture.repository.checkAccount(accountB))
        #expect(await fixture.repository.pendingRevisions(account: accountB).isEmpty)
        try await fixture.repository.confirmAccount(true)
        #expect(await !fixture.repository.canPublish(saved))
        await #expect(throws: RetainedStoreError.staleAccount) {
            try await fixture.repository.acknowledge(revision, account: accountA)
        }
        try await fixture.repository.acknowledge(revision, account: accountB)
        #expect(await fixture.repository.canPublish(saved))
    }

    @Test func importedCloudDataIsCommittedAndPreservesRawFutureSchedule() async throws {
        let fixture = try fixture()
        defer { fixture.clean() }
        #expect(try await fixture.repository.checkAccount(accountA))
        let raw = Data(
            #"{ "format":"notification-manager.schedule", "version":999, "future":[1,2,3] }"#.utf8)
        let value = opaqueValue(schedule: raw)
        let revision = RetainedCloudRevision(
            entityKey: "reminder/\(value.id.uuidString)", payload: try RetainedCoding.encode(value))
        try await fixture.repository.importRevision(revision, account: accountA)
        let snapshot = try #require(await fixture.repository.reminder(id: value.id))
        #expect(await fixture.repository.canPublish(snapshot))
        #expect(RetainedReminderValue(snapshot).scheduleData == raw)
        #expect(snapshot.schedule == .unsupportedFuture(version: 999, originalData: raw))
        let edited = try await fixture.repository.save(
            mutation(
                id: value.id, title: "Metadata edit",
                command: .updateMetadataPreservingCurrentSchedule))
        #expect(RetainedReminderValue(edited).scheduleData == raw)
        #expect(await !fixture.repository.canPublish(edited))
    }

    @Test func conflictsKeepBothValuesWithoutConsultingWallClock() async throws {
        let fixture = try fixture()
        defer { fixture.clean() }
        #expect(try await fixture.repository.checkAccount(accountA))
        let local = try await fixture.repository.save(mutation(title: "Unsynced local"))
        var remote = RetainedReminderValue(local)
        remote.title = "Remote"
        remote.updatedAt = .distantPast
        let revision = RetainedCloudRevision(
            entityKey: "reminder/\(local.id.uuidString)", payload: try RetainedCoding.encode(remote)
        )
        try await fixture.repository.importRevision(revision, account: accountA)
        let selected = try #require(await fixture.repository.reminder(id: local.id))
        let copies = await fixture.repository.recoveryRevisions()
        let copy = try #require(copies.first)
        let other = try JSONDecoder().decode(
            RetainedReminderValue.self, from: #require(copy.payload))
        #expect(Set([selected.title, other.title]) == ["Remote", "Unsynced local"])
        try await fixture.repository.restoreRevision(copy.id)
        #expect(try await fixture.repository.reminder(id: local.id)?.title == other.title)
        #expect(await fixture.repository.recoveryRevisions().isEmpty == false)
    }

    @Test func globalAndIndividualFutureCustomizationSurviveMetadataEditsAndRestart() async throws {
        let fixture = try fixture()
        defer { fixture.clean() }
        try await fixture.repository.setSyncEnabled(false)
        let saved = try await fixture.repository.save(mutation())
        let future = Data(#"{ "schemaVersion":700, "unknown":{"keep":true} }"#.utf8)
        try await fixture.repository.saveGlobalDisplayCustomizationData(future)
        _ = try await fixture.repository.saveDisplayCustomizationData(future, reminderID: saved.id)
        let edited = try await fixture.repository.save(
            mutation(
                id: saved.id, title: "New title", command: .updateMetadataPreservingCurrentSchedule)
        )
        #expect(edited.displayCustomization == nil)
        #expect(edited.displayCustomizationData == future)
        let reopened = try RetainedReminderRepository(url: fixture.url)
        #expect(await reopened.globalDisplayCustomizationData() == future)
        #expect(try await reopened.reminder(id: saved.id)?.displayCustomizationData == future)
        #expect(await reopened.canPublish(edited))
    }

    @Test @MainActor func migrationPreservesUUIDRelationshipsCorruptBytesAndOriginalStore()
        async throws
    {
        let container = try ModelContainerFactory.inMemory()
        let context = ModelContext(container)
        let tag = TagRecordV1(
            id: UUID(), name: "Tag", normalizedName: "tag",
            normalizationVersion: TagLimits.normalizationVersion, createdAt: timestamp,
            updatedAt: timestamp)
        context.insert(tag)
        let raw = Data([0, 255, 2, 254])
        let record = ReminderRecordV1(
            id: UUID(), title: "Legacy", notes: nil, urlString: nil, enabled: true,
            scheduleData: raw, createdAt: timestamp, updatedAt: timestamp, tags: [tag])
        context.insert(record)
        try context.save()
        let fixture = try fixture(legacy: RetainedLegacySnapshot(container: container))
        defer { fixture.clean() }
        let snapshot = try #require(await fixture.repository.reminder(id: record.id))
        #expect(snapshot.tagIDs == [tag.id])
        #expect(RetainedReminderValue(snapshot).scheduleData == raw)
        #expect(try await !fixture.repository.checkAccount(accountA))
        #expect(try context.fetch(FetchDescriptor<ReminderRecordV1>()).count == 1)
        let reopened = try RetainedReminderRepository(
            url: fixture.url, legacy: RetainedLegacySnapshot(container: container))
        #expect(try await reopened.fetchCompleteSnapshot().reminders.count == 1)
        #expect(await reopened.recoveryRevisions().isEmpty)
    }

    @Test func legacyCloudImporterReadsCDMRAndEncryptedAssetContents() async throws {
        let fixture = try fixture()
        defer { fixture.clean() }
        #expect(try await fixture.repository.checkAccount(accountA))
        let id = UUID()
        let tagID = UUID()
        let raw = Data([255, 254, 0, 1])
        let reminder = LegacyCloudRecord(
            name: "reminder", type: "CD_ReminderRecordV1",
            fields: [
                "CD_id": .string(id.uuidString), "CD_title": .string("Cloud legacy"),
                "CD_enabled": .number(1),
                "CD_scheduleData_ckAsset": .data(raw), "CD_createdAt": .date(timestamp),
                "CD_updatedAt": .date(timestamp)
            ])
        let tag = LegacyCloudRecord(
            name: "tag", type: "CD_TagRecordV1",
            fields: [
                "CD_id": .string(tagID.uuidString), "CD_name": .string("Tag"),
                "CD_normalizedName": .string("tag"),
                "CD_normalizationVersion": .string(TagLimits.normalizationVersion),
                "CD_createdAt": .date(timestamp), "CD_updatedAt": .date(timestamp)
            ])
        let relation = LegacyCloudRecord(
            name: "relation", type: "CDMR", fields: ["CD_recordNames": .string("reminder:tag")])
        try await fixture.repository.importLegacyPage(
            records: [reminder, tag, relation], deletedNames: [], token: Data([1]),
            account: accountA)
        let snapshot = try #require(await fixture.repository.reminder(id: id))
        #expect(snapshot.tagIDs == [tagID])
        #expect(RetainedReminderValue(snapshot).scheduleData == raw)
        #expect(await fixture.repository.canPublish(snapshot))
        let count = await fixture.repository.pendingRevisions(account: accountA).count
        try await fixture.repository.importLegacyPage(
            records: [reminder], deletedNames: [], token: Data([2]), account: accountA)
        #expect(await fixture.repository.pendingRevisions(account: accountA).count == count)
        #expect(await fixture.repository.legacyToken(account: accountA) == Data([2]))
        let ckRecord = CKRecord(recordType: "CD_ReminderRecordV1")
        ckRecord.encryptedValues["CD_title"] = "Private"
        ckRecord["CD_scheduleData"] = raw
        let portable = try LegacyCloudRecord(record: ckRecord)
        #expect(portable.string("title") == "Private")
        #expect(portable.bytes("scheduleData") == raw)
    }

    @Test func missingTagAndGlobalCommitAlsoKeepGateClosed() async throws {
        let fixture = try fixture()
        defer { fixture.clean() }
        #expect(try await fixture.repository.checkAccount(accountA))
        let tag = try await fixture.repository.saveTag(
            EncodedTagMutation(
                id: UUID(), name: "Tag", normalizedName: "tag",
                normalizationVersion: TagLimits.normalizationVersion,
                createdAt: timestamp, updatedAt: timestamp, command: .create
            ))
        let saved = try await fixture.repository.save(mutation(tagIDs: [tag.id]))
        try await fixture.repository.saveGlobalDisplayCustomizationData(Data("{}".utf8))
        let revisions = await fixture.repository.pendingRevisions(account: accountA)
        for revision in revisions where revision.entityKey.hasPrefix("reminder/") {
            try await fixture.repository.acknowledge(revision, account: accountA)
        }
        #expect(await !fixture.repository.canPublish(saved))
        for revision in revisions {
            try await fixture.repository.acknowledge(revision, account: accountA)
        }
        #expect(await fixture.repository.canPublish(saved))
    }

    @Test func corruptArchiveIsNeverReplacedWithAnEmptyStore() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = Data([255, 0, 1])
        try bytes.write(to: url)
        #expect(throws: (any Error).self) { try RetainedReminderRepository(url: url) }
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func failedLocalWriteDoesNotReleaseUnsavedMutation() async throws {
        let fixture = try fixture()
        defer { fixture.clean() }
        try await fixture.repository.setSyncEnabled(false)
        let saved = try await fixture.repository.save(mutation())
        try FileManager.default.removeItem(at: fixture.url)
        try FileManager.default.createDirectory(at: fixture.url, withIntermediateDirectories: true)
        await #expect(throws: (any Error).self) {
            try await fixture.repository.save(
                mutation(
                    id: saved.id, title: "Unsaved",
                    command: .updateMetadataPreservingCurrentSchedule))
        }
        #expect(try await fixture.repository.reminder(id: saved.id) == saved)
    }

    @Test func sharedProductionOpenSerializesMultipleScenes() async throws {
        let fixture = try fixture()
        defer { fixture.clean() }
        let first = try RetainedReminderRepository.open(url: fixture.url)
        let second = try RetainedReminderRepository.open(url: fixture.url)
        #expect(first === second)
        try await first.setSyncEnabled(false)
        let saved = try await first.save(mutation())
        #expect(try await second.reminder(id: saved.id) == saved)
    }

    @Test func legacyDeletionRetainsAnUnsyncedLocalBranchForRecovery() async throws {
        let fixture = try fixture()
        defer { fixture.clean() }
        #expect(try await fixture.repository.checkAccount(accountA))
        let id = UUID()
        let record = LegacyCloudRecord(
            name: "legacy", type: "CD_ReminderRecordV1",
            fields: [
                "CD_id": .string(id.uuidString), "CD_title": .string("Legacy"),
                "CD_enabled": .number(1),
                "CD_scheduleData": .data(Data([255, 0])), "CD_createdAt": .date(timestamp),
                "CD_updatedAt": .date(timestamp)
            ])
        try await fixture.repository.importLegacyPage(
            records: [record], deletedNames: [], token: Data([1]), account: accountA)
        _ = try await fixture.repository.save(
            mutation(id: id, title: "Local edit", command: .updateMetadataPreservingCurrentSchedule)
        )
        try await fixture.repository.importLegacyPage(
            records: [], deletedNames: ["legacy"], token: Data([2]), account: accountA)
        let current = try await fixture.repository.reminder(id: id)
        let recovery = await fixture.repository.recoveryRevisions()
        let values = recovery.compactMap { $0.payload }.compactMap {
            try? JSONDecoder().decode(RetainedReminderValue.self, from: $0).title
        }
        #expect(current?.title == "Local edit" || values.contains("Local edit"))
        #expect(!recovery.isEmpty)
    }

    @Test func immutableRecordCollisionAndCyclesCannotEraseCurrentData() async throws {
        let fixture = try fixture()
        defer { fixture.clean() }
        #expect(try await fixture.repository.checkAccount(accountA))
        let original = RetainedCloudRevision(entityKey: "customization/global", payload: Data([1]))
        try await fixture.repository.importRevision(original, account: accountA)
        let collision = RetainedCloudRevision(
            id: original.id, entityKey: original.entityKey, payload: Data([2]))
        await #expect(throws: RetainedStoreError.immutableRevisionCollision) {
            try await fixture.repository.importRevision(collision, account: accountA)
        }
        let cycle = RetainedCloudRevision(
            id: original.id, entityKey: original.entityKey, parents: [original.id], payload: nil)
        await #expect(throws: RetainedStoreError.invalidRevision) {
            try await fixture.repository.importRevision(cycle, account: accountA)
        }
        #expect(await fixture.repository.globalDisplayCustomizationData() == Data([1]))
    }

    @Test func partialCloudImportsKeepTheGateClosedUntilAllFetchesFinish() async throws {
        let fixture = try fixture()
        defer { fixture.clean() }
        #expect(try await fixture.repository.checkAccount(accountA))
        let saved = try await fixture.repository.save(mutation())
        let revision = try #require(
            await fixture.repository.pendingRevisions(account: accountA).first)
        try await fixture.repository.acknowledge(revision, account: accountA)
        let first = try await fixture.repository.beginCloudImport(account: accountA)
        let second = try await fixture.repository.beginCloudImport(account: accountA)
        #expect(await !fixture.repository.canPublish(saved))
        await fixture.repository.finishCloudImport(first)
        #expect(await !fixture.repository.canPublish(saved))
        await fixture.repository.finishCloudImport(second)
        #expect(await fixture.repository.canPublish(saved))
    }

    private func mutation(
        id: UUID = UUID(), title: String = "Reminder", tagIDs: Set<UUID> = [],
        command: ReminderMutationCommand? = nil
    ) throws -> EncodedReminderMutation {
        let schedule = ScheduleDefinition(
            source: SourceWallClock(
                year: 2030, month: 1, day: 2, hour: 12, minute: 0, timeZoneIdentifier: "Asia/Tokyo"),
            rule: .none, end: .never, early: nil)
        return EncodedReminderMutation(
            id: id, title: title, notes: nil, urlString: nil, enabled: true, tagIDs: tagIDs,
            createdAt: timestamp, updatedAt: timestamp,
            command: try command
                ?? .create(scheduleData: SchedulePayloadCodec().encodeCurrent(schedule).data)
        )
    }

    private func opaqueValue(schedule: Data) -> RetainedReminderValue {
        RetainedReminderValue(
            ReminderSnapshot(
                id: UUID(), title: "Opaque", notes: nil, urlString: nil, enabled: true,
                schedule: SchedulePayloadCodec().decode(schedule), tagIDs: [], createdAt: timestamp,
                updatedAt: timestamp
            ))
    }

    private func fixture(legacy: RetainedLegacySnapshot? = nil) throws -> RetainedTestFixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "retained-tests-\(UUID().uuidString)")
        let url = directory.appendingPathComponent("archive.json")
        return RetainedTestFixture(
            directory: directory, url: url,
            repository: try RetainedReminderRepository(url: url, legacy: legacy))
    }
}

private struct RetainedTestFixture {
    let directory: URL
    let url: URL
    let repository: RetainedReminderRepository
    func clean() { try? FileManager.default.removeItem(at: directory) }
}
