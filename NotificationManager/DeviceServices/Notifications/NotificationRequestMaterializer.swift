import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import UserNotifications

public struct MaterializationInput: Sendable {
    public let reminder: ReminderSnapshot
    public let locale: Locale
    public let evaluationNow: Date
    public let recurrenceEnvironment: any RecurrenceEnvironment

    public init(
        reminder: ReminderSnapshot,
        locale: Locale,
        evaluationNow: Date,
        recurrenceEnvironment: any RecurrenceEnvironment
    ) {
        self.reminder = reminder
        self.locale = locale
        self.evaluationNow = evaluationNow
        self.recurrenceEnvironment = recurrenceEnvironment
    }
}

public enum NotificationRequestMaterializationError: Error, Sendable, Equatable {
    case reminderIDMismatch
    case invalidSchedule
    case invalidContributingGroups
    case invalidOneShotAlertInstant
    case invalidOneShotReasons
    case invalidRepeatingComponents
    case invalidRepeatingContributors
    case logicalContributorMismatch
    case duplicateLogicalContributors
    case reasonKindNotAllowed
    case oneShotPayloadNotDerivable
    case repeatingPayloadNotDerivable
    case identifierDoesNotMatchPayload
    case oneShotTriggerDateMismatch
    case repeatingTriggerHasNoNextDate
}

public struct NotificationRequestMaterializer: Sendable {
    private static let reminderIDKey = "notification-manager.reminder-id"
    private static let openLinkCategoryIdentifier = "notification-manager.open-link"

    private let formatter: any LocalizedNotificationTextFormatting
    private let truncator: NotificationContentTruncator
    private let triggerDateVerifier: @Sendable (UNCalendarNotificationTrigger, Date) -> Bool

    public init() {
        formatter = LocalizedNotificationTextFormatter()
        truncator = NotificationContentTruncator()
        triggerDateVerifier = { trigger, expectedDate in
            trigger.nextTriggerDate() == expectedDate
        }
    }

    public init(formatter: any LocalizedNotificationTextFormatting) {
        self.formatter = formatter
        truncator = NotificationContentTruncator()
        triggerDateVerifier = { trigger, expectedDate in
            trigger.nextTriggerDate() == expectedDate
        }
    }

    init(
        triggerDateVerifier: @escaping @Sendable (UNCalendarNotificationTrigger, Date) -> Bool
    ) {
        formatter = LocalizedNotificationTextFormatter()
        truncator = NotificationContentTruncator()
        self.triggerDateVerifier = triggerDateVerifier
    }

