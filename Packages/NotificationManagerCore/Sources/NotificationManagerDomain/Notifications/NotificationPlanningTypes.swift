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

    public func validated() throws -> RepeatingTriggerComponents {
        guard TimeZone(identifier: timeZoneIdentifier) != nil,
            month.map({ (1...12).contains($0) }) ?? true,
            day.map({ (1...31).contains($0) }) ?? true,
            weekday.map({ (1...7).contains($0) }) ?? true,
            (0...23).contains(hour),
            (0...59).contains(minute),
            (0...59).contains(second),
            hasAllowedShape,
            hasValidFixedMonthDay
        else {
            throw NotificationIdentifierCodecError.invalidRepeatingComponents
        }
        return self
    }

    private var hasAllowedShape: Bool {
        switch (month, day, weekday) {
        case (nil, nil, nil),
            (nil, nil, .some),
            (nil, .some, nil),
            (.some, .some, nil):
            true
        default:
            false
        }
    }

    private var hasValidFixedMonthDay: Bool {
        guard let month, let day else { return true }
        let maximumDay =
            switch month {
            case 2: 29
            case 4, 6, 9, 11: 30
            default: 31
            }
        return day <= maximumDay
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
