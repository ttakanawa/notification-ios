import Foundation
import NotificationManagerApplication
import NotificationManagerDomain

public enum SchedulePayloadCodecError: Error, Sendable, Equatable {
    case invalidSchedule([ScheduleValidationIssue])
}

public struct SchedulePayloadCodec: SchedulePayloadCoding {
    public static let format = "notification-manager.schedule"
    public static let currentVersion: UInt32 = 1

    public init() {}

    public func decode(_ data: Data) -> ScheduleReadState {
        guard let probe = try? StrictJSONValue.probeEnvelope(data),
              probe.format == Self.format
        else {
            return .corrupt(originalData: data)
        }
        guard probe.version > 0 else { return .corrupt(originalData: data) }
        guard probe.version == Self.currentVersion else {
            return .unsupportedFuture(version: probe.version, originalData: data)
        }
        guard let document = try? StrictJSONValue.parse(data) else {
            return .corrupt(originalData: data)
        }
        return decodeV1(document, originalData: data)
    }

    public func encodeCurrent(_ definition: ScheduleDefinition) throws -> Data {
        let issues = ReminderAggregateValidator().scheduleIssues(for: definition)
        guard issues.isEmpty else {
            throw SchedulePayloadCodecError.invalidSchedule(issues)
        }

        let envelope = ScheduleEnvelopeV1DTO(
            format: Self.format,
            payload: SchedulePayloadV1DTO(definition),
            version: Self.currentVersion
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(envelope)
    }

    private func decodeV1(_ document: StrictJSONValue, originalData: Data) -> ScheduleReadState {
        do {
            let payload = try RawPayload(document)
            let decoded = payload.makeDomain()
            var issues = decoded.combinationIssues
            if let definition = decoded.definition {
                issues.append(contentsOf: ReminderAggregateValidator().scheduleIssues(for: definition))
                issues = issues.removingDuplicates()
                if issues.isEmpty {
                    return .valid(definition, sourceVersion: Self.currentVersion, originalData: originalData)
                }
            }
            return .domainInvalid(
                repairSeed: decoded.repairSeed,
                originalData: originalData,
                issues: issues.isEmpty ? [.invalidSelector] : issues
            )
        } catch {
            return .corrupt(originalData: originalData)
        }
    }
}

private enum PayloadStructureError: Error {
    case invalid
}

private struct RawPayload {
    let source: SourceWallClock
    let rule: RawRule
    let end: RawEnd
    let early: EarlyReminder?

    init(_ document: StrictJSONValue) throws {
        let envelope = try document.requireObject(
            exactKeys: ["format", "payload", "version"],
            requiredKeys: ["format", "payload", "version"]
        )
        guard envelope["format"]?.stringValue == SchedulePayloadCodec.format,
              envelope["version"]?.integer(as: UInt32.self) == SchedulePayloadCodec.currentVersion,
              let payloadValue = envelope["payload"]
        else {
            throw PayloadStructureError.invalid
        }
        let payload = try payloadValue.requireObject(
            exactKeys: ["source", "rule", "end", "early"],
            requiredKeys: ["source", "rule", "end"]
        )
        source = try Self.decodeSource(payload["source"]!)
        rule = try RawRule(payload["rule"]!)
        end = try RawEnd(payload["end"]!)
        early = try payload["early"].map(Self.decodeEarly)
    }

    func makeDomain() -> DecodedPayload {
        let ruleResult = rule.makeDomain()
        let endResult = end.makeDomain()
        var issues = ruleResult.issues + endResult.issues
        let definition: ScheduleDefinition?
        if let rule = ruleResult.value, let end = endResult.value {
            definition = ScheduleDefinition(source: source, rule: rule, end: end, early: early)
        } else {
            definition = nil
        }
        if case .none? = ruleResult.value, case .onDate? = endResult.value {
            issues.append(.endNotAllowed)
        }
        return DecodedPayload(
            definition: definition,
            repairSeed: ScheduleRepairSeed(
                source: source,
                rule: ruleResult.value,
                end: endResult.value,
                early: early
            ),
            combinationIssues: issues.removingDuplicates()
        )
    }

