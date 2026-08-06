import Foundation

public struct RepeatingTriggerPlanner: Sendable {
    public init() {}

    public func plan(
        _ input: RepeatingTriggerPlanningInput
    ) -> [RepeatingTriggerCandidate]? {
        let schedule = input.schedule
        guard input.evaluationNow.timeIntervalSinceReferenceDate.isFinite,
              ReminderAggregateValidator().scheduleIssues(for: schedule).isEmpty,
              case .never = schedule.end,
              let timeZone = input.environment.timeZone(
                  identifier: schedule.source.timeZoneIdentifier
              )
        else {
            return nil
        }

        let calendar = input.environment.gregorianCalendar(in: timeZone)
        guard let anchor = try? SourceWallClockResolver().resolve(
            schedule.source,
            calendar: calendar
        ), anchor <= input.evaluationNow,
              !hasObservedCrossOccurrenceCollision(input.physicalNotifications),
              let rulePlan = whitelistedRulePlan(for: schedule)
        else {
            return nil
        }

        var paths: [(components: RepeatingTriggerComponents, contributor: RepeatingTriggerContributor)] = []
        for baseComponents in rulePlan.baseComponents {
            if schedule.early?.mainEnabled != false {
                paths.append((
                    components: baseComponents,
                    contributor: RepeatingTriggerContributor(
                        kind: .main,
                        sourceComponents: baseComponents
                    )
                ))
            }
            if let early = schedule.early {
                guard let earlyComponents = staticEarlyComponents(
                    from: baseComponents,
                    cadence: rulePlan.cadence,
                    early: early,
                    schedule: schedule,
                    calendar: calendar
                ) else {
                    return nil
                }
                paths.append((
                    components: earlyComponents,
                    contributor: RepeatingTriggerContributor(
                        kind: .early,
                        sourceComponents: baseComponents
                    )
                ))
            }
        }

        var candidates: [RepeatingTriggerCandidate] = []
        for path in paths {
            if let index = candidates.firstIndex(where: { $0.components == path.components }) {
                var contributors = candidates[index].contributors
                if !contributors.contains(path.contributor) {
                    // Equal direct triggers from different occurrence paths require collision
                    // grouping, which is intentionally outside the direct-repeat whitelist.
                    return nil
                }
                contributors = sortedContributors(contributors)
                candidates[index] = RepeatingTriggerCandidate(
                    components: path.components,
                    contributors: contributors
                )
            } else {
                candidates.append(RepeatingTriggerCandidate(
                    components: path.components,
                    contributors: [path.contributor]
                ))
            }
        }

        return candidates.sorted {
            componentSortKey($0.components) < componentSortKey($1.components)
        }
    }

    private func whitelistedRulePlan(for schedule: ScheduleDefinition) -> RulePlan? {
        let source = schedule.source
        let zone = source.timeZoneIdentifier
        let time = (source.hour, source.minute)

        switch schedule.rule {
        case .daily(interval: 1):
            return RulePlan(cadence: .daily, baseComponents: [
                trigger(zone: zone, hour: time.0, minute: time.1)
            ])
        case let .weekly(interval: 1, _, weekdays):
            return RulePlan(cadence: .weekly, baseComponents: weekdays.map {
                trigger(
                    zone: zone,
                    weekday: foundationWeekday($0),
                    hour: time.0,
                    minute: time.1
                )
            })
        case let .monthly(interval: 1, selector):
            let day: Int
            switch selector {
            case .anchorDay:
                day = source.day
            case let .dayOfMonth(fixedDay):
                day = fixedDay
            default:
                return nil
            }
            return RulePlan(cadence: .monthly, baseComponents: [
                trigger(zone: zone, day: day, hour: time.0, minute: time.1)
            ])
        case let .yearly(interval: 1, month, selector):
            let fixedMonth: Int
            let fixedDay: Int
            switch (month, selector) {
            case (nil, .anchorMonthDay):
                fixedMonth = source.month
                fixedDay = source.day
            case let (.some(value), .dayOfMonth(day)):
                fixedMonth = value
                fixedDay = day
            default:
                return nil
            }
            return RulePlan(cadence: .yearly, baseComponents: [
                trigger(
                    zone: zone,
                    month: fixedMonth,
                    day: fixedDay,
                    hour: time.0,
                    minute: time.1
                )
            ])
        default:
            return nil
        }
    }

    private func staticEarlyComponents(
        from base: RepeatingTriggerComponents,
        cadence: Cadence,
        early: EarlyReminder,
        schedule: ScheduleDefinition,
        calendar: Calendar
    ) -> RepeatingTriggerComponents? {
        var result: RepeatingTriggerComponents?
        for source in representativeSources(
            cadence: cadence,
            base: base,
            originalSource: schedule.source
        ) {
            guard let baseInstant = try? SourceWallClockResolver().resolve(
                source,
                calendar: calendar
            ), let alertInstant = try? earlyAlertInstant(
                for: baseInstant,
                early: early,
                rule: schedule.rule,
                calendar: calendar
            ), let components = normalizedComponents(
                of: alertInstant,
                cadence: cadence,
                timeZoneIdentifier: base.timeZoneIdentifier,
                calendar: calendar
            ) else {
                return nil
            }
            if let result, result != components { return nil }
            result = components
        }
        return result
    }

