import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import Testing
import UserNotifications

@testable import NotificationManager

@Suite("Acceptance fixtures")
struct AcceptanceFixtureTests {
    @Test(arguments: [
        MarketFixture(
            localZone: "Asia/Manila",
            daylightHour: 21,
            standardHour: 22
        ),
        MarketFixture(
            localZone: "Asia/Tokyo",
            daylightHour: 22,
            standardHour: 23
        )
    ])
    func newYorkWeekdayOpenTracksDSTAndSourceWeekday(_ fixture: MarketFixture) throws {
        let result = try AcceptanceHarness().weekday0930(fixture)

        #expect(result.daylightLocalHour == fixture.daylightHour)
        #expect(result.daylightLocalMinute == 30)
        #expect(result.standardLocalHour == fixture.standardHour)
        #expect(result.standardLocalMinute == 30)
        #expect(result.weekdayWasEvaluatedInSourceZone)
        #expect(result.materializedSourceTimeZone == "America/New_York")
        #expect(result.materializedWeekday == 2)
        #expect(result.materializedHour == 9)
        #expect(result.materializedMinute == 30)
        #expect(result.triggerRepeats)
    }

    @Test func foundationPoliciesRemainTheRecurrenceAuthority() throws {
        let result = try AcceptanceHarness().foundationPolicies()

        #expect(result.gapInstant == acceptanceDate("2026-03-08T07:30:00Z"))
        #expect(result.firstOverlapInstant == acceptanceDate("2026-11-01T05:30:00Z"))
        #expect(result.nonLeapYearOccurrences.isEmpty)
        #expect(result.nextLeapOccurrence == acceptanceDate("2028-02-29T07:30:00Z"))
        #expect(
            result.hourlyInstants == [
                acceptanceDate("2026-03-08T05:30:00Z"),
                acceptanceDate("2026-03-08T06:30:00Z"),
                acceptanceDate("2026-03-08T07:30:00Z")
            ])
        #expect(result.hourlySourceHours == [0, 1, 3])
    }

    @MainActor
    @Test func alertDerivationKeepsEarlyCollisionSkipAndWarningContracts() throws {
        let result = try AcceptanceHarness().alertPolicies()

        #expect(result.mainOnKinds == [[.early], [.main]])
        #expect(result.mainOffKinds == [[.early]])
        #expect(result.hourlyDayOffset == 86_400)
        #expect(result.hourlyWeekOffset == 604_800)
        #expect(result.collisionKinds == [.main, .early])
        #expect(result.didSkipPastEarly)
        #expect(result.formShowsPastEarlyWarning)
    }

    @Test func expiryCapacityAndDeviceStatusRemainSeparateContracts() throws {
        let result = try AcceptanceHarness().statusPolicies()

        #expect(result.pastOneShotStatus == .expired)
        #expect(result.earliestGroupOutcome == .unscheduledCapacity)
        #expect(result.capacityDeviceStatus == .unscheduledCapacity)
        #expect(result.scheduledDespiteLaterCapacity == .scheduled)
        #expect(result.expiredDeviceStatus == .notApplicable)
    }

    @Test func saveUsesFreshTimeInsteadOfAnEarlierPreview() async throws {
        let requiresConfirmation = await AcceptanceHarness().freshSaveRequiresExpiredConfirmation()

        #expect(requiresConfirmation)
    }
}

struct MarketFixture: Sendable, Equatable {
    let localZone: String
    let daylightHour: Int
    let standardHour: Int
}

private struct Weekday0930AcceptanceResult: Sendable {
    let daylightLocalHour: Int
    let daylightLocalMinute: Int
    let standardLocalHour: Int
    let standardLocalMinute: Int
    let weekdayWasEvaluatedInSourceZone: Bool
    let materializedSourceTimeZone: String?
    let materializedWeekday: Int?
    let materializedHour: Int?
    let materializedMinute: Int?
    let triggerRepeats: Bool
}

private struct FoundationPolicyAcceptanceResult: Sendable {
    let gapInstant: Date
    let firstOverlapInstant: Date
    let nonLeapYearOccurrences: [Date]
    let nextLeapOccurrence: Date?
    let hourlyInstants: [Date]
    let hourlySourceHours: [Int]
}

