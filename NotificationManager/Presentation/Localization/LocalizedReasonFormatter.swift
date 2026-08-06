import Foundation
import NotificationManagerDomain

struct LocalizedReasonFormatter: Sendable {
    func reasons(
        for payload: LogicalNotificationPayload,
        sourceTimeZoneIdentifier: String,
        locale: Locale
    ) -> String {
        switch payload {
        case let .oneShot(_, reasons):
            return oneShotReasons(
                reasons,
                sourceTimeZoneIdentifier: sourceTimeZoneIdentifier,
                locale: locale
            )
        case let .repeating(_, contributors):
            return repeatingReasons(contributors, locale: locale)
        }
    }

    private func oneShotReasons(
        _ reasons: [EffectiveAlert],
        sourceTimeZoneIdentifier: String,
        locale: Locale
    ) -> String {
        let ordered = reasons.enumerated().sorted { lhs, rhs in
            if lhs.element.kind != rhs.element.kind {
                return lhs.element.kind == .main
            }
            if lhs.element.baseOccurrence.instant != rhs.element.baseOccurrence.instant {
                return lhs.element.baseOccurrence.instant < rhs.element.baseOccurrence.instant
            }
            return lhs.offset < rhs.offset
        }.map(\.element)

        return ordered.enumerated().map { index, reason in
            concreteReason(
                reason,
                isPrimary: index == 0,
                sourceTimeZoneIdentifier: sourceTimeZoneIdentifier,
                locale: locale
            )
        }.joined(separator: " ")
    }

    private func concreteReason(
        _ reason: EffectiveAlert,
        isPrimary: Bool,
        sourceTimeZoneIdentifier: String,
        locale: Locale
    ) -> String {
        let components = sourceComponents(
            for: reason.baseOccurrence.instant,
            timeZoneIdentifier: sourceTimeZoneIdentifier
        )
        let year = components.year!
        let month = components.month!
        let day = components.day!
        let hour = components.hour!
        let minute = components.minute!
        if locale.isJapanese {
            let value = String(format: "%d年%d月%d日%02d:%02d", year, month, day, hour, minute)
            switch (reason.kind, isPrimary) {
            case (.main, true): return "\(value)の予定時刻です。"
            case (.main, false): return "さらに、\(value)の予定時刻です。"
            case (.early, true): return "\(value)の早期通知です。"
            case (.early, false): return "さらに、\(value)の早期通知です。"
            }
        }

        let monthNames = [
            "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December"
        ]
        let value = String(
            format: "%@ %d, %d at %02d:%02d",
            monthNames[month - 1], day, year, hour, minute
        )
        switch (reason.kind, isPrimary) {
        case (.main, true): return "At the scheduled time for \(value)."
        case (.main, false): return "Also at the scheduled time for \(value)."
        case (.early, true): return "Early reminder for \(value)."
        case (.early, false): return "Also early for \(value)."
        }
    }

    private func repeatingReasons(
        _ contributors: [RepeatingTriggerContributor],
        locale: Locale
    ) -> String {
        let hasMain = contributors.contains { $0.kind == .main }
        let hasEarly = contributors.contains { $0.kind == .early }
        if locale.isJapanese {
            switch (hasMain, hasEarly) {
            case (true, true): return "予定時刻の通知です。 次回の予定に対する早期通知でもあります。"
            case (true, false): return "予定時刻の通知です。"
            case (false, true): return "次回の予定に対する早期通知です。"
            case (false, false): return ""
            }
        }
        switch (hasMain, hasEarly) {
        case (true, true): return "At the scheduled time. Also early for the next occurrence."
        case (true, false): return "At the scheduled time."
        case (false, true): return "Early reminder for the next occurrence."
        case (false, false): return ""
        }
    }

    private func sourceComponents(
        for instant: Date,
        timeZoneIdentifier: String
    ) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier)!
        return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: instant)
    }
}
