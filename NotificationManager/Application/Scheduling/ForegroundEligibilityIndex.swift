import Foundation

public struct ForegroundEligibilityIndex: Sendable, Equatable {
    public let generation: UInt64
    public let isStale: Bool
    public let eligibleReminderIDs: Set<UUID>

    public init(
        generation: UInt64,
        isStale: Bool,
        eligibleReminderIDs: Set<UUID>
    ) {
        self.generation = generation
        self.isStale = isStale
        self.eligibleReminderIDs = eligibleReminderIDs
    }
}

public final class ForegroundEligibilityIndexStore: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ForegroundEligibilityIndex(
        generation: 0,
        isStale: true,
        eligibleReminderIDs: []
    )

    public init() {}

    public func snapshot() -> ForegroundEligibilityIndex {
        lock.withLock { value }
    }

    public func isEligible(_ reminderID: UUID) -> Bool {
        lock.withLock {
            !value.isStale && value.eligibleReminderIDs.contains(reminderID)
        }
    }

    public func markStale() {
        lock.withLock {
            value = ForegroundEligibilityIndex(
                generation: value.generation,
                isStale: true,
                eligibleReminderIDs: value.eligibleReminderIDs
            )
        }
    }

    public func publish(eligibleReminderIDs: Set<UUID>) {
        lock.withLock {
            value = ForegroundEligibilityIndex(
                generation: value.generation &+ 1,
                isStale: false,
                eligibleReminderIDs: eligibleReminderIDs
            )
        }
    }
}