private struct AlertPolicyAcceptanceResult: Sendable {
    let mainOnKinds: [[AlertKind]]
    let mainOffKinds: [[AlertKind]]
    let hourlyDayOffset: TimeInterval
    let hourlyWeekOffset: TimeInterval
    let collisionKinds: [AlertKind]
    let didSkipPastEarly: Bool
    let formShowsPastEarlyWarning: Bool
}

private struct StatusPolicyAcceptanceResult: Sendable {
    let pastOneShotStatus: LifecycleStatus
    let earliestGroupOutcome: AlertGroupSchedulingOutcome?
    let capacityDeviceStatus: DeviceSchedulingStatus
    let scheduledDespiteLaterCapacity: DeviceSchedulingStatus
    let expiredDeviceStatus: DeviceSchedulingStatus
}

private struct AcceptanceHarness {
    private let reminderID = UUID(uuidString: "123e4567-e89b-12d3-a456-426614174000")!
    private let environment = FoundationRecurrenceEnvironment()

    func weekday0930(_ fixture: MarketFixture) throws -> Weekday0930AcceptanceResult {
        let schedule = ScheduleDefinition(
            source: SourceWallClock(
                year: 2026,
                month: 6,
                day: 1,
                hour: 9,
                minute: 30,
                timeZoneIdentifier: "America/New_York"
            ),
            rule: .weekly(
                interval: 1,
                weekdaySetKind: .weekday,
                weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday]
            ),
            end: .never,
            early: nil
        )
        let daylight = try occurrence(
            schedule: schedule,
            range: date("2026-06-01T00:00:00Z")..<date("2026-06-02T00:00:00Z")
        )
        let standard = try occurrence(
            schedule: schedule,
            range: date("2026-12-07T00:00:00Z")..<date("2026-12-08T00:00:00Z")
        )
        let localCalendar = calendar(timeZoneIdentifier: fixture.localZone)
        let daylightLocal = localCalendar.dateComponents(
            [.hour, .minute],
            from: daylight.instant
        )
        let standardLocal = localCalendar.dateComponents(
            [.hour, .minute],
            from: standard.instant
        )

        let reminder = ReminderSnapshot(
            id: reminderID,
            title: "New York market open",
            notes: nil,
            urlString: nil,
            enabled: true,
            schedule: .valid(schedule, sourceVersion: 1, originalData: Data([1])),
            tagIDs: [],
            createdAt: date("2026-05-01T00:00:00Z"),
            updatedAt: date("2026-05-01T00:00:00Z")
        )
        let evaluationNow = date("2026-06-01T14:00:00Z")
        let plan = try LogicalNotificationPlanner().plan(
            PlannerInput(
                snapshot: CompleteReminderSnapshot(reminders: [reminder], tags: []),
                evaluationNow: evaluationNow,
                deviceNotificationsEnabled: true,
                authorizationAllowsScheduling: true,
                capacity: 60,
                recurrenceEnvironment: environment
            ))
        let repeatingComponents: [RepeatingTriggerComponents] = plan.requests.compactMap {
            guard case .repeating(let components, _) = $0.payload else { return nil }
            return components
        }
        guard
            let mondayRequest = plan.requests.first(where: { request in
                guard case .repeating(let components, _) = request.payload else { return false }
                return components.weekday == 2
            })
        else {
            throw AcceptanceFixtureError.missingMondayRequest
        }
        let materialized = try NotificationRequestMaterializer(
            formatter: AcceptanceNotificationTextFormatter()
        ).materialize(
            mondayRequest,
            input: MaterializationInput(
                reminder: reminder,
                locale: Locale(identifier: "en_US"),
                evaluationNow: evaluationNow,
                recurrenceEnvironment: environment
            )
        )
        guard let trigger = materialized.trigger as? UNCalendarNotificationTrigger else {
            throw AcceptanceFixtureError.unexpectedTrigger
        }

