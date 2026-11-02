import Foundation
import Testing

@testable import NotificationManagerDomain

@Suite("ReminderStatusTests")
struct ReminderStatusTests {
    @Test func unsupportedSchedulePrecedesDisabledAndExpired() throws {
        let state = try calculator.status(
            schedule: .unsupportedFuture(version: 3, originalData: Data()),
            enabled: false,
            after: now,
            environment: .foundation
        )

        #expect(state.primary == .updateRequired)
        #expect(state.secondary == [.disabled, .expired])
    }

    @Test(arguments: [
        ScheduleReadState.corrupt(originalData: Data()),
        ScheduleReadState.domainInvalid(
            repairSeed: ScheduleRepairSeed(),
            originalData: Data(),
            issues: [.invalidTimeZone]
        )
    ])
    func invalidSchedulePrecedesDisabledAndExpired(_ schedule: ScheduleReadState) throws {
        let state = try calculator.status(
            schedule: schedule,
            enabled: false,
            after: now,
            environment: .foundation
        )

        #expect(state.primary == .invalidSchedule)
        #expect(state.secondary == [.disabled, .expired])
    }

    @Test func disabledPrecedesExpired() throws {
        let state = try calculator.status(
            schedule: validPastSchedule,
            enabled: false,
            after: now,
            environment: .foundation
        )

        #expect(state.primary == .disabled)
        #expect(state.secondary == [.expired])
    }

    @Test func expiredIsPrimaryWhenEnabledWithoutFutureAlert() throws {
        let state = try calculator.status(
            schedule: validPastSchedule,
            enabled: true,
            after: now,
            environment: .foundation
        )

        #expect(state.primary == .expired)
        #expect(state.secondary.isEmpty)
    }

    @Test func activeIsPrimaryOnlyForValidEnabledFutureSchedule() throws {
        let state = try calculator.status(
            schedule: validFutureSchedule,
            enabled: true,
            after: now,
            environment: .foundation
        )

        #expect(state.primary == .active)
        #expect(state.secondary.isEmpty)
    }

    @Test(arguments: [0.0, 1.0, 3_599.0, 3_599.75])
    func oneShotRangeStaysActiveFromStartUntilExclusiveEnd(_ elapsed: TimeInterval) throws {
        let schedule = rangedSchedule()
        let start = Date(timeIntervalSince1970: 1_786_066_200)
        let state = try calculator.status(
            schedule: .valid(schedule, sourceVersion: 3, originalData: Data()),
            enabled: true,
            after: start.addingTimeInterval(elapsed),
            environment: .foundation
        )

        #expect(state.primary == .active)
        #expect(state.secondary.isEmpty)
    }

    @Test func oneShotRangeExpiresExactlyAtEnd() throws {
        let start = Date(timeIntervalSince1970: 1_786_066_200)
        let state = try calculator.status(
            schedule: .valid(rangedSchedule(), sourceVersion: 3, originalData: Data()),
            enabled: true,
            after: start.addingTimeInterval(3_600),
            environment: .foundation
        )

        #expect(state.primary == .expired)
    }

