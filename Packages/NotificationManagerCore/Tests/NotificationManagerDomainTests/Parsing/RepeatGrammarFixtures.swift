import NotificationManagerDomain

struct AcceptedRepeatFixture: Sendable {
    let input: String
    let canonical: String
}

enum RepeatGrammarFixtures {
    static let accepted: [AcceptedRepeatFixture] = [
        .init(input: "Every hour", canonical: "Every hour"),
        .init(input: "Every 1 hour", canonical: "Every hour"),
        .init(input: "Every 2 hours", canonical: "Every 2 hours"),
        .init(input: "Every 9999 hours", canonical: "Every 9999 hours"),
        .init(input: "Every day", canonical: "Every day"),
        .init(input: "Every 1 day", canonical: "Every day"),
        .init(input: "Every 2 days", canonical: "Every 2 days"),
        .init(input: "Every week", canonical: "Every Tuesday"),
        .init(input: "Every 1 week", canonical: "Every Tuesday"),
        .init(input: "Every 2 weeks", canonical: "Every 2 weeks"),
        .init(input: "Every Tuesday", canonical: "Every Tuesday"),
        .init(input: "Every Monday and Wednesday", canonical: "Every Monday and Wednesday"),
        .init(input: "Every Mon, Wed, Fri", canonical: "Every Monday, Wednesday, and Friday"),
        .init(input: "Every Mon, Wed and Fri", canonical: "Every Monday, Wednesday, and Friday"),
        .init(input: "Every Mon, Wed, and Fri", canonical: "Every Monday, Wednesday, and Friday"),
        .init(input: "Every Fri, Mon, Wed", canonical: "Every Monday, Wednesday, and Friday"),
        .init(input: "Every Mon,Mon, Monday", canonical: "Every Monday"),
        .init(input: "Every weekday", canonical: "Every weekday"),
        .init(input: "Every weekend", canonical: "Every weekend"),
        .init(input: "Every month", canonical: "Every month"),
        .init(input: "Every 1 month", canonical: "Every month"),
        .init(input: "Every 6 months", canonical: "Every 6 months"),
        .init(input: "Every 9999 months", canonical: "Every 9999 months"),
        .init(input: "Every month on the 4th", canonical: "Every month on the 4th"),
        .init(input: "Every month on 31st", canonical: "Every month on the 31st"),
        .init(input: "Every month on the last day", canonical: "Every month on the last day"),
        .init(input: "Every month on the first weekday", canonical: "Every month on the 1st weekday"),
        .init(input: "Every month on the fifth weekday", canonical: "Every month on the 5th weekday"),
        .init(input: "Every month on the second weekend day", canonical: "Every month on the 2nd weekend day"),
        .init(input: "Every month on the 3rd Tuesday", canonical: "Every month on the 3rd Tuesday"),
        .init(input: "Every month on the fifth Sun", canonical: "Every month on the 5th Sunday"),
        .init(input: "Every month on the last Monday", canonical: "Every month on the last Monday"),
        .init(input: "Every month on the 2nd last Friday", canonical: "Every month on the 2nd last Friday"),
        .init(input: "Every month on the 5th last Sunday", canonical: "Every month on the 5th last Sunday"),
        .init(input: "Every year", canonical: "Every year"),
        .init(input: "Every 1 year", canonical: "Every year"),
        .init(input: "Every 2 years", canonical: "Every 2 years"),
        .init(input: "Every 9999 years", canonical: "Every 9999 years"),
        .init(input: "Every year on the 29th of Feb", canonical: "Every year on the 29th of February"),
        .init(input: "Every year on the last day of January", canonical: "Every year on the last day of January"),
        .init(input: "Every year on the first weekday of January", canonical: "Every year on the 1st weekday of January"),
        .init(input: "Every year on the second weekend day of January", canonical: "Every year on the 2nd weekend day of January"),
        .init(input: "Every year on the 3rd Tue of Mar", canonical: "Every year on the 3rd Tuesday of March"),
        .init(input: "Every year on the last Monday of April", canonical: "Every year on the last Monday of April"),
        .init(input: "Every year on the 5th last Sunday of December", canonical: "Every year on the 5th last Sunday of December"),
        .init(input: "  eVeRy\tthu\r\nAnD\u{000B}Friday  ", canonical: "Every Thursday and Friday")
    ]

    static let rejected: [String] = [
        "", "Every", "After 5 days", "Every weekday until December 31",
        "Every week for 20 times", "Every Thursday at 9:30", "Every Thursday UTC",
        "Every 1 months", "Every 2 month", "Every 2 week", "Every 1 weeks",
        "Every week please", "Every minute", "Every quarter", "Every fortnight",
        "Every 0 days", "Every 01 days", "Every 10000 days", "Every -2 days",
        "Every 2.5 days", "Every 1th day", "Every 2th day",
        "Every month on the 0th", "Every month on the 32nd",
        "Every month on the first", "Every month on the fifth",
        "Every month on the 0th Tuesday", "Every month on the 6th Tuesday",
        "Every month on the 1st last Tuesday", "Every month on the 6th last Tuesday",
        "Every month on the last weekday", "Every month on the second last Tuesday",
        "Every year on the 31st of April", "Every year on the 31st of June",
        "Every year on the 31st of September", "Every year on the 31st of November",
        "Every year on the 30th of February", "Every year on the 32nd of January",
        "Every year on the first of January",
        "Every year on the 1st", "Every year on January", "Every month on the 1st of January",
        "Every Mon Wed", "Every Mon, Wed", "Every Mon, and Wed",
        "Every Mon and Wed and Fri", "Every Mon, Wed Fri", "Every Mon,, Wed",
        "Every Mon and", "Every Mon,", "Every Mon, Wed, and",
        "Every Mon, Tue, Wed, Thu, Fri, Sat, Sun, Mon",
        "Every2 weeks", "Every 2weeks", "Everymonth", "Every week.",
        "Every\u{00A0}week", "Évery week", "Every 月曜日"
    ]
}

extension SourceWallClock {
    static let repeatFixture = SourceWallClock(
        year: 2026,
        month: 8,
        day: 4,
        hour: 9,
        minute: 30,
        timeZoneIdentifier: "Asia/Manila"
    )
}