        return Weekday0930AcceptanceResult(
            daylightLocalHour: try required(daylightLocal.hour),
            daylightLocalMinute: try required(daylightLocal.minute),
            standardLocalHour: try required(standardLocal.hour),
            standardLocalMinute: try required(standardLocal.minute),
            weekdayWasEvaluatedInSourceZone: daylight.sourceComponents.weekday == 2
                && standard.sourceComponents.weekday == 2
                && Set(repeatingComponents.compactMap(\.weekday)) == Set(2...6)
                && repeatingComponents.allSatisfy {
                    $0.timeZoneIdentifier == "America/New_York"
                },
            materializedSourceTimeZone: trigger.dateComponents.timeZone?.identifier,
            materializedWeekday: trigger.dateComponents.weekday,
            materializedHour: trigger.dateComponents.hour,
            materializedMinute: trigger.dateComponents.minute,
            triggerRepeats: trigger.repeats
        )
    }

    func foundationPolicies() throws -> FoundationPolicyAcceptanceResult {
        let resolver = SourceWallClockResolver()
        let gap = try resolver.resolve(
            SourceWallClock(
                year: 2026,
                month: 3,
                day: 8,
                hour: 2,
                minute: 30,
                timeZoneIdentifier: "America/New_York"
            ),
            environment: environment
        )
        let overlap = try resolver.resolve(
            SourceWallClock(
                year: 2026,
                month: 11,
                day: 1,
                hour: 1,
                minute: 30,
                timeZoneIdentifier: "America/New_York"
            ),
            environment: environment
        )
        let leapSchedule = ScheduleDefinition(
            source: SourceWallClock(
                year: 2024,
                month: 2,
                day: 29,
                hour: 2,
                minute: 30,
                timeZoneIdentifier: "America/New_York"
            ),
            rule: .yearly(interval: 1, month: nil, selector: .anchorMonthDay),
            end: .never,
            early: nil
        )
        let engine = FoundationRecurrenceEngine()
        let nonLeap = try Array(
            engine.baseOccurrences(
                for: leapSchedule,
                in: date("2025-01-01T00:00:00Z")..<date("2026-01-01T00:00:00Z"),
                environment: environment
            )
        ).map(\.instant)
        let nextLeap = try engine.baseOccurrences(
            for: leapSchedule,
            in: date("2028-02-28T00:00:00Z")..<date("2028-03-02T00:00:00Z"),
            environment: environment
        ).first(where: { _ in true })?.instant

        let hourlySchedule = ScheduleDefinition(
            source: SourceWallClock(
                year: 2026,
                month: 3,
                day: 8,
                hour: 0,
                minute: 30,
                timeZoneIdentifier: "America/New_York"
            ),
            rule: .hourly(interval: 1),
            end: .never,
            early: nil
        )
        let hourly = try Array(
            engine.baseOccurrences(
                for: hourlySchedule,
                in: date("2026-03-08T05:30:00Z")..<date("2026-03-08T08:30:00Z"),
                environment: environment
            ))
        return FoundationPolicyAcceptanceResult(
            gapInstant: gap,
            firstOverlapInstant: overlap,
            nonLeapYearOccurrences: nonLeap,
            nextLeapOccurrence: nextLeap,
            hourlyInstants: hourly.map(\.instant),
            hourlySourceHours: hourly.compactMap(\.sourceComponents.hour)
        )
    }

    @MainActor
    func alertPolicies() throws -> AlertPolicyAcceptanceResult {
        let oneShotSource = SourceWallClock(
            year: 2040,
            month: 8,
            day: 31,
            hour: 13,
            minute: 30,
            timeZoneIdentifier: "Africa/Abidjan"
        )
        let mainOn = try notifications(
            schedule: ScheduleDefinition(
                source: oneShotSource,
                rule: .none,
                end: .never,
                early: EarlyReminder(value: 5, unit: .minutes, mainEnabled: true)
            ),
            after: date("2040-08-31T13:00:00Z"),
            limit: 3
        )
        let mainOff = try notifications(
            schedule: ScheduleDefinition(
                source: oneShotSource,
                rule: .none,
                end: .never,
                early: EarlyReminder(value: 5, unit: .minutes, mainEnabled: false)
            ),
            after: date("2040-08-31T13:00:00Z"),
            limit: 3
        )
        let hourlyDay = try firstEarlyOffset(
            source: SourceWallClock(
                year: 2040,
                month: 8,
                day: 2,
                hour: 13,
                minute: 30,
                timeZoneIdentifier: "Africa/Abidjan"
            ),
            early: EarlyReminder(value: 1, unit: .days, mainEnabled: false),
            after: date("2040-08-01T00:00:00Z")
        )
        let hourlyWeek = try firstEarlyOffset(
            source: SourceWallClock(
                year: 2040,
                month: 8,
                day: 8,
                hour: 13,
                minute: 30,
                timeZoneIdentifier: "Africa/Abidjan"
            ),
            early: EarlyReminder(value: 1, unit: .weeks, mainEnabled: false),
            after: date("2040-08-01T00:00:00Z")
        )
        let collision = try notifications(
            schedule: ScheduleDefinition(
                source: SourceWallClock(
                    year: 2040,
                    month: 8,
                    day: 1,
                    hour: 13,
                    minute: 30,
                    timeZoneIdentifier: "Africa/Abidjan"
                ),
                rule: .daily(interval: 1),
                end: .never,
                early: EarlyReminder(value: 1, unit: .days, mainEnabled: true)
            ),
            after: date("2040-08-02T13:00:00Z"),
            limit: 1
        )
        let skipped = try NextNotificationProvider().nextPhysicalNotifications(
            for: reminderID,
            schedule: ScheduleDefinition(
                source: SourceWallClock(
                    year: 2040,
                    month: 8,
                    day: 1,
                    hour: 13,
                    minute: 30,
                    timeZoneIdentifier: "Africa/Abidjan"
                ),
                rule: .daily(interval: 1),
                end: .never,
                early: EarlyReminder(value: 1, unit: .weeks, mainEnabled: false)
            ),
            after: date("2040-08-06T12:00:00Z"),
            limit: 1,
            environment: environment
        )
        let form = ReminderFormModel(
            newReminderID: reminderID,
            now: date("2040-08-31T13:00:00Z"),
            actions: ReminderFormActions(
                save: { draft, _, _ in .saved(draft.id) },
                delete: { _ in }
            )
        )
        form.title = "Past early warning"
        form.sourceDate = SourceDate(year: 2040, month: 8, day: 31)
        form.sourceTime = SourceTime(hour: 13, minute: 30)
        form.timeZoneIdentifier = "Africa/Abidjan"
        form.earlyReminder = EarlyReminder(value: 60, unit: .minutes)

        return AlertPolicyAcceptanceResult(
            mainOnKinds: mainOn.map { $0.reasons.map(\.kind) },
            mainOffKinds: mainOff.map { $0.reasons.map(\.kind) },
            hourlyDayOffset: hourlyDay,
            hourlyWeekOffset: hourlyWeek,
            collisionKinds: try required(collision.first).reasons.map(\.kind),
            didSkipPastEarly: skipped.didSkipPastEarly,
            formShowsPastEarlyWarning: form.showsPastEarlyWarning
        )
    }

    func statusPolicies() throws -> StatusPolicyAcceptanceResult {
        let pastSchedule = ScheduleDefinition(
            source: SourceWallClock(
                year: 2039,
                month: 1,
                day: 1,
                hour: 9,
                minute: 30,
                timeZoneIdentifier: "America/New_York"
            ),
            rule: .none,
            end: .never,
            early: nil
        )
        let status = try ReminderStatusCalculator().status(
            schedule: .valid(pastSchedule, sourceVersion: 1, originalData: Data([1])),
            enabled: true,
            after: date("2039-12-01T00:00:00Z"),
            environment: environment
        )
        let capacitySchedule = ScheduleDefinition(
            source: SourceWallClock(
                year: 2040,
                month: 6,
                day: 3,
                hour: 9,
                minute: 30,
                timeZoneIdentifier: "America/New_York"
            ),
            rule: .none,
            end: .never,
            early: EarlyReminder(value: 5, unit: .minutes, mainEnabled: true)
        )
        let reminder = ReminderSnapshot(
            id: reminderID,
            title: "Atomic capacity",
            notes: nil,
            urlString: nil,
            enabled: true,
            schedule: .valid(capacitySchedule, sourceVersion: 1, originalData: Data([1])),
            tagIDs: [],
            createdAt: date("2039-12-01T00:00:00Z"),
            updatedAt: date("2039-12-01T00:00:00Z")
        )
        let plan = try LogicalNotificationPlanner().plan(
            PlannerInput(
                snapshot: CompleteReminderSnapshot(reminders: [reminder], tags: []),
                evaluationNow: date("2039-12-01T00:00:00Z"),
                deviceNotificationsEnabled: true,
                authorizationAllowsScheduling: true,
                capacity: 1,
                recurrenceEnvironment: environment
            ))
        let earliestOutcome = plan.outcomes.values.first
        let capacityStatus = DeviceSchedulingStatus.resolve(
            DeviceSchedulingStatusInput(
                lifecycleStatus: .active,
                deviceNotificationsEnabled: true,
                authorization: .allowed,
                earliestGroupOutcome: earliestOutcome,
                laterGroupOutcomes: [],
                reconcileInProgressOrQueued: false,
                earliestRequestPresentOrAddSucceeded: false
            ))
        let laterCapacityStatus = DeviceSchedulingStatus.resolve(
            DeviceSchedulingStatusInput(
                lifecycleStatus: .active,
                deviceNotificationsEnabled: true,
                authorization: .allowed,
                earliestGroupOutcome: .scheduled,
                laterGroupOutcomes: [.unscheduledCapacity],
                reconcileInProgressOrQueued: false,
                earliestRequestPresentOrAddSucceeded: true
            ))
        let expiredDeviceStatus = DeviceSchedulingStatus.resolve(
            DeviceSchedulingStatusInput(
                lifecycleStatus: status.primary,
                deviceNotificationsEnabled: true,
                authorization: .allowed,
                earliestGroupOutcome: nil,
                laterGroupOutcomes: [],
                reconcileInProgressOrQueued: false,
                earliestRequestPresentOrAddSucceeded: false
            ))
        return StatusPolicyAcceptanceResult(
            pastOneShotStatus: status.primary,
            earliestGroupOutcome: earliestOutcome,
            capacityDeviceStatus: capacityStatus,
            scheduledDespiteLaterCapacity: laterCapacityStatus,
            expiredDeviceStatus: expiredDeviceStatus
        )
    }

    func freshSaveRequiresExpiredConfirmation() async -> Bool {
        let alertInstant = date("2040-06-03T13:30:00Z")
        let schedule = ScheduleDefinition(
            source: SourceWallClock(
                year: 2040,
                month: 6,
                day: 3,
                hour: 9,
                minute: 30,
                timeZoneIdentifier: "America/New_York"
            ),
            rule: .none,
            end: .never,
            early: nil
        )
        let draft = ReminderDraft(
            id: reminderID,
            title: "Fresh save boundary",
            scheduleChange: .replace(schedule),
            createdAt: date("2040-06-01T00:00:00Z"),
            updatedAt: date("2040-06-01T00:00:00Z")
        )
        guard
            let outcome = try? await SaveReminderUseCase(
                repository: AcceptanceReminderRepository(),
                scheduleCodec: AcceptanceScheduleCodec(),
                preferenceStore: AcceptancePreferenceStore(),
                authorizationState: { .allowed },
                reconcileRequester: AcceptanceReconcileRequester(),
                now: { alertInstant },
                recurrenceEnvironment: environment
            ).execute(draft: draft)
        else {
            return false
        }
        if case .requiresExpiredScheduleConfirmation = outcome { return true }
        return false
    }

    private func notifications(
        schedule: ScheduleDefinition,
        after: Date,
        limit: Int
    ) throws -> [PhysicalNotification] {
        try NextNotificationProvider().nextPhysicalNotifications(
            for: reminderID,
            schedule: schedule,
            after: after,
            limit: limit,
            environment: environment
        ).notifications
    }

    private func firstEarlyOffset(
        source: SourceWallClock,
        early: EarlyReminder,
        after: Date
    ) throws -> TimeInterval {
        let value = try required(
            notifications(
                schedule: ScheduleDefinition(
                    source: source,
                    rule: .hourly(interval: 1),
                    end: .never,
                    early: early
                ),
                after: after,
                limit: 1
            ).first)
        return value.primaryReason.baseOccurrence.instant.timeIntervalSince(value.alertInstant)
    }

    private func occurrence(
        schedule: ScheduleDefinition,
        range: Range<Date>
    ) throws -> BaseOccurrence {
        guard
            let value = try FoundationRecurrenceEngine()
                .baseOccurrences(for: schedule, in: range, environment: environment)
                .first(where: { _ in true })
        else {
            throw AcceptanceFixtureError.missingOccurrence
        }
        return value
    }

    private func calendar(timeZoneIdentifier: String) -> Calendar {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            preconditionFailure("Invalid acceptance fixture time zone")
        }
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZone
        return value
    }

    private func required(_ value: Int?) throws -> Int {
        guard let value else { throw AcceptanceFixtureError.missingDateComponent }
        return value
    }

    private func required<T>(_ value: T?) throws -> T {
        guard let value else { throw AcceptanceFixtureError.missingValue }
        return value
    }

    private func date(_ value: String) -> Date {
        guard let result = ISO8601DateFormatter().date(from: value) else {
            preconditionFailure("Invalid acceptance fixture date")
        }
        return result
    }
}

