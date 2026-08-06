import Foundation

public struct RepeatingTriggerComponents: Sendable, Equatable, Hashable {
    public let timeZoneIdentifier: String
    public let month: Int?
    public let day: Int?
    public let weekday: Int?
    public let hour: Int
    public let minute: Int
    public let second: Int

    public init(
        timeZoneIdentifier: String,
        month: Int? = nil,
        day: Int? = nil,
        weekday: Int? = nil,
        hour: Int,
        minute: Int,
        second: Int
    ) {
        self.timeZoneIdentifier = timeZoneIdentifier
        self.month = month
        self.day = day
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
        self.second = second
    }

    public func canonicalDocument() throws -> Data {
        try NotificationIdentifierCodec().canonicalDocument(for: self)
    }
}

public enum NotificationIdentifierClassification: Sendable, Equatable {
    case currentOneShot(reminderID: UUID, unixSeconds: Int64)
    case currentRepeating(reminderID: UUID, digest: String)
    case appOwnedStale
    case unrelated
}

public struct RepeatingTriggerContributor: Sendable, Equatable {
    public let kind: AlertKind
    public let sourceComponents: RepeatingTriggerComponents

    public init(kind: AlertKind, sourceComponents: RepeatingTriggerComponents) {
        self.kind = kind
        self.sourceComponents = sourceComponents
    }
}

public struct RepeatingTriggerCandidate: Sendable, Equatable {
    public let components: RepeatingTriggerComponents
    public let contributors: [RepeatingTriggerContributor]

    public init(
        components: RepeatingTriggerComponents,
        contributors: [RepeatingTriggerContributor]
    ) {
        self.components = components
        self.contributors = contributors
    }
}

public struct RepeatingTriggerPlanningInput: Sendable {
    public let schedule: ScheduleDefinition
    public let evaluationNow: Date
    public let physicalNotifications: [PhysicalNotification]
    public let environment: any RecurrenceEnvironment

    public init(
        schedule: ScheduleDefinition,
        evaluationNow: Date,
        physicalNotifications: [PhysicalNotification],
        environment: any RecurrenceEnvironment
    ) {
        self.schedule = schedule
        self.evaluationNow = evaluationNow
        self.physicalNotifications = physicalNotifications
        self.environment = environment
    }
}