    private static func decodeSource(_ value: StrictJSONValue) throws -> SourceWallClock {
        let object = try value.requireObject(
            exactKeys: ["year", "month", "day", "hour", "minute", "timeZone"],
            requiredKeys: ["year", "month", "day", "hour", "minute", "timeZone"]
        )
        return SourceWallClock(
            year: try object.requireInteger("year"),
            month: try object.requireInteger("month"),
            day: try object.requireInteger("day"),
            hour: try object.requireInteger("hour"),
            minute: try object.requireInteger("minute"),
            timeZoneIdentifier: try object.requireString("timeZone")
        )
    }

    private static func decodeEarly(_ value: StrictJSONValue) throws -> EarlyReminder {
        let object = try value.requireObject(
            exactKeys: ["value", "unit", "mainEnabled"],
            requiredKeys: ["value", "unit", "mainEnabled"]
        )
        guard let unit = EarlyReminderUnit(rawValue: try object.requireString("unit")) else {
            throw PayloadStructureError.invalid
        }
        return EarlyReminder(
            value: try object.requireInteger("value"),
            unit: unit,
            mainEnabled: try object.requireBool("mainEnabled")
        )
    }
}

private struct DecodedPayload {
    let definition: ScheduleDefinition?
    let repairSeed: ScheduleRepairSeed
    let combinationIssues: [ScheduleValidationIssue]
}

private struct RawRule {
    let type: String
    let interval: Int?
    let weekdaySetKind: WeekdaySetKind?
    let weekdays: [Weekday]?
    let selector: RawSelector?
    let month: Int?
    let keys: Set<String>

    init(_ value: StrictJSONValue) throws {
        let object = try value.requireObject(
            exactKeys: ["type", "interval", "weekdaySetKind", "weekdays", "selector", "month"],
            requiredKeys: ["type"]
        )
        keys = Set(object.keys)
        type = try object.requireString("type")
        guard ["none", "hourly", "daily", "weekly", "monthly", "yearly"].contains(type) else {
            throw PayloadStructureError.invalid
        }
        switch type {
        case "hourly", "daily":
            try object.requireKeys(["interval"])
        case "weekly":
            try object.requireKeys(["interval", "weekdaySetKind", "weekdays"])
        case "monthly", "yearly":
            try object.requireKeys(["interval", "selector"])
        default:
            break
        }
        interval = try object.optionalInteger("interval")
        if let value = object["weekdaySetKind"] {
            guard let decoded = WeekdaySetKind(rawValue: try value.requireString()) else {
                throw PayloadStructureError.invalid
            }
            weekdaySetKind = decoded
        } else {
            weekdaySetKind = nil
        }
        if let value = object["weekdays"] {
            guard case let .array(values) = value else { throw PayloadStructureError.invalid }
            weekdays = try values.map {
                guard let weekday = Weekday(rawValue: try $0.requireString()) else {
                    throw PayloadStructureError.invalid
                }
                return weekday
            }
        } else {
            weekdays = nil
        }
        selector = try object["selector"].map(RawSelector.init)
        month = try object.optionalInteger("month")
    }

    func makeDomain() -> PartialDomain<RepeatRule> {
        switch type {
        case "none":
            return PartialDomain(
                value: RepeatRule.none,
                issues: keys == ["type"] ? [] : [.invalidSelector]
            )
        case "hourly":
            return intervalRule { .hourly(interval: $0) }
        case "daily":
            return intervalRule { .daily(interval: $0) }
        case "weekly":
            guard let interval, let weekdaySetKind, let weekdays else {
                return PartialDomain(value: nil, issues: [.invalidWeekdaySet])
            }
            let expected: Set<String> = ["type", "interval", "weekdaySetKind", "weekdays"]
            return PartialDomain(
                value: .weekly(interval: interval, weekdaySetKind: weekdaySetKind, weekdays: weekdays),
                issues: keys == expected ? [] : [.invalidWeekdaySet]
            )
        case "monthly":
            guard let interval, let selectorResult = selector?.makeDomain(), let selector = selectorResult.value else {
                return PartialDomain(value: nil, issues: [.invalidSelector])
            }
            let expected: Set<String> = ["type", "interval", "selector"]
            return PartialDomain(
                value: .monthly(interval: interval, selector: selector),
                issues: (keys == expected ? [] : [.invalidSelector]) + selectorResult.issues
            )
        case "yearly":
            guard let interval, let selectorResult = selector?.makeDomain(), let selector = selectorResult.value else {
                return PartialDomain(value: nil, issues: [.invalidSelector])
            }
            let expected: Set<String> = month == nil
                ? ["type", "interval", "selector"]
                : ["type", "interval", "selector", "month"]
            return PartialDomain(
                value: .yearly(interval: interval, month: month, selector: selector),
                issues: (keys == expected ? [] : [.invalidSelector]) + selectorResult.issues
            )
        default:
            return PartialDomain(value: nil, issues: [.invalidSelector])
        }
    }

