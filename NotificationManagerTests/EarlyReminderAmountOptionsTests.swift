import NotificationManagerDomain
import Testing

@testable import NotificationManager

struct EarlyReminderAmountOptionsTests {
    @Test func rangesAreUnitSpecificAndIncrementByOne() {
        let fixtures: [(EarlyReminderUnit, ClosedRange<Int>)] = [
            (.seconds, 1...59),
            (.minutes, 1...59),
            (.hours, 1...23),
            (.days, 1...30),
            (.weeks, 1...52)
        ]

        for (unit, expected) in fixtures {
            #expect(EarlyReminderAmountOptions.standardRange(for: unit) == expected)
            #expect(
                EarlyReminderAmountOptions.values(
                    for: EarlyReminder(value: expected.lowerBound, unit: unit)
                ) == Array(expected))
        }
    }

    @Test func existingOutOfRangeValueIsPreservedAndUnitChangeClamps() {
        let legacy = EarlyReminder(value: 90, unit: .minutes)

        #expect(EarlyReminderAmountOptions.values(for: legacy).last == 90)
        #expect(EarlyReminderAmountOptions.clamped(59, for: .hours) == 23)
        #expect(EarlyReminderAmountOptions.clamped(0, for: .seconds) == 1)
    }
}