    @Test func finalRecurringRangeRemainsActiveAfterRepeatCutoff() throws {
        let finalStart = Date(timeIntervalSince1970: 1_786_066_200)
        let schedule = rangedSchedule(
            rule: .daily(interval: 1),
            end: .onDate(SourceDate(year: 2026, month: 8, day: 7))
        )
        let state = try calculator.status(
            schedule: .valid(schedule, sourceVersion: 3, originalData: Data()),
            enabled: true,
            after: finalStart.addingTimeInterval(1_800),
            environment: .foundation
        )

        #expect(state.primary == .active)
        #expect(
            try !calculator.hasOngoingRange(
                schedule: schedule,
                at: finalStart.addingTimeInterval(3_600),
                environment: .foundation
            ))
    }

    @Test func disabledOngoingRangeIsDisabledWithoutExpiredSecondary() throws {
        let state = try calculator.status(
            schedule: .valid(rangedSchedule(), sourceVersion: 3, originalData: Data()),
            enabled: false,
            after: Date(timeIntervalSince1970: 1_786_066_200),
            environment: .foundation
        )

        #expect(state.primary == .disabled)
        #expect(state.secondary.isEmpty)
    }

    @Test func malformedRangeRemainsInvalidInsteadOfBecomingActive() throws {
        let state = try calculator.status(
            schedule: .valid(
                rangedSchedule(duration: -60), sourceVersion: 3, originalData: Data()),
            enabled: true,
            after: Date(timeIntervalSince1970: 1_786_066_200),
            environment: .foundation
        )
        #expect(state.primary == .invalidSchedule)
    }

    @Test(arguments: [-300.0, -299.0, 0.0, 360.0, 599.75])
    func explicitLiveActivityWindowKeepsReminderActive(_ elapsed: TimeInterval) throws {
        let schedule = liveActivitySchedule()
        let notification = try SourceWallClockResolver().resolve(
            schedule.source, environment: FoundationRecurrenceEnvironment())
        let evaluation = notification.addingTimeInterval(elapsed)
        #expect(
            try calculator.hasOngoingLiveActivityWindow(
                schedule: schedule, at: evaluation, environment: .foundation))
        let status = try calculator.status(
            schedule: .valid(schedule, sourceVersion: 4, originalData: Data()),
            enabled: true, after: evaluation, environment: .foundation
        )
        #expect(status.primary == .active)
        #expect(status.secondary.isEmpty)
    }

    @Test func explicitLiveActivityWindowHasInclusiveStartAndExclusiveEnd() throws {
        let schedule = liveActivitySchedule()
        let notification = try SourceWallClockResolver().resolve(
            schedule.source, environment: FoundationRecurrenceEnvironment())
        #expect(
            try !calculator.hasOngoingLiveActivityWindow(
                schedule: schedule, at: notification.addingTimeInterval(-301),
                environment: .foundation))
        let end = notification.addingTimeInterval(600)
        #expect(
            try !calculator.hasOngoingLiveActivityWindow(
                schedule: schedule, at: end, environment: .foundation))
        #expect(
            try calculator.status(
                schedule: .valid(schedule, sourceVersion: 4, originalData: Data()),
                enabled: true, after: end, environment: .foundation
            ).primary == .expired)
    }

    @Test func activePostNotificationWindowDoesNotCreateAGhostNotification() throws {
        let schedule = liveActivitySchedule()
        let notification = try SourceWallClockResolver().resolve(
            schedule.source, environment: FoundationRecurrenceEnvironment())
        let evaluation = notification.addingTimeInterval(360)
        let pending = try NextNotificationProvider().nextPhysicalNotifications(
            for: UUID(), schedule: schedule, after: evaluation, environment: .foundation)
        #expect(pending.notifications.isEmpty)
        #expect(pending.exhausted)
        #expect(
            try calculator.status(
                schedule: .valid(schedule, sourceVersion: 4, originalData: Data()),
                enabled: false, after: evaluation, environment: .foundation
            ) == ReminderStatus(primary: .disabled, secondary: []))
    }

    @Test func finalRecurringLiveActivityWindowRemainsActiveAfterRepeatCutoff() throws {
        let schedule = liveActivitySchedule(
            rule: .daily(interval: 1),
            end: .onDate(SourceDate(year: 2026, month: 8, day: 7)))
        let notification = try SourceWallClockResolver().resolve(
            schedule.source, environment: FoundationRecurrenceEnvironment())
        #expect(
            try calculator.status(
                schedule: .valid(schedule, sourceVersion: 4, originalData: Data()),
                enabled: true, after: notification.addingTimeInterval(360), environment: .foundation
            ).primary == .active)
        #expect(
            try calculator.status(
                schedule: .valid(schedule, sourceVersion: 4, originalData: Data()),
                enabled: true, after: notification.addingTimeInterval(600), environment: .foundation
            ).primary == .expired)
    }

    @Test func validScheduleEnvironmentFailurePropagatesWithoutBecomingInvalid() {
        #expect(throws: SourceWallClockResolutionError.unknownTimeZone) {
            try calculator.status(
                schedule: validFutureSchedule,
                enabled: true,
                after: now,
                environment: UnavailableRecurrenceEnvironment()
            )
        }
    }

    private let calculator = ReminderStatusCalculator()
    private let now = Date(timeIntervalSince1970: 1_786_000_000)

    private var validFutureSchedule: ScheduleReadState {
        validSchedule(year: 2026, month: 8, day: 7)
    }

    private var validPastSchedule: ScheduleReadState {
        validSchedule(year: 2026, month: 8, day: 4)
    }

    private func rangedSchedule(
        rule: RepeatRule = .none,
        end: RepeatEnd = .never,
        duration: Int = 3_600
    ) -> ScheduleDefinition {
        ScheduleDefinition(
            source: SourceWallClock(
                year: 2026, month: 8, day: 7, hour: 9, minute: 30,
                timeZoneIdentifier: "Asia/Manila"
            ),
            rule: rule, end: end, early: nil, durationSeconds: duration
        )
    }

    private func liveActivitySchedule(
        rule: RepeatRule = .none,
        end: RepeatEnd = .never
    ) -> ScheduleDefinition {
        ScheduleDefinition(
            source: SourceWallClock(
                year: 2026, month: 8, day: 7, hour: 10, minute: 0,
                timeZoneIdentifier: "Africa/Abidjan"),
            rule: rule, end: end, early: nil,
            liveActivityWindow: LiveActivityWindow(beforeSeconds: 300, afterSeconds: 600)
        )
    }

    private func validSchedule(year: Int, month: Int, day: Int) -> ScheduleReadState {
        .valid(
            ScheduleDefinition(
                source: SourceWallClock(
                    year: year,
                    month: month,
                    day: day,
                    hour: 9,
                    minute: 30,
                    timeZoneIdentifier: "Asia/Manila"
                ),
                rule: .none,
                end: .never,
                early: nil
            ),
            sourceVersion: 1,
            originalData: Data()
        )
    }
}

private struct UnavailableRecurrenceEnvironment: RecurrenceEnvironment {
    func timeZone(identifier: String) -> TimeZone? {
        nil
    }

    func gregorianCalendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
