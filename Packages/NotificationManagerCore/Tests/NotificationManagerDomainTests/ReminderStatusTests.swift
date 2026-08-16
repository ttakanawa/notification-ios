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
