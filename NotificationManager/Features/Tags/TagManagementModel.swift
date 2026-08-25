import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import Observation

enum TagActionErrorIdentity: Sendable, Equatable {
    case emptyName
    case nameTooLarge
    case normalizedNameTooLarge
    case duplicateName
    case notFound
    case storeUnavailable
}

enum TagManagementLoadOutcome: Sendable, Equatable {
    case acceptedCompleteSnapshot(generation: UInt64)
    case notAccepted
}

@MainActor
@Observable
final class TagManagementModel {
    private(set) var tags: [TagSnapshot]
    private(set) var isWorking = false
    private(set) var actionError: TagActionErrorIdentity?
    private(set) var completeSnapshotGeneration: UInt64 = 0

    @ObservationIgnored private let repository: any ReminderRepository
    @ObservationIgnored private let useCase: TagManagementUseCase
    @ObservationIgnored private let associationRemovalCommitted: @Sendable () async -> Void

    init(
        repository: any ReminderRepository,
        useCase: TagManagementUseCase,
        initialTags: [TagSnapshot] = [],
        associationRemovalCommitted: @escaping @Sendable () async -> Void = {}
    ) {
        self.repository = repository
        self.useCase = useCase
        self.associationRemovalCommitted = associationRemovalCommitted
        tags = Self.sorted(initialTags)
    }

    @discardableResult
    func load() async -> TagManagementLoadOutcome {
        guard !isWorking else { return .notAccepted }
        isWorking = true
        actionError = nil
        defer { isWorking = false }
        do {
            tags = Self.sorted(try await repository.fetchCompleteSnapshot().tags)
            completeSnapshotGeneration &+= 1
            return .acceptedCompleteSnapshot(generation: completeSnapshotGeneration)
        } catch {
            actionError = Self.errorIdentity(for: error)
            return .notAccepted
        }
    }

    func create(name: String) async -> TagSnapshot? {
        guard !isWorking else { return nil }
        isWorking = true
        actionError = nil
        do {
            let tag = try await useCase.create(name: name)
            upsert(tag)
            isWorking = false
            return tag
        } catch {
            actionError = Self.errorIdentity(for: error)
            isWorking = false
            return nil
        }
    }

    func rename(tagID: UUID, name: String) async -> TagSnapshot? {
        guard !isWorking else { return nil }
        isWorking = true
        actionError = nil
        do {
            let tag = try await useCase.rename(tagID: tagID, name: name)
            upsert(tag)
            isWorking = false
            return tag
        } catch {
            actionError = Self.errorIdentity(for: error)
            isWorking = false
            return nil
        }
    }

    func delete(tagID: UUID) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        actionError = nil
        do {
            try await useCase.delete(tagID: tagID)
            tags.removeAll { $0.id == tagID }
            isWorking = false
            return true
        } catch {
            actionError = Self.errorIdentity(for: error)
            isWorking = false
            return false
        }
    }

    func removeAssociation(
        tagID: UUID,
        from reminderID: UUID?
    ) async -> TagAssociationRemovalOutcome? {
        guard !isWorking else { return nil }
        isWorking = true
        actionError = nil
        defer { isWorking = false }
        do {
            let outcome = try await repository.removeTagAssociation(
                tagID: tagID,
                from: reminderID
            )
            if outcome == .tagDeleted {
                tags.removeAll { $0.id == tagID }
            }
            await associationRemovalCommitted()
            return outcome
        } catch {
            actionError = Self.errorIdentity(for: error)
            return nil
        }
    }

    private func upsert(_ tag: TagSnapshot) {
        tags.removeAll { $0.id == tag.id }
        tags.append(tag)
        tags = Self.sorted(tags)
    }

    private static func sorted(_ tags: [TagSnapshot]) -> [TagSnapshot] {
        tags.sorted {
            if $0.normalizedName != $1.normalizedName {
                return $0.normalizedName < $1.normalizedName
            }
            if $0.name != $1.name {
                return $0.name < $1.name
            }
            return $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased()
        }
    }

    private static func errorIdentity(for error: any Error) -> TagActionErrorIdentity {
        if let issue = error as? TagValidationIssue {
            return errorIdentity(for: issue)
        }
        if let error = error as? TagRepositoryError {
            switch error {
            case .notFound: return .notFound
            case .duplicateName: return .duplicateName
            case .invalid(let issue):
                return errorIdentity(for: issue)
            case .duplicateID, .unavailable: return .storeUnavailable
            }
        }
        return .storeUnavailable
    }

    private static func errorIdentity(for issue: TagValidationIssue) -> TagActionErrorIdentity {
        switch issue {
        case .normalizedNameEmpty:
            .emptyName
        case .nameTooLarge:
            .nameTooLarge
        case .normalizedNameTooLarge:
            .normalizedNameTooLarge
        case .normalizedNameMismatch, .unsupportedNormalizationVersion,
            .invalidCreatedAt, .invalidUpdatedAt:
            .storeUnavailable
        }
    }
}

enum TagPickerSelection {
    static func reconciled(
        selectedIDs: Set<UUID>,
        availableIDs: Set<UUID>
    ) -> Set<UUID> {
        selectedIDs.intersection(availableIDs)
    }

    static func selecting(_ tagID: UUID, in selectedIDs: Set<UUID>) -> Set<UUID> {
        var result = selectedIDs
        result.insert(tagID)
        return result
    }

    static func reconciled(
        selectedIDs: Set<UUID>,
        availableIDs: Set<UUID>,
        after outcome: TagManagementLoadOutcome
    ) -> Set<UUID> {
        guard case .acceptedCompleteSnapshot = outcome else { return selectedIDs }
        return reconciled(selectedIDs: selectedIDs, availableIDs: availableIDs)
    }
}

struct TagPickerSuggestionState {
    let matches: [TagSnapshot]
    let trimmedQuery: String
    let creationName: String?
    let exactMatch: TagSnapshot?

    init(tags: [TagSnapshot], query: String) {
        let trimmed = TagNameNormalizerV1.trimmedDisplayName(query)
        trimmedQuery = trimmed
        exactMatch = tags.first {
            TagNameNormalizerV1.trimmedDisplayName($0.name) == trimmed
        }

        guard !trimmed.isEmpty,
            let normalizedQuery = try? TagNameNormalizerV1().normalize(trimmed)
        else {
            matches = tags
            creationName = nil
            return
        }

        matches =
            tags
            .filter { $0.normalizedName.contains(normalizedQuery) }
            .sorted {
                let lhsRank = Self.rank($0.normalizedName, query: normalizedQuery)
                let rhsRank = Self.rank($1.normalizedName, query: normalizedQuery)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                if $0.normalizedName != $1.normalizedName {
                    return $0.normalizedName < $1.normalizedName
                }
                if $0.name != $1.name { return $0.name < $1.name }
                return $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased()
            }
        creationName = exactMatch == nil ? trimmed : nil
    }

    private static func rank(_ name: String, query: String) -> Int {
        if name == query { return 0 }
        if name.hasPrefix(query) { return 1 }
        return 2
    }
}
