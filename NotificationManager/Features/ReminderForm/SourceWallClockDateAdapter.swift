import Foundation
import NotificationManagerDomain

struct SourceWallClockDateAdapter: Sendable {
    let timeZone: TimeZone

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZone
        return value
    }

    func nextWholeHour(after now: Date) -> SourceWallClock? {
        guard let value = calendar.nextDate(
            after: now,
            matching: DateComponents(minute: 0, second: 0),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) else { return nil }
        let date = sourceDate(from: value)
        let time = sourceTime(from: value)
        return SourceWallClock(
            year: date.year,
            month: date.month,
            day: date.day,
            hour: time.hour,
            minute: time.minute,
            timeZoneIdentifier: timeZone.identifier
        )
    }

    func instant(date: SourceDate, time: SourceTime) -> Date? {
        calendar.date(from: DateComponents(
            year: date.year,
            month: date.month,
            day: date.day,
            hour: time.hour,
            minute: time.minute
        ))
    }

    func sourceDate(from value: Date) -> SourceDate {
        let values = calendar.dateComponents([.year, .month, .day], from: value)
        return SourceDate(year: values.year!, month: values.month!, day: values.day!)
    }

    func sourceTime(from value: Date) -> SourceTime {
        let values = calendar.dateComponents([.hour, .minute], from: value)
        return SourceTime(hour: values.hour!, minute: values.minute!)
    }
}
