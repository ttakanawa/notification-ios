import Foundation

public struct ReminderDraft: Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var notes: String?
    public var urlString: String?
    public var enabled: Bool
    public var date: SourceDate?
    public var time: SourceTime?
    public var timeZoneIdentifier: String?
    public var rule: RepeatRule
    public var end: RepeatEnd
    public var early: EarlyReminder?
    public var scheduleChange: DraftScheduleChange
    public let originalScheduleData: Data?
    public var tagIDs: Set<UUID>
    public let createdAt: Date
    public var updatedAt: Date

    public var source: SourceWallClock? {
        get {
            guard let date, let time, let timeZoneIdentifier else { return nil }
            return SourceWallClock(
                year: date.year,
                month: date.month,
                day: date.day,
                hour: time.hour,
                minute: time.minute,
                timeZoneIdentifier: timeZoneIdentifier
            )
        }
        set {
            date = newValue.map { SourceDate(year: $0.year, month: $0.month, day: $0.day) }
            time = newValue.map { SourceTime(hour: $0.hour, minute: $0.minute) }
            timeZoneIdentifier = newValue?.timeZoneIdentifier
        }
    }

    public init(
        id: UUID = UUID(),
        title: String = "",
        notes: String? = nil,
        urlString: String? = nil,
        enabled: Bool = true,
        source: SourceWallClock? = nil,
        rule: RepeatRule = .none,
        end: RepeatEnd = .never,
        early: EarlyReminder? = nil,
        scheduleChange: DraftScheduleChange = .preserveOriginal,
        originalScheduleData: Data? = nil,
        tagIDs: Set<UUID> = [],
        createdAt: Date,
        updatedAt: Date
    ) {
        let effectiveSource: SourceWallClock?
        let effectiveRule: RepeatRule
        let effectiveEnd: RepeatEnd
        let effectiveEarly: EarlyReminder?
        switch scheduleChange {
        case .preserveOriginal:
            effectiveSource = source
            effectiveRule = rule
            effectiveEnd = end
            effectiveEarly = early
        case .replace(let schedule):
            effectiveSource = schedule.source
            effectiveRule = schedule.rule
            effectiveEnd = schedule.end
            effectiveEarly = schedule.early
        }

        self.id = id
        self.title = title
        self.notes = notes
        self.urlString = urlString
        self.enabled = enabled
        date = effectiveSource.map { SourceDate(year: $0.year, month: $0.month, day: $0.day) }
        time = effectiveSource.map { SourceTime(hour: $0.hour, minute: $0.minute) }
        timeZoneIdentifier = effectiveSource?.timeZoneIdentifier
        self.rule = effectiveRule
        self.end = effectiveEnd
        self.early = effectiveEarly
        self.scheduleChange = scheduleChange
        self.originalScheduleData = originalScheduleData
        self.tagIDs = tagIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(id: UUID = UUID(), now: Date = Date()) {
        let timestamp = Self.integralSecond(now)
        self.init(id: id, createdAt: timestamp, updatedAt: timestamp)
    }

    public init(snapshot: ReminderSnapshot) {
        let editableSchedule: ScheduleRepairSeed
        switch snapshot.schedule {
        case .valid(let schedule, _, _):
            editableSchedule = ScheduleRepairSeed(
                source: schedule.source,
                rule: schedule.rule,
                end: schedule.end,
                early: schedule.early
            )
        case .domainInvalid(let repairSeed, _, _):
            editableSchedule = repairSeed
        case .unsupportedFuture, .corrupt:
            editableSchedule = ScheduleRepairSeed()
        }

        self.init(
            id: snapshot.id,
            title: snapshot.title,
            notes: snapshot.notes,
            urlString: snapshot.urlString,
            enabled: snapshot.enabled,
            source: editableSchedule.source,
            rule: editableSchedule.rule ?? .none,
            end: editableSchedule.end ?? .never,
            early: editableSchedule.early,
            scheduleChange: .preserveOriginal,
            originalScheduleData: snapshot.schedule.originalData,
            tagIDs: snapshot.tagIDs,
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt
        )
    }

    public func scheduleData(replacementData: Data) -> Data? {
        switch scheduleChange {
        case .preserveOriginal:
            originalScheduleData
        case .replace:
            replacementData
        }
    }

    private static func integralSecond(_ date: Date) -> Date {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite else { return date }
        return Date(timeIntervalSince1970: seconds.rounded(.down))
    }
}

extension ScheduleReadState {
    fileprivate var originalData: Data {
        switch self {
        case .valid(_, _, let originalData),
            .unsupportedFuture(_, let originalData),
            .corrupt(let originalData),
            .domainInvalid(_, let originalData, _):
            originalData
        }
    }
}
