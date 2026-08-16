import Foundation
import NotificationManagerDomain
import Testing

@testable import NotificationManagerPersistence

@Suite struct SchedulePayloadCodecTests {
    private let codec = SchedulePayloadCodec()

    @Test func encodesNormativeV1GoldenBytes() throws {
        let data = try codec.encodeCurrent(.weekdayFixture).data
        let expected = Data(
            #"{"format":"notification-manager.schedule","payload":{"early":{"mainEnabled":true,"unit":"minutes","value":5},"end":{"type":"never"},"rule":{"interval":1,"type":"weekly","weekdaySetKind":"weekday","weekdays":["monday","tuesday","wednesday","thursday","friday"]},"source":{"day":3,"hour":9,"minute":30,"month":8,"timeZone":"America/New_York","year":2026}},"version":1}"#
                .utf8
        )

        #expect(data == expected)
    }

    @Test func currentEncodingCarriesMatchingVersionAndBytes() throws {
        let encoded = try codec.encodeCurrent(.weekdayFixture)

        #expect(encoded.version == SchedulePayloadCodec.currentVersion)
        #expect(
            codec.decode(encoded.data)
                == .valid(
                    .weekdayFixture,
                    sourceVersion: encoded.version,
                    originalData: encoded.data
                ))
    }

    @Test(arguments: ["0", "-1", "1.0", "1e0", "null"])
    func rejectsNonCurrentNonUnsignedVersions(_ version: String) {
        let data = Data(
            #"{"format":"notification-manager.schedule","payload":{},"version":\#(version)}"#.utf8)

        #expect(codec.decode(data).isCorrupt)
    }

    @Test(arguments: ["2", "4294967295"])
    func futureVersionProbeShortCircuitsPayloadValidation(_ version: String) throws {
        let data = Data(
            #"{"format":"notification-manager.schedule","futureKey":null,"version":\#(version)}"#
                .utf8)
        let parsedVersion = try #require(UInt32(version))

        #expect(
            codec.decode(data) == .unsupportedFuture(version: parsedVersion, originalData: data))
    }

    @Test func futureVersionProbeSkipsNestedDuplicateKeys() {
        let duplicateKeys = Data(
            #"{"format":"notification-manager.schedule","version":2,"payload":{"a":1,"a":2}}"#.utf8)

        #expect(
            codec.decode(duplicateKeys)
                == .unsupportedFuture(version: 2, originalData: duplicateKeys))
    }

    @Test func futureVersionProbeHandlesNearLimitNestingWithoutUsingTheCallStack() {
        let depth = 8_000
        let deeplyNested = Data(
            (#"{"format":"notification-manager.schedule","version":2,"payload":"#
                + String(repeating: "[", count: depth)
                + "0"
                + String(repeating: "]", count: depth)
                + "}").utf8
        )

        #expect(deeplyNested.count > 15 * 1_024)
        #expect(deeplyNested.count < 16 * 1_024)
        #expect(
            codec.decode(deeplyNested) == .unsupportedFuture(version: 2, originalData: deeplyNested)
        )
    }

    @Test func futureVersionProbeStillRejectsAmbiguousHeadersAndMalformedJSON() {
        let documents = [
            #"{"format":"notification-manager.schedule","format":"notification-manager.schedule","version":2}"#,
            #"{"format":"notification-manager.schedule","version":2,"version":3}"#,
            #"{"format":"notification-manager.schedule","version":2,"payload":[}"#,
            #"{"format":"notification-manager.schedule","version":2,"payload":null}null"#
        ]

        for document in documents {
            let data = Data(document.utf8)
            #expect(codec.decode(data) == .corrupt(originalData: data))
        }
    }

    @Test func rejectsMalformedOrWrongFormatEnvelope() {
        let inputs = [
            Data(),
            Data([0xEF, 0xBB, 0xBF])
                + Data(#"{"format":"notification-manager.schedule","payload":{},"version":1}"#.utf8),
            Data(#"{"format":"other","payload":{},"version":1}"#.utf8),
            Data(#"{"payload":{},"version":1}"#.utf8),
            Data(#"{"format":null,"payload":{},"version":1}"#.utf8),
            Data(#"[]"#.utf8)
        ]

        for input in inputs {
            #expect(codec.decode(input) == .corrupt(originalData: input))
        }
    }

    @Test func rejectsUnknownMissingAndNullStructuralKeysInV1() {
        let documents = [
            #"{"format":"notification-manager.schedule","payload":{"source":{"year":2026,"month":8,"day":3,"hour":9,"minute":30,"timeZone":"America/New_York"},"rule":{"type":"none"},"end":{"type":"never"}},"version":1,"unknown":true}"#,
            #"{"format":"notification-manager.schedule","payload":{"rule":{"type":"none"},"end":{"type":"never"}},"version":1}"#,
            #"{"format":"notification-manager.schedule","payload":{"source":{"year":2026,"month":8,"day":3,"hour":9,"minute":30,"timeZone":"America/New_York","calendar":"gregorian"},"rule":{"type":"none"},"end":{"type":"never"}},"version":1}"#,
            #"{"format":"notification-manager.schedule","payload":{"source":{"year":2026,"month":8,"day":3,"hour":9,"minute":null,"timeZone":"America/New_York"},"rule":{"type":"none"},"end":{"type":"never"}},"version":1}"#,
            #"{"format":"notification-manager.schedule","payload":{"source":{"year":2026,"month":8,"day":3,"hour":9,"minute":30,"timeZone":"America/New_York"},"rule":{"type":"none","bogus":1},"end":{"type":"never"}},"version":1}"#,
            #"{"format":"notification-manager.schedule","payload":{"source":{"year":2026,"month":8,"day":3,"hour":9,"minute":30,"timeZone":"America/New_York"},"rule":{"type":"none"},"end":{"type":"never"},"early":{"value":5,"unit":"minutes"}},"version":1}"#
        ]

        for document in documents {
            let data = Data(document.utf8)
            #expect(codec.decode(data) == .corrupt(originalData: data))
        }
    }

    @Test func rejectsFloatingPointAndExponentIntegerFields() {
        for invalidDay in ["3.0", "3e0"] {
            let data = Data(
                #"{"format":"notification-manager.schedule","payload":{"source":{"year":2026,"month":8,"day":\#(invalidDay),"hour":9,"minute":30,"timeZone":"America/New_York"},"rule":{"type":"none"},"end":{"type":"never"}},"version":1}"#
                    .utf8)
            #expect(codec.decode(data) == .corrupt(originalData: data))
        }
    }

    @Test func rejectsDuplicateKeysAndUnknownEnumValuesAsCorrupt() {
        let documents = [
            #"{"format":"notification-manager.schedule","format":"notification-manager.schedule","payload":{},"version":1}"#,
            #"{"format":"notification-manager.schedule","payload":{"source":{"year":2026,"month":8,"day":3,"hour":9,"minute":30,"timeZone":"America/New_York"},"rule":{"type":"fortnightly"},"end":{"type":"never"}},"version":1}"#,
            #"{"format":"notification-manager.schedule","payload":{"source":{"year":2026,"month":8,"day":3,"hour":9,"minute":30,"timeZone":"America/New_York"},"rule":{"interval":1,"type":"weekly","weekdaySetKind":"workday","weekdays":["monday"]},"end":{"type":"never"}},"version":1}"#,
            #"{"format":"notification-manager.schedule","payload":{"source":{"year":2026,"month":8,"day":3,"hour":9,"minute":30,"timeZone":"America/New_York"},"rule":{"interval":1,"selector":{"type":"middleDay"},"type":"monthly"},"end":{"type":"never"}},"version":1}"#,
            #"{"format":"notification-manager.schedule","payload":{"source":{"year":2026,"month":8,"day":3,"hour":9,"minute":30,"timeZone":"America/New_York"},"rule":{"type":"none"},"end":{"type":"eventually"}},"version":1}"#,
            #"{"format":"notification-manager.schedule","payload":{"source":{"year":2026,"month":8,"day":3,"hour":9,"minute":30,"timeZone":"America/New_York"},"rule":{"type":"none"},"end":{"type":"never"},"early":{"mainEnabled":true,"unit":"months","value":1}},"version":1}"#
        ]

        for document in documents {
            let data = Data(document.utf8)
            #expect(codec.decode(data) == .corrupt(originalData: data))
        }
    }

    @Test func classifiesEveryKnownForbiddenRuleFieldAsDomainInvalid() {
        let rules = [
            #"{"type":"none","interval":1}"#,
            #"{"type":"hourly","interval":1,"month":2}"#,
            #"{"type":"daily","interval":1,"weekdays":["monday"]}"#,
            #"{"type":"weekly","interval":1,"weekdaySetKind":"explicit","weekdays":["monday"],"selector":{"type":"anchorDay"}}"#,
            #"{"type":"monthly","interval":1,"selector":{"type":"anchorDay"},"month":2}"#,
            #"{"type":"yearly","interval":1,"selector":{"type":"anchorMonthDay"},"weekdaySetKind":"weekday","weekdays":["monday","tuesday","wednesday","thursday","friday"]}"#
        ]

        for rule in rules {
            let data = payloadData(rule: rule)
            #expect(codec.decode(data).isDomainInvalid)
            #expect(codec.decode(data).originalData == data)
        }
    }

    @Test func classifiesEveryKnownForbiddenSelectorFieldAsDomainInvalid() {
        let selectors = [
            #"{"type":"anchorDay","day":3}"#,
            #"{"type":"anchorMonthDay","ordinal":1}"#,
            #"{"type":"dayOfMonth","day":3,"weekday":"monday"}"#,
            #"{"type":"lastDay","daySet":"weekday"}"#,
            #"{"type":"ordinalDaySet","ordinal":1,"daySet":"weekday","weekday":"monday"}"#,
            #"{"type":"ordinalWeekday","ordinal":1,"weekday":"monday","daySet":"weekday"}"#
        ]

        for selector in selectors {
            let rule = #"{"type":"monthly","interval":1,"selector":\#(selector)}"#
            let data = payloadData(rule: rule)
            #expect(codec.decode(data).isDomainInvalid)
            #expect(codec.decode(data).originalData == data)
        }
    }

    @Test func rejectsMissingNullAndWrongTypedTaggedUnionRequiredFieldsAsCorrupt() {
        let malformedRules = [
            #"{"type":"hourly"}"#,
            #"{"type":"daily","interval":null}"#,
            #"{"type":"monthly","interval":"1","selector":{"type":"anchorDay"}}"#,
            #"{"type":"yearly","interval":1.0,"selector":{"type":"anchorMonthDay"}}"#,
            #"{"type":"weekly","weekdaySetKind":"explicit","weekdays":["monday"]}"#,
            #"{"type":"weekly","interval":1,"weekdays":["monday"]}"#,
            #"{"type":"weekly","interval":1,"weekdaySetKind":"explicit"}"#,
            #"{"type":"weekly","interval":1,"weekdaySetKind":null,"weekdays":["monday"]}"#,
            #"{"type":"weekly","interval":1,"weekdaySetKind":"explicit","weekdays":{}}"#,
            #"{"type":"monthly","interval":1}"#,
            #"{"type":"yearly","interval":1,"selector":null}"#,
            #"{"type":"monthly","interval":1,"selector":{"type":"dayOfMonth"}}"#,
            #"{"type":"monthly","interval":1,"selector":{"type":"dayOfMonth","day":null}}"#,
            #"{"type":"monthly","interval":1,"selector":{"type":"dayOfMonth","day":"1"}}"#,
            #"{"type":"monthly","interval":1,"selector":{"type":"ordinalDaySet","daySet":"weekday"}}"#,
            #"{"type":"monthly","interval":1,"selector":{"type":"ordinalDaySet","ordinal":1}}"#,
            #"{"type":"monthly","interval":1,"selector":{"type":"ordinalDaySet","ordinal":null,"daySet":"weekday"}}"#,
            #"{"type":"monthly","interval":1,"selector":{"type":"ordinalDaySet","ordinal":1,"daySet":false}}"#,
            #"{"type":"monthly","interval":1,"selector":{"type":"ordinalWeekday","weekday":"monday"}}"#,
            #"{"type":"monthly","interval":1,"selector":{"type":"ordinalWeekday","ordinal":1}}"#,
            #"{"type":"monthly","interval":1,"selector":{"type":"ordinalWeekday","ordinal":[],"weekday":"monday"}}"#,
            #"{"type":"monthly","interval":1,"selector":{"type":"ordinalWeekday","ordinal":1,"weekday":null}}"#
        ]
        let malformedEnds = [
            #"{"type":"onDate","month":8,"day":4}"#,
            #"{"type":"onDate","year":2026,"day":4}"#,
            #"{"type":"onDate","year":2026,"month":8}"#,
            #"{"type":"onDate","year":null,"month":8,"day":4}"#,
            #"{"type":"onDate","year":2026,"month":"8","day":4}"#,
            #"{"type":"onDate","year":2026,"month":8,"day":false}"#
        ]

        for rule in malformedRules {
            let data = payloadData(rule: rule)
            #expect(codec.decode(data) == .corrupt(originalData: data))
        }
        for end in malformedEnds {
            let data = payloadData(rule: #"{"type":"daily","interval":1}"#, end: end)
            #expect(codec.decode(data) == .corrupt(originalData: data))
        }
    }

    @Test func classifiesSupportedRuleCombinationViolationsAsDomainInvalid() {
        let documents = [
            #"{"format":"notification-manager.schedule","payload":{"source":{"year":2026,"month":8,"day":3,"hour":9,"minute":30,"timeZone":"America/New_York"},"rule":{"type":"none","interval":1},"end":{"type":"never"}},"version":1}"#,
            #"{"format":"notification-manager.schedule","payload":{"source":{"year":2026,"month":8,"day":3,"hour":9,"minute":30,"timeZone":"America/New_York"},"rule":{"type":"monthly","interval":1,"selector":{"type":"anchorMonthDay"}},"end":{"type":"never"}},"version":1}"#,
            #"{"format":"notification-manager.schedule","payload":{"source":{"year":2026,"month":8,"day":3,"hour":9,"minute":30,"timeZone":"America/New_York"},"rule":{"type":"yearly","interval":1,"selector":{"type":"anchorDay"}},"end":{"type":"never"}},"version":1}"#,
            #"{"format":"notification-manager.schedule","payload":{"source":{"year":2026,"month":8,"day":3,"hour":9,"minute":30,"timeZone":"America/New_York"},"rule":{"type":"none"},"end":{"type":"onDate","year":2026,"month":8,"day":4}},"version":1}"#
        ]

        for document in documents {
            let data = Data(document.utf8)
            #expect(codec.decode(data).isDomainInvalid)
            #expect(codec.decode(data).originalData == data)
        }
    }

    @Test func reportsDomainIssuesAndKeepsSafelyDecodedRepairFields() {
        let data = Data(
            #"{"format":"notification-manager.schedule","payload":{"early":{"mainEnabled":false,"unit":"weeks","value":10000},"end":{"type":"onDate","year":2025,"month":2,"day":29},"rule":{"interval":0,"type":"daily"},"source":{"day":29,"hour":24,"minute":60,"month":2,"timeZone":"Etc/Unknown","year":2025}},"version":1}"#
                .utf8)

        guard case .domainInvalid(let seed, let original, let issues) = codec.decode(data) else {
            Issue.record("Expected a domain-invalid result")
            return
        }
        #expect(original == data)
        #expect(
            seed.source
                == SourceWallClock(
                    year: 2025, month: 2, day: 29, hour: 24, minute: 60,
                    timeZoneIdentifier: "Etc/Unknown"))
        #expect(seed.rule == .daily(interval: 0))
        #expect(seed.end == .onDate(SourceDate(year: 2025, month: 2, day: 29)))
        #expect(seed.early == EarlyReminder(value: 10_000, unit: .weeks, mainEnabled: false))
        #expect(issues.contains(.invalidSourceDay))
        #expect(issues.contains(.invalidSourceHour))
        #expect(issues.contains(.invalidSourceMinute))
        #expect(issues.contains(.invalidTimeZone))
        #expect(issues.contains(.intervalOutOfRange))
        #expect(issues.contains(.invalidEndDate))
        #expect(issues.contains(.earlyValueOutOfRange))
    }

    @Test func roundTripsEveryRuleSelectorEndAndEarlyVariant() throws {
        let schedules: [ScheduleDefinition] = [
            .fixture(rule: .none),
            .fixture(
                rule: .hourly(interval: 2), end: .onDate(SourceDate(year: 2026, month: 8, day: 4))),
            .fixture(rule: .daily(interval: 3)),
            .fixture(
                rule: .weekly(interval: 1, weekdaySetKind: .explicit, weekdays: [.monday, .sunday])),
            .fixture(
                rule: .weekly(
                    interval: 1, weekdaySetKind: .weekend, weekdays: [.saturday, .sunday])),
            .fixture(rule: .monthly(interval: 1, selector: .anchorDay)),
            .fixture(rule: .monthly(interval: 1, selector: .dayOfMonth(31))),
            .fixture(rule: .monthly(interval: 1, selector: .lastDay)),
            .fixture(
                rule: .monthly(interval: 1, selector: .ordinalDaySet(ordinal: 2, daySet: .weekend))),
            .fixture(
                rule: .monthly(
                    interval: 1, selector: .ordinalWeekday(ordinal: -1, weekday: .friday))),
            .fixture(rule: .yearly(interval: 1, month: nil, selector: .anchorMonthDay)),
            .fixture(
                rule: .yearly(interval: 1, month: 2, selector: .dayOfMonth(29)), sourceYear: 2024),
            .fixture(rule: .yearly(interval: 1, month: 4, selector: .lastDay)),
            .fixture(
                rule: .yearly(
                    interval: 1, month: 6, selector: .ordinalDaySet(ordinal: 5, daySet: .weekday))),
            .fixture(
                rule: .yearly(
                    interval: 1, month: 12, selector: .ordinalWeekday(ordinal: 1, weekday: .monday))
            ),
            .fixture(
                rule: .daily(interval: 1),
                early: EarlyReminder(value: 1, unit: .hours, mainEnabled: false)),
            .fixture(rule: .daily(interval: 1), early: EarlyReminder(value: 2, unit: .days)),
            .fixture(rule: .daily(interval: 1), early: EarlyReminder(value: 3, unit: .weeks))
        ]

        for schedule in schedules {
            let encoded = try codec.encodeCurrent(schedule)
            #expect(
                codec.decode(encoded.data)
                    == .valid(
                        schedule,
                        sourceVersion: encoded.version,
                        originalData: encoded.data
                    ))
        }
    }

    @Test func rejectsInvalidFixedYearlyDateAsDomainInvalid() {
        let data = Data(
            #"{"format":"notification-manager.schedule","payload":{"source":{"year":2026,"month":8,"day":3,"hour":9,"minute":30,"timeZone":"America/New_York"},"rule":{"interval":1,"month":4,"selector":{"day":31,"type":"dayOfMonth"},"type":"yearly"},"end":{"type":"never"}},"version":1}"#
                .utf8)

        guard case .domainInvalid(_, let original, let issues) = codec.decode(data) else {
            Issue.record("Expected a domain-invalid result")
            return
        }
        #expect(original == data)
        #expect(issues.contains(.invalidSelector))
    }

    @Test func preservesExactRawBytesForEveryReadClassification() {
        let valid =
            Data(" \n".utf8)
            + Data(
                #"{"version":1,"payload":{"end":{"type":"never"},"rule":{"type":"none"},"source":{"timeZone":"America/New_York","minute":30,"hour":9,"day":3,"month":8,"year":2026}},"format":"notification-manager.schedule"}"#
                    .utf8) + Data("\t".utf8)
        let future = Data(#"{"version":2,"format":"notification-manager.schedule"}"#.utf8)
        let corrupt = Data(#"{"format":"notification-manager.schedule","version":0}"#.utf8)
        let invalid = Data(
            #"{"format":"notification-manager.schedule","payload":{"end":{"type":"never"},"rule":{"interval":0,"type":"daily"},"source":{"day":3,"hour":9,"minute":30,"month":8,"timeZone":"America/New_York","year":2026}},"version":1}"#
                .utf8)

        #expect(codec.decode(valid).originalData == valid)
        #expect(codec.decode(future).originalData == future)
        #expect(codec.decode(corrupt).originalData == corrupt)
        #expect(codec.decode(invalid).originalData == invalid)
    }

    @Test func encodeRejectsUnvalidatedDomainDefinition() {
        let invalid = ScheduleDefinition.fixture(rule: .daily(interval: 0))

        #expect(throws: SchedulePayloadCodecError.self) {
            try codec.encodeCurrent(invalid)
        }
    }

    private func payloadData(rule: String, end: String = #"{"type":"never"}"#) -> Data {
        Data(
            #"{"format":"notification-manager.schedule","payload":{"source":{"year":2026,"month":8,"day":3,"hour":9,"minute":30,"timeZone":"America/New_York"},"rule":\#(rule),"end":\#(end)},"version":1}"#
                .utf8)
    }
}

extension ScheduleDefinition {
    fileprivate static let weekdayFixture = fixture(
        rule: .weekly(
            interval: 1,
            weekdaySetKind: .weekday,
            weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday]
        ),
        early: EarlyReminder(value: 5, unit: .minutes)
    )

    fileprivate static func fixture(
        rule: RepeatRule,
        end: RepeatEnd = .never,
        early: EarlyReminder? = nil,
        sourceYear: Int = 2026
    ) -> ScheduleDefinition {
        ScheduleDefinition(
            source: SourceWallClock(
                year: sourceYear,
                month: 8,
                day: 3,
                hour: 9,
                minute: 30,
                timeZoneIdentifier: "America/New_York"
            ),
            rule: rule,
            end: end,
            early: early
        )
    }
}

extension ScheduleReadState {
    fileprivate var isCorrupt: Bool {
        if case .corrupt = self { return true }
        return false
    }

    fileprivate var isDomainInvalid: Bool {
        if case .domainInvalid = self { return true }
        return false
    }

    fileprivate var originalData: Data {
        switch self {
        case .valid(_, _, let data),
            .unsupportedFuture(_, let data),
            .corrupt(let data),
            .domainInvalid(_, let data, _):
            data
        }
    }
}
