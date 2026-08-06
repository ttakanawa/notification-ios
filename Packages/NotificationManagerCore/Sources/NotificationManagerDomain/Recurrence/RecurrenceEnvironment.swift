import Foundation

public protocol RecurrenceEnvironment: Sendable {
    func timeZone(identifier: String) -> TimeZone?
    func gregorianCalendar(in timeZone: TimeZone) -> Calendar
}

public struct FoundationRecurrenceEnvironment: RecurrenceEnvironment, Sendable {
    public init() {}

    public func timeZone(identifier: String) -> TimeZone? {
        TimeZone(identifier: identifier)
    }

    public func gregorianCalendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

public extension RecurrenceEnvironment where Self == FoundationRecurrenceEnvironment {
    static var foundation: FoundationRecurrenceEnvironment {
        FoundationRecurrenceEnvironment()
    }
}
