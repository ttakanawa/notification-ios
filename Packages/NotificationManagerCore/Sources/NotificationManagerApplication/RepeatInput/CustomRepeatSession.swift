import Foundation
import NotificationManagerDomain

public struct CustomRepeatPreview: Sendable, Equatable {
    public let route: CustomRepeatResolutionRoute
    public let rule: RepeatRule
    public let canonicalEnglish: String
    public let nextNotifications: NextNotificationResult

    public init(
        route: CustomRepeatResolutionRoute,
        rule: RepeatRule,
        canonicalEnglish: String,
        nextNotifications: NextNotificationResult
    ) {
        self.route = route
        self.rule = rule
        self.canonicalEnglish = canonicalEnglish
        self.nextNotifications = nextNotifications
    }
}

public enum CustomRepeatSessionState: Sendable, Equatable {
    case idle
    case failed(CustomRepeatResolutionError)
    case awaitingSuggestion(String)
    case awaitingConfirmation(CustomRepeatPreview)
    case confirmed(CustomRepeatPreview)
}

public enum CustomRepeatSubmissionOutcome: Sendable, Equatable {
    case applied(CustomRepeatSessionState)
    case superseded
}

public actor CustomRepeatSession {
    private let resolver: any CustomRepeatInputResolving
    private let reminderID: UUID
    private let now: @Sendable () -> Date
    private let recurrenceEnvironment: any RecurrenceEnvironment

    private var rawInput: String?
    private var generatedCandidate: RepeatCandidate?
    private var pendingSchedule: ScheduleDefinition?
    private var preview: CustomRepeatPreview?
    private var state: CustomRepeatSessionState = .idle
    private var submissionGeneration: UInt64 = 0

    public init(
        resolver: any CustomRepeatInputResolving,
        reminderID: UUID,
        now: @escaping @Sendable () -> Date,
        recurrenceEnvironment: any RecurrenceEnvironment
    ) {
        self.resolver = resolver
        self.reminderID = reminderID
        self.now = now
        self.recurrenceEnvironment = recurrenceEnvironment
    }

    @discardableResult
    public func submit(_ input: String) async throws -> CustomRepeatSubmissionOutcome {
        submissionGeneration += 1
        let generation = submissionGeneration
        clearPending()
        rawInput = input

        let resolution = await resolver.resolve(input)
        guard generation == submissionGeneration else {
            return .superseded
        }

        switch resolution {
        case let .failed(error):
            state = .failed(error)
        case let .suggested(suggestion):
            state = .awaitingSuggestion(suggestion)
        case let .resolved(resolved):
            do {
                let nextNotifications = try NextNotificationProvider().nextPhysicalNotifications(
                    for: reminderID,
                    schedule: resolved.schedule,
                    after: now(),
                    environment: recurrenceEnvironment
                )
                let presentation = CustomRepeatPreview(
                    route: resolved.route,
                    rule: resolved.rule,
                    canonicalEnglish: CanonicalRepeatFormatter().string(for: resolved.rule),
                    nextNotifications: nextNotifications
                )
                generatedCandidate = resolved.candidate
                pendingSchedule = resolved.schedule
                preview = presentation
                state = .awaitingConfirmation(presentation)
            } catch {
                clearPending()
                throw error
            }
        }
        return .applied(state)
    }

    public func confirm() -> ScheduleDefinition? {
        guard let pendingSchedule, let preview else { return nil }
        state = .confirmed(preview)
        return pendingSchedule
    }

    @discardableResult
    public func reset() -> CustomRepeatSessionState {
        submissionGeneration += 1
        rawInput = nil
        clearPending()
        state = .idle
        return state
    }

    private func clearPending() {
        generatedCandidate = nil
        pendingSchedule = nil
        preview = nil
    }
}