    private func intervalRule(_ makeRule: (Int) -> RepeatRule) -> PartialDomain<RepeatRule> {
        guard let interval else {
            return PartialDomain(value: nil, issues: [.intervalOutOfRange])
        }
        return PartialDomain(
            value: makeRule(interval),
            issues: keys == ["type", "interval"] ? [] : [.invalidSelector]
        )
    }
}

private struct RawSelector {
    let type: String
    let day: Int?
    let ordinal: Int?
    let daySet: DaySet?
    let weekday: Weekday?
    let keys: Set<String>

    init(_ value: StrictJSONValue) throws {
        let object = try value.requireObject(
            exactKeys: ["type", "day", "ordinal", "daySet", "weekday"],
            requiredKeys: ["type"]
        )
        keys = Set(object.keys)
        type = try object.requireString("type")
        guard [
            "anchorDay", "anchorMonthDay", "dayOfMonth", "lastDay",
            "ordinalDaySet", "ordinalWeekday"
        ].contains(type) else {
            throw PayloadStructureError.invalid
        }
        switch type {
        case "dayOfMonth":
            try object.requireKeys(["day"])
        case "ordinalDaySet":
            try object.requireKeys(["ordinal", "daySet"])
        case "ordinalWeekday":
            try object.requireKeys(["ordinal", "weekday"])
        default:
            break
        }
        day = try object.optionalInteger("day")
        ordinal = try object.optionalInteger("ordinal")
        if let value = object["daySet"] {
            guard let decoded = DaySet(rawValue: try value.requireString()) else {
                throw PayloadStructureError.invalid
            }
            daySet = decoded
        } else {
            daySet = nil
        }
        if let value = object["weekday"] {
            guard let decoded = Weekday(rawValue: try value.requireString()) else {
                throw PayloadStructureError.invalid
            }
            weekday = decoded
        } else {
            weekday = nil
        }
    }

    func makeDomain() -> PartialDomain<RepeatSelector> {
        switch type {
        case "anchorDay":
            return exact(.anchorDay, expectedKeys: ["type"])
        case "anchorMonthDay":
            return exact(.anchorMonthDay, expectedKeys: ["type"])
        case "dayOfMonth":
            guard let day else { return PartialDomain(value: nil, issues: [.invalidSelector]) }
            return exact(.dayOfMonth(day), expectedKeys: ["type", "day"])
        case "lastDay":
            return exact(.lastDay, expectedKeys: ["type"])
        case "ordinalDaySet":
            guard let ordinal, let daySet else {
                return PartialDomain(value: nil, issues: [.invalidSelector])
            }
            return exact(
                .ordinalDaySet(ordinal: ordinal, daySet: daySet),
                expectedKeys: ["type", "ordinal", "daySet"]
            )
        case "ordinalWeekday":
            guard let ordinal, let weekday else {
                return PartialDomain(value: nil, issues: [.invalidSelector])
            }
            return exact(
                .ordinalWeekday(ordinal: ordinal, weekday: weekday),
                expectedKeys: ["type", "ordinal", "weekday"]
            )
        default:
            return PartialDomain(value: nil, issues: [.invalidSelector])
        }
    }

