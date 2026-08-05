import Foundation
import Testing
@testable import NotificationManagerDomain

@Suite("ReminderStatusTests")
struct ReminderStatusTests {
    @Test func unsupportedSchedulePrecedesDisabledAndExpired() {
        let state = calculator.status(
            schedule: .unsupportedFuture(version: 2, originalData: Data()),
            enabled: false,
            hasFutureAlert: false
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
    func invalidSchedulePrecedesDisabledAndExpired(_ schedule: ScheduleReadState) {
        let state = calculator.status(schedule: schedule, enabled: false, hasFutureAlert: false)

        #expect(state.primary == .invalidSchedule)
        #expect(state.secondary == [.disabled, .expired])
    }

    @Test func disabledPrecedesExpired() {
        let state = calculator.status(schedule: validSchedule, enabled: false, hasFutureAlert: false)

        #expect(state.primary == .disabled)
        #expect(state.secondary == [.expired])
    }

    @Test func expiredIsPrimaryWhenEnabledWithoutFutureAlert() {
        let state = calculator.status(schedule: validSchedule, enabled: true, hasFutureAlert: false)

        #expect(state.primary == .expired)
        #expect(state.secondary.isEmpty)
    }

    @Test func activeIsPrimaryOnlyForValidEnabledFutureSchedule() {
        let state = calculator.status(schedule: validSchedule, enabled: true, hasFutureAlert: true)

        #expect(state.primary == .active)
        #expect(state.secondary.isEmpty)
    }

    private let calculator = ReminderStatusCalculator()

    private var validSchedule: ScheduleReadState {
        .valid(
            ScheduleDefinition(
                source: SourceWallClock(
                    year: 2026,
                    month: 8,
                    day: 4,
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
