import Foundation
import NotificationManagerDomain

struct LocalizedReasonFormatter: Sendable {
    private let localizer: LocalizedTextProvider

    init(localizer: LocalizedTextProvider = .live) {
        self.localizer = localizer
    }

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
        let key = switch (reason.kind, isPrimary) {
        case (.main, true): "localization.reason.one-shot.main.primary"
        case (.main, false): "localization.reason.one-shot.main.secondary"
        case (.early, true): "localization.reason.one-shot.early.primary"
        case (.early, false): "localization.reason.one-shot.early.secondary"
        }
        return format(
            key,
            locale: locale,
            localizedSourceDate(
                reason.baseOccurrence.instant,
                sourceTimeZoneIdentifier: sourceTimeZoneIdentifier,
                locale: locale
            )
        )
    }

    private func repeatingReasons(
        _ contributors: [RepeatingTriggerContributor],
        locale: Locale
    ) -> String {
        let hasMain = contributors.contains { $0.kind == .main }
        let hasEarly = contributors.contains { $0.kind == .early }
        guard hasMain || hasEarly else { return "" }
        let key = switch (hasMain, hasEarly) {
        case (true, true): "localization.reason.repeating.main-and-early"
        case (true, false): "localization.reason.repeating.main"
        case (false, true): "localization.reason.repeating.early"
        case (false, false): preconditionFailure("Handled by the empty contributor guard")
        }
        return localizer.value(for: key, locale: locale)
    }

    private func localizedSourceDate(
        _ instant: Date,
        sourceTimeZoneIdentifier: String,
        locale: Locale
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: sourceTimeZoneIdentifier) ?? .gmt
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: instant)
    }

    private func format(_ key: String, locale: Locale, _ arguments: CVarArg...) -> String {
        String(
            format: localizer.value(for: key, locale: locale),
            locale: locale,
            arguments: arguments
        )
    }
}