    private func exact(_ value: RepeatSelector, expectedKeys: Set<String>) -> PartialDomain<RepeatSelector> {
        PartialDomain(value: value, issues: keys == expectedKeys ? [] : [.invalidSelector])
    }
}

private struct RawEnd {
    let type: String
    let year: Int?
    let month: Int?
    let day: Int?
    let keys: Set<String>

    init(_ value: StrictJSONValue) throws {
        let object = try value.requireObject(
            exactKeys: ["type", "year", "month", "day"],
            requiredKeys: ["type"]
        )
        keys = Set(object.keys)
        type = try object.requireString("type")
        guard ["never", "onDate"].contains(type) else {
            throw PayloadStructureError.invalid
        }
        if type == "onDate" {
            try object.requireKeys(["year", "month", "day"])
        }
        year = try object.optionalInteger("year")
        month = try object.optionalInteger("month")
        day = try object.optionalInteger("day")
    }

    func makeDomain() -> PartialDomain<RepeatEnd> {
        switch type {
        case "never":
            return PartialDomain(value: .never, issues: keys == ["type"] ? [] : [.invalidEndDate])
        case "onDate":
            guard let year, let month, let day else {
                return PartialDomain(value: nil, issues: [.invalidEndDate])
            }
            return PartialDomain(
                value: .onDate(SourceDate(year: year, month: month, day: day)),
                issues: keys == ["type", "year", "month", "day"] ? [] : [.invalidEndDate]
            )
        default:
            return PartialDomain(value: nil, issues: [.invalidEndDate])
        }
    }
}

private struct PartialDomain<Value> {
    let value: Value?
    let issues: [ScheduleValidationIssue]
}

private extension StrictJSONValue {
    func requireObject(exactKeys allowed: Set<String>, requiredKeys: Set<String>) throws -> [String: StrictJSONValue] {
        guard let object = objectValue,
              Set(object.keys).isSubset(of: allowed),
              requiredKeys.isSubset(of: Set(object.keys))
        else {
            throw PayloadStructureError.invalid
        }
        return object
    }

    func requireString() throws -> String {
        guard let value = stringValue else { throw PayloadStructureError.invalid }
        return value
    }
}

private extension Dictionary where Key == String, Value == StrictJSONValue {
    func requireKeys(_ keys: Set<String>) throws {
        guard keys.isSubset(of: Set(self.keys)) else {
            throw PayloadStructureError.invalid
        }
    }

    func requireString(_ key: String) throws -> String {
        guard let value = self[key]?.stringValue else { throw PayloadStructureError.invalid }
        return value
    }

    func requireBool(_ key: String) throws -> Bool {
        guard let value = self[key]?.boolValue else { throw PayloadStructureError.invalid }
        return value
    }

    func requireInteger(_ key: String) throws -> Int {
        guard let value = self[key]?.integer(as: Int.self) else {
            throw PayloadStructureError.invalid
        }
        return value
    }

    func optionalInteger(_ key: String) throws -> Int? {
        guard let value = self[key] else { return nil }
        guard let integer = value.integer(as: Int.self) else {
            throw PayloadStructureError.invalid
        }
        return integer
    }
}

private extension Weekday {
    init?(rawValue: String) {
        guard let index = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
            .firstIndex(of: rawValue)
        else {
            return nil
        }
        self.init(rawValue: index + 1)
    }
}

private extension WeekdaySetKind {
    init?(rawValue: String) {
        switch rawValue {
        case "explicit": self = .explicit
        case "weekday": self = .weekday
        case "weekend": self = .weekend
        default: return nil
        }
    }
}

private extension DaySet {
    init?(rawValue: String) {
        switch rawValue {
        case "weekday": self = .weekday
        case "weekend": self = .weekend
        default: return nil
        }
    }
}

private extension EarlyReminderUnit {
    init?(rawValue: String) {
        switch rawValue {
        case "minutes": self = .minutes
        case "hours": self = .hours
        case "days": self = .days
        case "weeks": self = .weeks
        default: return nil
        }
    }
}

private extension Array where Element == ScheduleValidationIssue {
    func removingDuplicates() -> Self {
        reduce(into: []) { result, issue in
            if !result.contains(issue) { result.append(issue) }
        }
    }
}