    public func materialize(
        _ request: LogicalNotificationRequest,
        input: MaterializationInput
    ) throws -> UNNotificationRequest {
        guard request.reminderID == input.reminder.id else {
            throw NotificationRequestMaterializationError.reminderIDMismatch
        }
        guard case let .valid(schedule, _, _) = input.reminder.schedule,
              ReminderAggregateValidator().scheduleIssues(for: schedule).isEmpty
        else {
            throw NotificationRequestMaterializationError.invalidSchedule
        }
        try validatePayloadShape(request.payload, schedule: schedule)
        do {
            try LogicalNotificationRequestValidator().validate(
                request,
                for: input.reminder,
                context: LogicalNotificationRequestValidationContext(
                    evaluationNow: input.evaluationNow,
                    recurrenceEnvironment: input.recurrenceEnvironment
                )
            )
        } catch let error as LogicalNotificationRequestValidationError {
            throw materializationError(for: error)
        }

        let trigger = try notificationTrigger(
            for: request,
            schedule: schedule
        )
        let text = formatter.content(
            for: NotificationTextInput(
                title: input.reminder.title,
                notes: input.reminder.notes,
                schedule: schedule,
                payload: request.payload
            ),
            locale: input.locale
        )

        let content = UNMutableNotificationContent()
        content.title = truncator.truncate(text.title, maximumBytes: 256, ellipsis: text.ellipsis)
        content.body = truncator.truncate(text.body, maximumBytes: 2_048, ellipsis: text.ellipsis)
        content.sound = .default
        content.interruptionLevel = .active
        content.userInfo = [
            Self.reminderIDKey: request.reminderID.uuidString.lowercased()
        ]
        if input.reminder.urlString != nil {
            content.categoryIdentifier = Self.openLinkCategoryIdentifier
        }

        return UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: trigger
        )
    }

    private func notificationTrigger(
        for request: LogicalNotificationRequest,
        schedule: ScheduleDefinition
    ) throws -> UNCalendarNotificationTrigger {
        switch request.payload {
        case let .oneShot(alertInstant, reasons):
            return try oneShotTrigger(
                request: request,
                alertInstant: alertInstant,
                reasons: reasons
            )
        case let .repeating(components, contributors):
            return try repeatingTrigger(
                request: request,
                schedule: schedule,
                components: components,
                contributors: contributors
            )
        }
    }

    private func validatePayloadShape(
        _ payload: LogicalNotificationPayload,
        schedule: ScheduleDefinition
    ) throws {
        switch payload {
        case let .oneShot(alertInstant, reasons):
            guard isFiniteIntegralSecond(alertInstant) else {
                throw NotificationRequestMaterializationError.invalidOneShotAlertInstant
            }
            guard !reasons.isEmpty,
                  reasons.allSatisfy({
                      $0.alertInstant == alertInstant
                          && isFiniteIntegralSecond($0.baseOccurrence.instant)
                  })
            else {
                throw NotificationRequestMaterializationError.invalidOneShotReasons
            }
        case let .repeating(components, contributors):
            guard (try? components.validated()) != nil,
                  components.timeZoneIdentifier == schedule.source.timeZoneIdentifier
            else {
                throw NotificationRequestMaterializationError.invalidRepeatingComponents
            }
            guard !contributors.isEmpty,
                  contributors.allSatisfy({
                      (try? $0.sourceComponents.validated()) != nil
                          && $0.sourceComponents.timeZoneIdentifier
                              == schedule.source.timeZoneIdentifier
                  })
            else {
                throw NotificationRequestMaterializationError.invalidRepeatingContributors
            }
        }
    }

    private func oneShotTrigger(
        request: LogicalNotificationRequest,
        alertInstant: Date,
        reasons: [EffectiveAlert]
    ) throws -> UNCalendarNotificationTrigger {
        guard isFiniteIntegralSecond(alertInstant) else {
            throw NotificationRequestMaterializationError.invalidOneShotAlertInstant
        }
        guard !reasons.isEmpty,
              reasons.allSatisfy({
                  $0.alertInstant == alertInstant
                      && isFiniteIntegralSecond($0.baseOccurrence.instant)
              })
        else {
            throw NotificationRequestMaterializationError.invalidOneShotReasons
        }
        guard (try? NotificationIdentifierCodec().oneShotIdentifier(
            reminderID: request.reminderID,
            alertInstant: alertInstant
        )) == request.identifier else {
            throw NotificationRequestMaterializationError.identifierDoesNotMatchPayload
        }

        let utc = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: alertInstant
        )
        guard let year = components.year, (1...9_999).contains(year) else {
            throw NotificationRequestMaterializationError.invalidOneShotAlertInstant
        }
        components.calendar = calendar
        components.timeZone = utc
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )
        guard triggerDateVerifier(trigger, alertInstant) else {
            throw NotificationRequestMaterializationError.oneShotTriggerDateMismatch
        }
        return trigger
    }

    private func repeatingTrigger(
        request: LogicalNotificationRequest,
        schedule: ScheduleDefinition,
        components: RepeatingTriggerComponents,
        contributors: [RepeatingTriggerContributor]
    ) throws -> UNCalendarNotificationTrigger {
        guard (try? components.validated()) != nil,
              components.timeZoneIdentifier == schedule.source.timeZoneIdentifier
        else {
            throw NotificationRequestMaterializationError.invalidRepeatingComponents
        }
        guard !contributors.isEmpty,
              contributors.allSatisfy({
                  (try? $0.sourceComponents.validated()) != nil
                      && $0.sourceComponents.timeZoneIdentifier == schedule.source.timeZoneIdentifier
              })
        else {
            throw NotificationRequestMaterializationError.invalidRepeatingContributors
        }
        guard (try? NotificationIdentifierCodec().repeatingIdentifier(
            reminderID: request.reminderID,
            components: components
        )) == request.identifier else {
            throw NotificationRequestMaterializationError.identifierDoesNotMatchPayload
        }

        let timeZone = TimeZone(identifier: components.timeZoneIdentifier)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var dateComponents = DateComponents()
        dateComponents.calendar = calendar
        dateComponents.timeZone = timeZone
        dateComponents.month = components.month
        dateComponents.day = components.day
        dateComponents.weekday = components.weekday
        dateComponents.hour = components.hour
        dateComponents.minute = components.minute
        dateComponents.second = components.second
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: true
        )
        guard trigger.nextTriggerDate() != nil else {
            throw NotificationRequestMaterializationError.repeatingTriggerHasNoNextDate
        }
        return trigger
    }

    private func isFiniteIntegralSecond(_ date: Date) -> Bool {
        let seconds = date.timeIntervalSince1970
        return seconds.isFinite && seconds.rounded(.towardZero) == seconds
    }

    private func materializationError(
        for error: LogicalNotificationRequestValidationError
    ) -> NotificationRequestMaterializationError {
        switch error {
        case .reminderIDMismatch:
            .reminderIDMismatch
        case .invalidSchedule:
            .invalidSchedule
        case .invalidContributingGroups:
            .invalidContributingGroups
        case .contributorIdentityMismatch:
            .logicalContributorMismatch
        case .duplicateContributors:
            .duplicateLogicalContributors
        case .reasonKindNotAllowed:
            .reasonKindNotAllowed
        case .oneShotAlertNotDerivable:
            .oneShotPayloadNotDerivable
        case .repeatingPayloadNotDerivable:
            .repeatingPayloadNotDerivable
        }
    }
}

private struct LocalizedNotificationTextFormatter: LocalizedNotificationTextFormatting {
    private let repeatFormatter = LocalizedRepeatFormatter()
    private let reasonFormatter = LocalizedReasonFormatter()
    private let localizer = LocalizedTextProvider.live

    func content(for input: NotificationTextInput, locale: Locale) -> NotificationText {
        let primary = input.notes ?? repeatFormatter.summary(for: input.schedule, locale: locale)
        let source = repeatFormatter.sourceTime(for: input.schedule.source, locale: locale)
        let reasons = reasonFormatter.reasons(
            for: input.payload,
            sourceTimeZoneIdentifier: input.schedule.source.timeZoneIdentifier,
            locale: locale
        )
        let body = String(
            format: localizer.value(for: "localization.notification.body", locale: locale),
            locale: locale,
            arguments: [primary, source, reasons]
        )
        return NotificationText(
            title: input.title,
            body: body,
            ellipsis: "…"
        )
    }
}