private struct AcceptanceNotificationTextFormatter: LocalizedNotificationTextFormatting {
    func content(for input: NotificationTextInput, locale: Locale) -> NotificationText {
        NotificationText(title: input.title, body: "Weekday reminder", ellipsis: "…")
    }
}

private enum AcceptanceFixtureError: Error {
    case missingOccurrence
    case missingMondayRequest
    case unexpectedTrigger
    case missingDateComponent
    case missingValue
    case unsupportedRepositoryOperation
}

private actor AcceptanceReminderRepository: ReminderRepository {
    private var reminders: [UUID: ReminderSnapshot] = [:]

    func fetchCompleteSnapshot() -> CompleteReminderSnapshot {
        CompleteReminderSnapshot(
            reminders: reminders.values.sorted { $0.id.uuidString < $1.id.uuidString },
            tags: []
        )
    }

    func reminder(id: UUID) -> ReminderSnapshot? {
        reminders[id]
    }

    func save(_ mutation: EncodedReminderMutation) throws -> ReminderSnapshot {
        let schedule: ScheduleReadState
        switch mutation.command {
        case .create(let scheduleData), .replaceSchedule(let scheduleData):
            schedule = .corrupt(originalData: scheduleData)
        case .updateMetadataPreservingCurrentSchedule:
            schedule = reminders[mutation.id]?.schedule ?? .corrupt(originalData: Data())
        }
        let reminder = ReminderSnapshot(
            id: mutation.id,
            title: mutation.title,
            notes: mutation.notes,
            urlString: mutation.urlString,
            enabled: mutation.enabled,
            schedule: schedule,
            tagIDs: mutation.tagIDs,
            createdAt: mutation.createdAt,
            updatedAt: mutation.updatedAt
        )
        reminders[reminder.id] = reminder
        return reminder
    }

    func delete(id: UUID) {
        reminders[id] = nil
    }

    func saveTag(_ mutation: EncodedTagMutation) throws -> TagSnapshot {
        throw AcceptanceFixtureError.unsupportedRepositoryOperation
    }

    func deleteTag(id: UUID) throws {
        throw AcceptanceFixtureError.unsupportedRepositoryOperation
    }
}

private struct AcceptanceScheduleCodec: SchedulePayloadCoding {
    func decode(_ data: Data) -> ScheduleReadState {
        .corrupt(originalData: data)
    }

    func encodeCurrent(_ definition: ScheduleDefinition) -> Data {
        Data("acceptance-schedule".utf8)
    }
}

private struct AcceptancePreferenceStore: DeviceNotificationPreferenceStore {
    func isEnabled() async -> Bool { false }

    func setEnabled(_ enabled: Bool) async {}
}

private struct AcceptanceReconcileRequester: ReconcileRequesting {
    func requestReconcile(_ reason: ReconcileReason) async {}
}

private func acceptanceDate(_ value: String) -> Date {
    guard let date = ISO8601DateFormatter().date(from: value) else {
        preconditionFailure("Invalid acceptance date fixture")
    }
    return date
}
