import Foundation
import Testing

@testable import NotificationManagerDomain

@Suite("ReminderAggregateValidatorTests")
struct ReminderAggregateValidatorTests {
    @Test func rejectsBlankTrimmedTitle() {
        #expect(throws: ReminderValidationIssue.titleEmpty) {
            try validator.validate(draft(title: " \n\t "))
        }
    }

    @Test func acceptsTitleAt512UTF8Bytes() throws {
        try validator.validate(draft(title: String(repeating: "a", count: 512)))
    }

    @Test func rejectsTitleOver512UTF8Bytes() {
        #expect(throws: ReminderValidationIssue.titleTooLarge) {
            try validator.validate(draft(title: String(repeating: "a", count: 513)))
        }
    }

    @Test func countsUTF8BytesInsteadOfCharacters() {
        #expect(throws: ReminderValidationIssue.titleTooLarge) {
            try validator.validate(draft(title: String(repeating: "é", count: 257)))
        }
    }

    @Test func enforcesNotesByteBoundary() throws {
        try validator.validate(draft(notes: String(repeating: "a", count: 65_536)))

        #expect(throws: ReminderValidationIssue.notesTooLarge) {
            try validator.validate(draft(notes: String(repeating: "a", count: 65_537)))
        }
    }

    @Test func canonicalizesHTTPURLWithoutReorderingEncodedComponents() throws {
        let url = try CanonicalHTTPURL(
            "HTTPS://User:Pass@EXAMPLE.COM:443/a%2Fb?q=one%20two&q=three#Frag"
        )

        #expect(
            url.string
                == "https://User:Pass@example.com/a%2Fb?q=one%20two&q=three#Frag"
        )
    }

    @Test(arguments: [
        "ftp://example.com/file",
        "https:///missing-host",
        "relative/path",
        "https://exa mple.com",
        "https://example.com:99999",
        "https://example.com:999999999999999999999999",
        "https://example.com/%ZZ"
    ])
    func rejectsMalformedOrUnsupportedURLs(_ value: String) {
        #expect(throws: CanonicalHTTPURLError.self) {
            _ = try CanonicalHTTPURL(value)
        }
    }

    @Test func removesOnlyMatchingDefaultPort() throws {
        #expect(try CanonicalHTTPURL("http://EXAMPLE.com:80/").string == "http://example.com/")
        #expect(try CanonicalHTTPURL("https://EXAMPLE.com:443/").string == "https://example.com/")
        #expect(try CanonicalHTTPURL("https://EXAMPLE.com:80/").string == "https://example.com:80/")
    }

    @Test func enforcesCanonicalURLByteBoundary() throws {
        let prefix = "https://example.com/"
        let exact =
            prefix + String(repeating: "a", count: ReminderLimits.urlBytes - prefix.utf8.count)
        try validator.validate(draft(urlString: exact))

        #expect(throws: ReminderValidationIssue.urlTooLarge) {
            try validator.validate(draft(urlString: exact + "a"))
        }
    }

    @Test func rejectsInvalidURLFromAggregate() {
        #expect(throws: ReminderValidationIssue.invalidURL) {
            try validator.validate(draft(urlString: "mailto:test@example.com"))
        }
    }

    @Test func validationReturnsCanonicalPersistenceValues() throws {
        let original = Data([0x7B, 0x7D])
        let validated = try validator.validate(
            draft(
                urlString: "HTTPS://EXAMPLE.COM:443/a%2Fb?q=one%20two",
                originalScheduleData: original
            )
        )

        #expect(validated.urlString == "https://example.com/a%2Fb?q=one%20two")
        #expect(validated.scheduleData == original)
    }

    @Test func enforcesRawScheduleByteBoundaryWhenPreserving() throws {
        try validator.validate(
            draft(originalScheduleData: Data(count: ReminderLimits.scheduleBytes)))

        #expect(throws: ReminderValidationIssue.scheduleTooLarge) {
            try validator.validate(
                draft(originalScheduleData: Data(count: ReminderLimits.scheduleBytes + 1))
            )
        }
    }

    @Test func enforcesEncodedScheduleByteBoundaryWhenReplacing() throws {
        let replacementDraft = draft(scheduleChange: .replace(validSchedule))
        try validator.validate(
            replacementDraft,
            replacementScheduleData: Data(count: ReminderLimits.scheduleBytes)
        )

        #expect(throws: ReminderValidationIssue.scheduleTooLarge) {
            try validator.validate(
                replacementDraft,
                replacementScheduleData: Data(count: ReminderLimits.scheduleBytes + 1)
            )
        }
    }

    @Test func replacementRequiresEncodedScheduleBytes() {
        #expect(throws: ReminderValidationIssue.replacementScheduleDataRequired) {
            try validator.validate(draft(scheduleChange: .replace(validSchedule)))
        }
    }

    @Test func replacementRejectsDraftFieldsThatDivergeAfterEditing() {
        var replacementDraft = draft(scheduleChange: .replace(validSchedule))
        replacementDraft.date = SourceDate(year: 2026, month: 8, day: 5)

        #expect(throws: ReminderValidationIssue.scheduleFieldsDoNotMatchReplacement) {
            try validator.validate(replacementDraft, replacementScheduleData: Data())
        }
    }

    @Test func newDraftWithoutACompleteScheduleCannotValidate() {
        #expect(throws: ReminderValidationIssue.missingScheduleData) {
            try validator.validate(draft(originalScheduleData: nil))
        }
    }

    @Test func enforcesTagCountBoundary() throws {
        try validator.validate(draft(tagIDs: tagIDs(count: ReminderLimits.tagCount)))

        #expect(throws: ReminderValidationIssue.tooManyTags) {
            try validator.validate(draft(tagIDs: tagIDs(count: ReminderLimits.tagCount + 1)))
        }
    }

    @Test func preservesOriginalScheduleBytesUntilReplacement() {
        let original = Data([0x00, 0xFF, 0x01])
        let replacement = Data([0x02])
        let preserving = draft(originalScheduleData: original)
        let replacing = draft(
            originalScheduleData: original,
            scheduleChange: .replace(validSchedule)
        )

        #expect(preserving.scheduleData(replacementData: replacement) == original)
        #expect(replacing.scheduleData(replacementData: replacement) == replacement)
    }

    @Test func editingDraftPreservesBytesForEveryScheduleReadState() {
        let original = Data([0x7B, 0x00, 0x7D])
        let states: [ScheduleReadState] = [
            .valid(validSchedule, sourceVersion: 1, originalData: original),
            .unsupportedFuture(version: 3, originalData: original),
            .corrupt(originalData: original),
            .domainInvalid(
                repairSeed: ScheduleRepairSeed(source: validSource),
                originalData: original,
                issues: [.invalidSelector]
            )
        ]

        for state in states {
            let snapshot = ReminderSnapshot(
                id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                title: "Tokyo open",
                notes: nil,
                urlString: nil,
                enabled: true,
                schedule: state,
                tagIDs: [],
                createdAt: Date(timeIntervalSince1970: 1_786_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_786_000_000)
            )
            let draft = ReminderDraft(snapshot: snapshot)

            #expect(draft.scheduleChange == .preserveOriginal)
            #expect(draft.scheduleData(replacementData: Data([0x01])) == original)
        }
    }

    @Test func detachedDraftDefaultsRemainStable() {
        let now = Date(timeIntervalSince1970: 1_786_000_000.75)
        let draft = ReminderDraft(now: now)
        let capturedID = draft.id

        #expect(draft.id == capturedID)
        #expect(draft.enabled)
        #expect(draft.date == nil)
        #expect(draft.time == nil)
        #expect(draft.timeZoneIdentifier == nil)
        #expect(draft.source == nil)
        #expect(draft.rule == .none)
        #expect(draft.end == .never)
        #expect(draft.early == nil)
        #expect(draft.scheduleChange == .preserveOriginal)
        #expect(draft.createdAt == Date(timeIntervalSince1970: 1_786_000_000))
        #expect(draft.updatedAt == Date(timeIntervalSince1970: 1_786_000_000))
    }

    @Test func detachedDraftKeepsPartiallyEnteredSourceFields() {
        var draft = ReminderDraft(now: Date(timeIntervalSince1970: 1_786_000_000))
        draft.date = SourceDate(year: 2026, month: 8, day: 4)
        draft.time = SourceTime(hour: 9, minute: 30)

        #expect(draft.source == nil)
        #expect(draft.date == SourceDate(year: 2026, month: 8, day: 4))
        #expect(draft.time == SourceTime(hour: 9, minute: 30))

        draft.timeZoneIdentifier = "Asia/Manila"
        #expect(draft.source == validSource)
    }

    @Test func validatesGregorianSourceRangesAndKnownTimeZone() throws {
        try validator.validate(
            draft(scheduleChange: .replace(validSchedule)),
            replacementScheduleData: Data()
        )

        for source in [
            SourceWallClock(
                year: 0, month: 8, day: 4, hour: 9, minute: 30, timeZoneIdentifier: "Asia/Manila"),
            SourceWallClock(
                year: 2026, month: 2, day: 30, hour: 9, minute: 30,
                timeZoneIdentifier: "Asia/Manila"),
            SourceWallClock(
                year: 2026, month: 8, day: 4, hour: 24, minute: 0, timeZoneIdentifier: "Asia/Manila"
            ),
            SourceWallClock(
                year: 2026, month: 8, day: 4, hour: 9, minute: 60, timeZoneIdentifier: "Asia/Manila"
            ),
            SourceWallClock(
                year: 2026, month: 8, day: 4, hour: 9, minute: 30, timeZoneIdentifier: "Etc/Unknown"
            )
        ] {
            let schedule = ScheduleDefinition(source: source, rule: .none, end: .never, early: nil)
            #expect(throws: ReminderValidationIssue.invalidSchedule) {
                try validator.validate(draft(scheduleChange: .replace(schedule)))
            }
        }
    }

    @Test func acceptsProlepticGregorianDateInsideHistoricalCutoverGap() throws {
        let source = SourceWallClock(
            year: 1582,
            month: 10,
            day: 10,
            hour: 9,
            minute: 30,
            timeZoneIdentifier: "Asia/Manila"
        )
        let schedule = ScheduleDefinition(source: source, rule: .none, end: .never, early: nil)

        try validator.validate(
            draft(scheduleChange: .replace(schedule)),
            replacementScheduleData: Data()
        )
    }

    @Test func rejectsJulianOnlyLeapDayUnderProlepticGregorianRules() {
        let source = SourceWallClock(
            year: 1500,
            month: 2,
            day: 29,
            hour: 9,
            minute: 30,
            timeZoneIdentifier: "Asia/Manila"
        )
        let schedule = ScheduleDefinition(source: source, rule: .none, end: .never, early: nil)

        #expect(throws: ReminderValidationIssue.invalidSchedule) {
            try validator.validate(draft(scheduleChange: .replace(schedule)))
        }
    }

    @Test func accepts9999RecurrenceIntervalForEveryRuleFamily() throws {
        let rules: [RepeatRule] = [
            .hourly(interval: 9_999),
            .daily(interval: 9_999),
            .weekly(interval: 9_999, weekdaySetKind: .explicit, weekdays: [.monday]),
            .monthly(interval: 9_999, selector: .anchorDay),
            .yearly(interval: 9_999, month: nil, selector: .anchorMonthDay)
        ]

        for rule in rules {
            let schedule = ScheduleDefinition(
                source: validSource, rule: rule, end: .never, early: nil)
            try validator.validate(
                draft(scheduleChange: .replace(schedule)),
                replacementScheduleData: Data()
            )
        }
    }

    @Test func rejects10000RecurrenceIntervalForEveryRuleFamily() {
        let rules: [RepeatRule] = [
            .hourly(interval: 10_000),
            .daily(interval: 10_000),
            .weekly(interval: 10_000, weekdaySetKind: .explicit, weekdays: [.monday]),
            .monthly(interval: 10_000, selector: .anchorDay),
            .yearly(interval: 10_000, month: nil, selector: .anchorMonthDay)
        ]

        for rule in rules {
            let schedule = ScheduleDefinition(
                source: validSource, rule: rule, end: .never, early: nil)
            #expect(throws: ReminderValidationIssue.invalidSchedule) {
                try validator.validate(draft(scheduleChange: .replace(schedule)))
            }
        }
    }

    @Test func rejectsEarlyValueAt10000() {
        let schedule = ScheduleDefinition(
            source: validSource,
            rule: .daily(interval: 1),
            end: .never,
            early: EarlyReminder(value: 10_000, unit: .minutes)
        )

        #expect(throws: ReminderValidationIssue.invalidSchedule) {
            try validator.validate(draft(scheduleChange: .replace(schedule)))
        }
    }

    @Test func enforcesOrdinalDaySetBoundaries() throws {
        for ordinal in [1, 5] {
            let schedule = ScheduleDefinition(
                source: validSource,
                rule: .monthly(
                    interval: 1,
                    selector: .ordinalDaySet(ordinal: ordinal, daySet: .weekday)
                ),
                end: .never,
                early: nil
            )
            try validator.validate(
                draft(scheduleChange: .replace(schedule)),
                replacementScheduleData: Data()
            )
        }

        for ordinal in [0, 6] {
            let schedule = ScheduleDefinition(
                source: validSource,
                rule: .monthly(
                    interval: 1,
                    selector: .ordinalDaySet(ordinal: ordinal, daySet: .weekday)
                ),
                end: .never,
                early: nil
            )
            #expect(throws: ReminderValidationIssue.invalidSchedule) {
                try validator.validate(draft(scheduleChange: .replace(schedule)))
            }
        }
    }

    @Test func enforcesOrdinalWeekdayBoundaries() throws {
        for ordinal in [-5, -1, 1, 5] {
            let schedule = ScheduleDefinition(
                source: validSource,
                rule: .monthly(
                    interval: 1,
                    selector: .ordinalWeekday(ordinal: ordinal, weekday: .monday)
                ),
                end: .never,
                early: nil
            )
            try validator.validate(
                draft(scheduleChange: .replace(schedule)),
                replacementScheduleData: Data()
            )
        }

        for ordinal in [-6, 0, 6] {
            let schedule = ScheduleDefinition(
                source: validSource,
                rule: .monthly(
                    interval: 1,
                    selector: .ordinalWeekday(ordinal: ordinal, weekday: .monday)
                ),
                end: .never,
                early: nil
            )
            #expect(throws: ReminderValidationIssue.invalidSchedule) {
                try validator.validate(draft(scheduleChange: .replace(schedule)))
            }
        }
    }

    @Test func rejectsInvalidRuleSelectorCombinations() {
        let invalidRules: [RepeatRule] = [
            .hourly(interval: 0),
            .weekly(interval: 1, weekdaySetKind: .weekday, weekdays: [.monday, .tuesday]),
            .weekly(interval: 1, weekdaySetKind: .explicit, weekdays: [.tuesday, .monday]),
            .monthly(interval: 1, selector: .anchorMonthDay),
            .yearly(interval: 1, month: nil, selector: .anchorDay),
            .yearly(interval: 1, month: 4, selector: .dayOfMonth(31))
        ]

        for rule in invalidRules {
            let schedule = ScheduleDefinition(
                source: validSource, rule: rule, end: .never, early: nil)
            #expect(throws: ReminderValidationIssue.invalidSchedule) {
                try validator.validate(draft(scheduleChange: .replace(schedule)))
            }
        }
    }

    @Test func validatesEndDateAndEarlyReminderBoundaries() throws {
        let validEnd = SourceDate(year: 2026, month: 8, day: 4)
        let validEarly = EarlyReminder(value: 9_999, unit: .weeks, mainEnabled: false)
        let valid = ScheduleDefinition(
            source: validSource,
            rule: .daily(interval: 1),
            end: .onDate(validEnd),
            early: validEarly
        )
        try validator.validate(
            draft(scheduleChange: .replace(valid)),
            replacementScheduleData: Data()
        )

        let invalidSchedules = [
            ScheduleDefinition(
                source: validSource,
                rule: .none,
                end: .onDate(validEnd),
                early: nil
            ),
            ScheduleDefinition(
                source: validSource,
                rule: .daily(interval: 1),
                end: .onDate(SourceDate(year: 2026, month: 8, day: 3)),
                early: nil
            ),
            ScheduleDefinition(
                source: validSource,
                rule: .daily(interval: 1),
                end: .onDate(SourceDate(year: 2026, month: 2, day: 30)),
                early: nil
            ),
            ScheduleDefinition(
                source: validSource,
                rule: .daily(interval: 1),
                end: .never,
                early: EarlyReminder(value: 0, unit: .minutes, mainEnabled: true)
            )
        ]

        for schedule in invalidSchedules {
            #expect(throws: ReminderValidationIssue.invalidSchedule) {
                try validator.validate(draft(scheduleChange: .replace(schedule)))
            }
        }
    }

    @Test func rejectsNonfiniteAndFractionalMetadataDates() {
        #expect(throws: ReminderValidationIssue.invalidCreatedAt) {
            try validator.validate(
                draft(createdAt: Date(timeIntervalSinceReferenceDate: .infinity)))
        }
        #expect(throws: ReminderValidationIssue.invalidUpdatedAt) {
            try validator.validate(draft(updatedAt: Date(timeIntervalSince1970: 1.5)))
        }
    }

    private let validator = ReminderAggregateValidator()

    private var validSource: SourceWallClock {
        SourceWallClock(
            year: 2026,
            month: 8,
            day: 4,
            hour: 9,
            minute: 30,
            timeZoneIdentifier: "Asia/Manila"
        )
    }

    private var validSchedule: ScheduleDefinition {
        ScheduleDefinition(source: validSource, rule: .none, end: .never, early: nil)
    }

    private func draft(
        title: String = "Tokyo open",
        notes: String? = nil,
        urlString: String? = nil,
        originalScheduleData: Data? = Data(),
        scheduleChange: DraftScheduleChange = .preserveOriginal,
        tagIDs: Set<UUID> = [],
        createdAt: Date = Date(timeIntervalSince1970: 1_786_000_000),
        updatedAt: Date = Date(timeIntervalSince1970: 1_786_000_000)
    ) -> ReminderDraft {
        ReminderDraft(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            title: title,
            notes: notes,
            urlString: urlString,
            enabled: true,
            source: nil,
            rule: .none,
            end: .never,
            early: nil,
            scheduleChange: scheduleChange,
            originalScheduleData: originalScheduleData,
            tagIDs: tagIDs,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func tagIDs(count: Int) -> Set<UUID> {
        Set(
            (0..<count).map { value in
                let suffix = String(format: "%012X", value)
                guard let id = UUID(uuidString: "00000000-0000-0000-0000-\(suffix)") else {
                    preconditionFailure("Generated tag UUID must be valid: \(suffix)")
                }
                return id
            })
    }
}