    private func representativeSources(
        cadence: Cadence,
        base: RepeatingTriggerComponents,
        originalSource: SourceWallClock
    ) -> [SourceWallClock] {
        var sources: [SourceWallClock] = []
        let years: Range<Int> = switch cadence {
        case .daily, .weekly:
            // Daily/weekly output has no month/day field. A complete 28-year
            // Gregorian weekday/leap cycle exposes every projected transition
            // weekday alignment while keeping reconcile-time planning bounded.
            2_020..<2_048
        case .monthly, .yearly:
            // Month/day output must also survive the full Gregorian leap cycle.
            2_000..<2_400
        }

        for year in years {
            for month in 1...12 {
                if cadence == .yearly, month != base.month { continue }
                let maximumDay = maximumGregorianDay(year: year, month: month)
                for day in 1...maximumDay {
                    switch cadence {
                    case .daily:
                        break
                    case .weekly:
                        guard gregorianWeekday(year: year, month: month, day: day)
                            == base.weekday else { continue }
                    case .monthly:
                        guard day == base.day else { continue }
                    case .yearly:
                        guard day == base.day else { continue }
                    }
                    sources.append(SourceWallClock(
                        year: year,
                        month: month,
                        day: day,
                        hour: originalSource.hour,
                        minute: originalSource.minute,
                        timeZoneIdentifier: originalSource.timeZoneIdentifier
                    ))
                }
            }
        }
        return sources
    }

    private func normalizedComponents(
        of instant: Date,
        cadence: Cadence,
        timeZoneIdentifier: String,
        calendar: Calendar
    ) -> RepeatingTriggerComponents? {
        let values = calendar.dateComponents(
            [.month, .day, .weekday, .hour, .minute, .second],
            from: instant
        )
        guard let hour = values.hour,
              let minute = values.minute,
              values.second == 0
        else {
            return nil
        }
        switch cadence {
        case .daily:
            return trigger(zone: timeZoneIdentifier, hour: hour, minute: minute)
        case .weekly:
            guard let weekday = values.weekday else { return nil }
            return trigger(
                zone: timeZoneIdentifier,
                weekday: weekday,
                hour: hour,
                minute: minute
            )
        case .monthly:
            guard let day = values.day else { return nil }
            return trigger(
                zone: timeZoneIdentifier,
                day: day,
                hour: hour,
                minute: minute
            )
        case .yearly:
            guard let month = values.month, let day = values.day else { return nil }
            return trigger(
                zone: timeZoneIdentifier,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        }
    }

    private func hasObservedCrossOccurrenceCollision(
        _ notifications: [PhysicalNotification]
    ) -> Bool {
        notifications.contains { notification in
            var occurrenceInstants: [Date] = []
            for reason in notification.reasons
                where !occurrenceInstants.contains(reason.baseOccurrence.instant)
            {
                occurrenceInstants.append(reason.baseOccurrence.instant)
            }
            return occurrenceInstants.count > 1
        }
    }

    private func sortedContributors(
        _ contributors: [RepeatingTriggerContributor]
    ) -> [RepeatingTriggerContributor] {
        contributors.sorted {
            let lhsKind = $0.kind == .main ? 0 : 1
            let rhsKind = $1.kind == .main ? 0 : 1
            if lhsKind != rhsKind { return lhsKind < rhsKind }
            return componentSortKey($0.sourceComponents)
                < componentSortKey($1.sourceComponents)
        }
    }

    private func componentSortKey(_ components: RepeatingTriggerComponents) -> String {
        let month = components.month.map { String(format: "%02d", $0) } ?? "--"
        let day = components.day.map { String(format: "%02d", $0) } ?? "--"
        let weekday = components.weekday.map(String.init) ?? "-"
        return "\(components.timeZoneIdentifier)|\(month)|\(day)|\(weekday)|"
            + String(format: "%02d:%02d:%02d", components.hour, components.minute, components.second)
    }

    private func trigger(
        zone: String,
        month: Int? = nil,
        day: Int? = nil,
        weekday: Int? = nil,
        hour: Int,
        minute: Int
    ) -> RepeatingTriggerComponents {
        RepeatingTriggerComponents(
            timeZoneIdentifier: zone,
            month: month,
            day: day,
            weekday: weekday,
            hour: hour,
            minute: minute,
            second: 0
        )
    }

    private func foundationWeekday(_ weekday: Weekday) -> Int {
        weekday == .sunday ? 1 : weekday.rawValue + 1
    }

    private func gregorianWeekday(year: Int, month: Int, day: Int) -> Int? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: 12
        )) else {
            return nil
        }
        return calendar.component(.weekday, from: date)
    }

    private func maximumGregorianDay(year: Int, month: Int) -> Int {
        switch month {
        case 2:
            let leap = year.isMultiple(of: 4)
                && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
            return leap ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }
}

private struct RulePlan {
    let cadence: Cadence
    let baseComponents: [RepeatingTriggerComponents]
}

private enum Cadence: Equatable {
    case daily
    case weekly
    case monthly
    case yearly
}
