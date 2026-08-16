import Foundation

public enum SourceWallClockResolutionError: Error, Sendable, Equatable {
    case invalidComponents
    case unknownTimeZone
    case unsupportedResult
}

public struct SourceWallClockResolver: Sendable {
    private static let fixedProbeMargin: TimeInterval = 7 * 24 * 3_600

    public init() {}

    public func resolve(
        _ source: SourceWallClock,
        environment: any RecurrenceEnvironment
    ) throws -> Date {
        guard let timeZone = environment.timeZone(identifier: source.timeZoneIdentifier) else {
            throw SourceWallClockResolutionError.unknownTimeZone
        }
        let calendar = environment.gregorianCalendar(in: timeZone)
        return try resolve(source, calendar: calendar)
    }

    func resolve(_ source: SourceWallClock, calendar: Calendar) throws -> Date {
        guard
            Self.isValidGregorianDate(
                year: source.year,
                month: source.month,
                day: source.day
            ),
            (0...23).contains(source.hour),
            (0...59).contains(source.minute)
        else {
            throw SourceWallClockResolutionError.invalidComponents
        }

        let components = DateComponents(
            year: source.year,
            month: source.month,
            day: source.day,
            hour: source.hour,
            minute: source.minute,
            second: 0
        )
        var utc = Calendar(identifier: .gregorian)
        guard let utcTimeZone = TimeZone(secondsFromGMT: 0) else {
            throw SourceWallClockResolutionError.unsupportedResult
        }
        utc.timeZone = utcTimeZone
        guard let nominal = utc.date(from: components) else {
            throw SourceWallClockResolutionError.invalidComponents
        }
        let probe = nominal.addingTimeInterval(-Self.fixedProbeMargin)
        guard
            let result = calendar.nextDate(
                after: probe,
                matching: components,
                matchingPolicy: .nextTimePreservingSmallerComponents,
                repeatedTimePolicy: .first,
                direction: .forward
            )
        else {
            throw SourceWallClockResolutionError.unsupportedResult
        }

        let interval = result.timeIntervalSinceReferenceDate
        let resultYear = calendar.component(.year, from: result)
        guard interval.isFinite,
            interval.rounded(FloatingPointRoundingRule.towardZero) == interval,
            (1...9_999).contains(resultYear)
        else {
            throw SourceWallClockResolutionError.unsupportedResult
        }
        return result
    }

    static func isValidGregorianDate(year: Int, month: Int, day: Int) -> Bool {
        guard (1...9_999).contains(year), (1...12).contains(month), day >= 1 else {
            return false
        }
        let maximumDay =
            switch month {
            case 2:
                isLeapYear(year) ? 29 : 28
            case 4, 6, 9, 11:
                30
            default:
                31
            }
        return day <= maximumDay
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        year.isMultiple(of: 4)
            && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
    }
}
