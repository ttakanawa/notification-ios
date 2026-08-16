import NotificationManagerDomain

enum EarlyReminderAmountOptions {
    static func standardRange(for unit: EarlyReminderUnit) -> ClosedRange<Int> {
        switch unit {
        case .seconds, .minutes: 1...59
        case .hours: 1...23
        case .days: 1...30
        case .weeks: 1...52
        }
    }

    static func values(for early: EarlyReminder) -> [Int] {
        let range = standardRange(for: early.unit)
        guard !range.contains(early.value) else { return Array(range) }
        return (Array(range) + [early.value]).sorted()
    }

    static func clamped(_ value: Int, for unit: EarlyReminderUnit) -> Int {
        let range = standardRange(for: unit)
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
