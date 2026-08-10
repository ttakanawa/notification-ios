import Foundation
import NotificationManagerDomain
import Testing
@testable import NotificationManagerApplication

@Suite("TagManagementUseCase")
struct TagManagementUseCaseTests {
    @Test func createPersistsTheFixedIDAndVersionedNormalizedIdentity() async throws {
        let repository = InMemoryReminderRepository()
        let useCase = TagManagementUseCase(
            repository: repository,
            normalizer: FixedTagNormalizer(result: .success("work")),
            now: { testDate("2026-08-06T12:00:00.900Z") }
        )

        let tag = try await useCase.create(
            name: "  ＷＯＲＫ  ",
            id: TestApplicationValues.tagID
        )

        #expect(tag.id == TestApplicationValues.tagID)
        #expect(tag.name == "  ＷＯＲＫ  ")
        #expect(tag.normalizedName == "work")
        #expect(tag.normalizationVersion == TagLimits.normalizationVersion)
        #expect(tag.createdAt == testDate("2026-08-06T12:00:00Z"))
        #expect(tag.updatedAt == testDate("2026-08-06T12:00:00Z"))
        #expect(await repository.savedTagMutations.map(\.command) == [.create])
    }

    @Test func createRejectsANameWhoseNormalizedIdentityIsEmpty() async throws {
        let repository = InMemoryReminderRepository()
        let useCase = TagManagementUseCase(
            repository: repository,
            normalizer: FixedTagNormalizer(result: .failure(.normalizedNameEmpty)),
            now: { testDate("2026-08-06T12:00:00Z") }
        )

        await #expect(throws: TagValidationIssue.normalizedNameEmpty) {
            try await useCase.create(name: "   ", id: TestApplicationValues.tagID)
        }
        #expect(await repository.savedTagMutations.isEmpty)
    }

    @Test func createDelegatesNormalizedDuplicateRejectionToTheRepository() async throws {
        let existing = tagSnapshot(
            id: TestApplicationValues.otherTagID,
            name: "Work",
            normalizedName: "work"
        )
        let repository = InMemoryReminderRepository(
            snapshot: CompleteReminderSnapshot(reminders: [], tags: [existing])
        )
        let useCase = TagManagementUseCase(
            repository: repository,
            normalizer: FixedTagNormalizer(result: .success("work")),
            now: { testDate("2026-08-06T12:00:00Z") }
        )

        await #expect(throws: TagRepositoryError.duplicateNormalizedName("work")) {
            try await useCase.create(name: "WORK", id: TestApplicationValues.tagID)
        }
        #expect(await repository.savedTagMutations.isEmpty)
    }

    @Test func renamePreservesIdentityAndCreationTimeWhileReplacingNormalizedName() async throws {
        let existing = tagSnapshot(
            id: TestApplicationValues.tagID,
            name: "Travel",
            normalizedName: "travel"
        )
        let repository = InMemoryReminderRepository(
            snapshot: CompleteReminderSnapshot(reminders: [], tags: [existing])
        )
        let useCase = TagManagementUseCase(
            repository: repository,
            normalizer: FixedTagNormalizer(result: .success("trips")),
            now: { testDate("2026-08-06T12:30:00.500Z") }
        )

        let renamed = try await useCase.rename(tagID: existing.id, name: "Trips")

        #expect(renamed.id == existing.id)
        #expect(renamed.createdAt == existing.createdAt)
        #expect(renamed.updatedAt == testDate("2026-08-06T12:30:00Z"))
        #expect(renamed.name == "Trips")
        #expect(renamed.normalizedName == "trips")
        #expect(await repository.savedTagMutations.map(\.command) == [.update])
    }

    @Test func renameRejectsADuplicateThroughTheRepositoryCriticalSection() async throws {
        let existing = tagSnapshot(
            id: TestApplicationValues.tagID,
            name: "Travel",
            normalizedName: "travel"
        )
        let collision = tagSnapshot(
            id: TestApplicationValues.otherTagID,
            name: "Work",
            normalizedName: "work"
        )
        let repository = InMemoryReminderRepository(
            snapshot: CompleteReminderSnapshot(reminders: [], tags: [existing, collision])
        )
        let useCase = TagManagementUseCase(
            repository: repository,
            normalizer: FixedTagNormalizer(result: .success("work")),
            now: { testDate("2026-08-06T12:30:00Z") }
        )

        await #expect(throws: TagRepositoryError.duplicateNormalizedName("work")) {
            try await useCase.rename(tagID: existing.id, name: "WORK")
        }
        #expect(await repository.storedTag(id: existing.id) == existing)
    }

    @Test func renameRequiresTheCurrentTagInsteadOfCreatingAReplacement() async throws {
        let repository = InMemoryReminderRepository()
        let useCase = TagManagementUseCase(
            repository: repository,
            normalizer: FixedTagNormalizer(result: .success("missing")),
            now: { testDate("2026-08-06T12:30:00Z") }
        )

        await #expect(throws: TagRepositoryError.notFound(TestApplicationValues.tagID)) {
            try await useCase.rename(tagID: TestApplicationValues.tagID, name: "Missing")
        }
        #expect(await repository.savedTagMutations.isEmpty)
    }

    @Test func renameDoesNotResurrectATagDeletedAfterItsFreshFetch() async throws {
        let existing = tagSnapshot(
            id: TestApplicationValues.tagID,
            name: "Travel",
            normalizedName: "travel"
        )
        let repository = InMemoryReminderRepository(
            snapshot: CompleteReminderSnapshot(reminders: [], tags: [existing]),
            deleteTagBeforeNextSaveID: existing.id
        )
        let useCase = TagManagementUseCase(
            repository: repository,
            normalizer: FixedTagNormalizer(result: .success("trips")),
            now: { testDate("2026-08-06T12:30:00Z") }
        )

        await #expect(throws: TagRepositoryError.notFound(existing.id)) {
            try await useCase.rename(tagID: existing.id, name: "Trips")
        }

        #expect(await repository.storedTag(id: existing.id) == nil)
        #expect(await repository.savedTagMutations.isEmpty)
    }

    @Test func deleteRemovesOnlyTheTagAggregate() async throws {
        let existing = tagSnapshot(
            id: TestApplicationValues.tagID,
            name: "Travel",
            normalizedName: "travel"
        )
        let reminder = reminderSnapshot(
            id: TestApplicationValues.reminderID,
            schedule: oneShotSchedule("2026-08-07T12:00:00Z"),
            tagIDs: [existing.id]
        )
        let repository = InMemoryReminderRepository(
            snapshot: CompleteReminderSnapshot(reminders: [reminder], tags: [existing])
        )
        let useCase = TagManagementUseCase(
            repository: repository,
            normalizer: FixedTagNormalizer(result: .success("unused")),
            now: { testDate("2026-08-06T12:30:00Z") }
        )

        try await useCase.delete(tagID: existing.id)

        #expect(await repository.storedTag(id: existing.id) == nil)
        let updatedReminder = try #require(await repository.reminder(id: reminder.id))
        #expect(updatedReminder.id == reminder.id)
        #expect(updatedReminder.title == reminder.title)
        #expect(updatedReminder.schedule == reminder.schedule)
        #expect(updatedReminder.tagIDs.isEmpty)
    }
}

private struct FixedTagNormalizer: TagNameNormalizing {
    let result: Result<String, TagValidationIssue>

    func normalize(_ name: String) throws -> String {
        try result.get()
    }
}

private func tagSnapshot(
    id: UUID,
    name: String,
    normalizedName: String
) -> TagSnapshot {
    TagSnapshot(
        id: id,
        name: name,
        normalizedName: normalizedName,
        createdAt: testDate("2026-08-01T00:00:00Z"),
        updatedAt: testDate("2026-08-01T00:00:00Z")
    )
}

extension TestApplicationValues {
    static let tagID = UUID(uuidString: "123E4567-E89B-12D3-A456-426614174001")!
    static let otherTagID = UUID(uuidString: "123E4567-E89B-12D3-A456-426614174002")!
}
