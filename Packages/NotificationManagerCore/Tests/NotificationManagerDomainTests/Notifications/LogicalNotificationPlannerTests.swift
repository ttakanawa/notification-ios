import Foundation
import Testing

@testable import NotificationManagerDomain

@Suite("Notifications.LogicalNotificationPlanner")
struct LogicalNotificationPlannerTests {
    @Test func allocatesEveryReminderEarliestGroupBeforeLaterGroups() throws {
        let plan = try planner.plan(
            input(
                reminders: [
                    reminder("00000000-0000-0000-0000-00000000000A", hour: 13, interval: 1),
                    reminder("00000000-0000-0000-0000-00000000000B", hour: 14, interval: 24),
                    reminder("00000000-0000-0000-0000-00000000000C", hour: 15, interval: 24)
                ],
                capacity: 4
            ))

        #expect(
            plan.selectedGroupIDs == [
                group("00000000-0000-0000-0000-00000000000A", "2026-08-06T13:00:00Z"),
                group("00000000-0000-0000-0000-00000000000B", "2026-08-06T14:00:00Z"),
                group("00000000-0000-0000-0000-00000000000C", "2026-08-06T15:00:00Z"),
                group("00000000-0000-0000-0000-00000000000A", "2026-08-06T14:00:00Z")
            ])
    }

    @Test func doesNotSplitTwoRequestAlertGroupWhenOneSlotRemains() throws {
        let value = reminder(
            "00000000-0000-0000-0000-00000000000A",
            hour: 13,
            interval: 24,
            early: EarlyReminder(value: 5, unit: .minutes)
        )

        let plan = try planner.plan(input(reminders: [value], capacity: 1))
        let groupID = group(value.id, "2026-08-06T13:00:00Z")

        #expect(plan.outcomes[groupID] == .unscheduledCapacity)
        #expect(plan.requests.isEmpty)
        #expect(plan.selectedGroupIDs.isEmpty)
    }

    @Test func tieBreaksByLowercaseUUIDThenBaseOccurrence() throws {
        let laterUUID = reminder("FFFFFFFF-0000-0000-0000-000000000000", hour: 13, interval: 24)
        let earlierUUID = reminder("0AAAAAAA-0000-0000-0000-000000000000", hour: 13, interval: 24)

        let plan = try planner.plan(input(reminders: [laterUUID, earlierUUID], capacity: 1))

        #expect(plan.selectedGroupIDs == [group(earlierUUID.id, "2026-08-06T13:00:00Z")])
        #expect(plan.outcomes[group(laterUUID.id, "2026-08-06T13:00:00Z")] == .unscheduledCapacity)
    }

    @Test func collisionMergeChargesDistinctIdentifiersAndKeepsContributorSets() throws {
        let value = reminder(
            "00000000-0000-0000-0000-00000000000A",
            hour: 13,
            interval: 24,
            early: EarlyReminder(value: 24, unit: .hours)
        )

        let plan = try planner.plan(input(reminders: [value], capacity: 2))
        let collision = try #require(
            plan.requests.first(where: {
                $0.oneShotAlertInstant == date("2026-08-06T13:00:00Z")
            }))

        #expect(plan.selectedGroupIDs.count == 2)
        #expect(plan.requests.count == 2)
        #expect(
            collision.contributingGroupIDs
                == Set([
                    group(value.id, "2026-08-06T13:00:00Z"),
                    group(value.id, "2026-08-07T13:00:00Z")
                ]))
        #expect(collision.oneShotReasons.count == 2)
    }

    @Test func duplicateSnapshotReminderCannotInflateCostOrOutcomes() throws {
        let value = reminder("00000000-0000-0000-0000-00000000000A", hour: 13, interval: 24)
        let plan = try planner.plan(input(reminders: [value, value], capacity: 1))
        let single = try planner.plan(input(reminders: [value], capacity: 1))

        #expect(plan == single)
    }

    @Test func replacesBaselineOnlyWhenEntireRepeatingCollectionFits() throws {
        let repeatable = weekdayReminder(
            "00000000-0000-0000-0000-00000000000A",
            hour: 13
        )

        let fits = try planner.plan(input(reminders: [repeatable], capacity: 5))
        let cannotFit = try planner.plan(input(reminders: [repeatable], capacity: 1))

        #expect(fits.requests.count == 5)
        #expect(fits.requests.allSatisfy { $0.isRepeating })
        #expect(fits.scheduledThrough[repeatable.id] == nil)
        #expect(cannotFit.requests.count == 1)
        #expect(
            try #require(cannotFit.requests.first).oneShotAlertInstant
                == date("2026-08-06T13:00:00Z"))
        #expect(cannotFit.scheduledThrough[repeatable.id] == date("2026-08-06T13:00:00Z"))
    }

    @Test func repeatingPreparationFailureKeepsBaselineAndUnrelatedReminder() throws {
        let failing = weekdayReminder(
            "00000000-0000-0000-0000-00000000000A",
            hour: 13
        )
        let unrelated = reminder(
            "00000000-0000-0000-0000-00000000000B",
            hour: 13,
            minute: 30,
            interval: 24
        )
        let failingID = failing.id
        let planner = LogicalNotificationPlanner(
            dependencies: .init { point, reminderID in
                if point == .repeatingReplacement, reminderID == failingID {
                    throw InjectedPlannerFailure.expected
                }
            })

        let plan = try planner.plan(input(reminders: [failing, unrelated], capacity: 3))

        #expect(plan.outcomes[group(failing.id, "2026-08-06T13:00:00Z")] == .scheduled)
        #expect(
            plan.requests.contains {
                $0.reminderID == failing.id
                    && !$0.isRepeating
                    && $0.oneShotAlertInstant == date("2026-08-06T13:00:00Z")
            })
        #expect(plan.requests.contains { $0.reminderID == unrelated.id })
        #expect(plan.requests.allSatisfy { !$0.isRepeating })
        #expect(plan.scheduledThrough[failing.id] == date("2026-08-06T13:00:00Z"))
    }

    @Test func initialContinuationFailureRetiresOnlyFailingReminder() throws {
        let failing = reminder(
            "00000000-0000-0000-0000-00000000000A",
            hour: 13,
            interval: 1
        )
        let unrelated = reminder(
            "00000000-0000-0000-0000-00000000000B",
            hour: 13,
            minute: 30,
            interval: 1
        )
        let failingID = failing.id
        let planner = LogicalNotificationPlanner(
            dependencies: .init { point, reminderID in
                if point == .initialContinuation, reminderID == failingID {
                    throw InjectedPlannerFailure.expected
                }
            })

        let plan = try planner.plan(input(reminders: [failing, unrelated], capacity: 3))

        #expect(plan.outcomes[group(failing.id, "2026-08-06T13:00:00Z")] == .scheduled)
        #expect(plan.outcomes[group(unrelated.id, "2026-08-06T14:30:00Z")] == .scheduled)
        #expect(plan.scheduledThrough[failing.id] == date("2026-08-06T13:00:00Z"))
        #expect(plan.scheduledThrough[unrelated.id] == date("2026-08-06T14:30:00Z"))
    }

    @Test func postAcceptanceAdvanceFailureCannotRewriteAcceptedOutcome() throws {
        let failing = reminder(
            "00000000-0000-0000-0000-00000000000A",
            hour: 13,
            interval: 1
        )
        let unrelated = reminder(
            "00000000-0000-0000-0000-00000000000B",
            hour: 13,
            minute: 30,
            interval: 1
        )
        let failingID = failing.id
        let planner = LogicalNotificationPlanner(
            dependencies: .init { point, reminderID in
                if point == .acceptedContinuationAdvance, reminderID == failingID {
                    throw InjectedPlannerFailure.expected
                }
            })
        let acceptedID = group(failing.id, "2026-08-06T14:00:00Z")

        let plan = try planner.plan(input(reminders: [failing, unrelated], capacity: 5))

        #expect(plan.outcomes[acceptedID] == .scheduled)
        #expect(plan.selectedGroupIDs.contains(acceptedID))
        #expect(
            plan.requests.contains {
                $0.reminderID == failing.id
                    && $0.oneShotAlertInstant == date("2026-08-06T14:00:00Z")
            })
        #expect(plan.scheduledThrough[failing.id] == date("2026-08-06T14:00:00Z"))
        #expect(plan.outcomes[group(unrelated.id, "2026-08-06T14:30:00Z")] == .scheduled)
        #expect(plan.outcomes[group(unrelated.id, "2026-08-06T15:30:00Z")] == .scheduled)
        #expect(plan.outcomes[group(failing.id, "2026-08-06T15:00:00Z")] == nil)
    }

    @Test func rollingOverflowStopsOnlyThatReminderAndOtherCheaperGroupsContinue() throws {
        let expensive = reminder(
            "00000000-0000-0000-0000-00000000000A",
            hour: 13,
            interval: 1,
            early: EarlyReminder(value: 5, unit: .minutes)
        )
        let cheap = reminder(
            "00000000-0000-0000-0000-00000000000B",
            hour: 13,
            minute: 30,
            interval: 1
        )

        let plan = try planner.plan(input(reminders: [expensive, cheap], capacity: 4))

        #expect(plan.outcomes[group(expensive.id, "2026-08-06T14:00:00Z")] == .unscheduledCapacity)
        #expect(plan.outcomes[group(cheap.id, "2026-08-06T14:30:00Z")] == .scheduled)
        #expect(plan.selectedGroupIDs.last == group(cheap.id, "2026-08-06T14:30:00Z"))
    }

    @Test func capacityBoundariesAndInvalidValuesAreExact() throws {
        let value = reminder("00000000-0000-0000-0000-00000000000A", hour: 13, interval: 1)

        #expect(try planner.plan(input(reminders: [value], capacity: 0)).requests.isEmpty)
        #expect(try planner.plan(input(reminders: [value], capacity: 1)).requests.count == 1)
        #expect(try planner.plan(input(reminders: [value], capacity: 60)).requests.count == 60)
        #expect(throws: LogicalNotificationPlannerError.invalidCapacity(-1)) {
            try planner.plan(input(reminders: [value], capacity: -1))
        }
        #expect(throws: LogicalNotificationPlannerError.invalidCapacity(61)) {
            try planner.plan(input(reminders: [value], capacity: 61))
        }
    }

    @Test func classifiedNonActiveRemindersAreExcludedFromRequests() throws {
        let disabled = reminder(
            "00000000-0000-0000-0000-00000000000A", hour: 13, interval: 24, enabled: false)
        let unsupported = classifiedReminder(
            "00000000-0000-0000-0000-00000000000B",
            schedule: .unsupportedFuture(version: 3, originalData: Data([3]))
        )
        let invalid = classifiedReminder(
            "00000000-0000-0000-0000-00000000000C",
            schedule: .corrupt(originalData: Data([0]))
        )
        let expired = reminder(
            "00000000-0000-0000-0000-00000000000D",
            day: 5,
            hour: 13,
            interval: 24,
            endDay: 5
        )

        let plan = try planner.plan(
            input(reminders: [disabled, unsupported, invalid, expired], capacity: 60))

        #expect(plan.requests.isEmpty)
        #expect(plan.reminderStatuses[disabled.id]?.primary == .disabled)
        #expect(plan.reminderStatuses[unsupported.id]?.primary == .updateRequired)
        #expect(plan.reminderStatuses[invalid.id]?.primary == .invalidSchedule)
        #expect(plan.reminderStatuses[expired.id]?.primary == .expired)
    }

    @Test func deviceAndAuthorizationOffClearTargetsButRetainClassifications() throws {
        let active = reminder("00000000-0000-0000-0000-00000000000A", hour: 13, interval: 24)
        let off = try planner.plan(input(reminders: [active], capacity: 60, deviceEnabled: false))
        let denied = try planner.plan(
            input(reminders: [active], capacity: 60, authorization: false))

        #expect(off.requests.isEmpty)
        #expect(denied.requests.isEmpty)
        #expect(off.reminderStatuses[active.id]?.primary == .active)
        #expect(denied.reminderStatuses[active.id]?.primary == .active)
        #expect(off.outcomes.isEmpty)
        #expect(denied.outcomes.isEmpty)
    }

    @Test func sameFixedInputIsDeterministicAndEnvironmentIsSubstitutable() throws {
        let value = reminder("00000000-0000-0000-0000-00000000000A", hour: 13, interval: 24)
        let fixed = input(reminders: [value], capacity: 1)

        #expect(try planner.plan(fixed) == planner.plan(fixed))

        let shifted = input(
            reminders: [value],
            capacity: 1,
            environment: FixedOffsetEnvironment(secondsFromGMT: -3_600)
        )
        #expect(
            try #require(planner.plan(fixed).requests.first).oneShotAlertInstant
                == date("2026-08-06T13:00:00Z"))
        #expect(
            try #require(planner.plan(shifted).requests.first).oneShotAlertInstant
                == date("2026-08-06T14:00:00Z"))
    }

    private let planner = LogicalNotificationPlanner()
    private let now = date("2026-08-06T12:00:00Z")

    private func input(
        reminders: [ReminderSnapshot],
        capacity: Int,
        deviceEnabled: Bool = true,
        authorization: Bool = true,
        environment: any RecurrenceEnvironment = FoundationRecurrenceEnvironment()
    ) -> PlannerInput {
        PlannerInput(
            snapshot: CompleteReminderSnapshot(reminders: reminders, tags: []),
            evaluationNow: now,
            deviceNotificationsEnabled: deviceEnabled,
            authorizationAllowsScheduling: authorization,
            capacity: capacity,
            recurrenceEnvironment: environment
        )
    }

    private func reminder(
        _ id: String,
        day: Int = 6,
        hour: Int,
        minute: Int = 0,
        interval: Int,
        early: EarlyReminder? = nil,
        enabled: Bool = true,
        endDay: Int = 9
    ) -> ReminderSnapshot {
        classifiedReminder(
            id,
            schedule: .valid(
                ScheduleDefinition(
                    source: SourceWallClock(
                        year: 2026,
                        month: 8,
                        day: day,
                        hour: hour,
                        minute: minute,
                        timeZoneIdentifier: "Africa/Abidjan"
                    ),
                    rule: .hourly(interval: interval),
                    end: .onDate(SourceDate(year: 2026, month: 8, day: endDay)),
                    early: early
                ),
                sourceVersion: 1,
                originalData: Data([1])
            ),
            enabled: enabled
        )
    }

    private func weekdayReminder(
        _ id: String,
        hour: Int
    ) -> ReminderSnapshot {
        classifiedReminder(
            id,
            schedule: .valid(
                ScheduleDefinition(
                    source: SourceWallClock(
                        year: 2026,
                        month: 8,
                        day: 1,
                        hour: hour,
                        minute: 0,
                        timeZoneIdentifier: "Africa/Abidjan"
                    ),
                    rule: .weekly(
                        interval: 1,
                        weekdaySetKind: .weekday,
                        weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday]
                    ),
                    end: .never,
                    early: nil
                ),
                sourceVersion: 1,
                originalData: Data([1])
            )
        )
    }

    private func classifiedReminder(
        _ id: String,
        schedule: ScheduleReadState,
        enabled: Bool = true
    ) -> ReminderSnapshot {
        guard let reminderID = UUID(uuidString: id) else {
            preconditionFailure("Invalid reminder UUID fixture: \(id)")
        }
        return ReminderSnapshot(
            id: reminderID,
            title: id,
            notes: nil,
            urlString: nil,
            enabled: enabled,
            schedule: schedule,
            tagIDs: [],
            createdAt: now,
            updatedAt: now
        )
    }

    private func group(_ reminderID: String, _ instant: String) -> AlertGroupID {
        guard let id = UUID(uuidString: reminderID) else {
            preconditionFailure("Invalid reminder UUID fixture: \(reminderID)")
        }
        return group(id, instant)
    }

    private func group(_ reminderID: UUID, _ instant: String) -> AlertGroupID {
        AlertGroupID(reminderID: reminderID, baseOccurrenceInstant: date(instant))
    }
}

private struct FixedOffsetEnvironment: RecurrenceEnvironment {
    let secondsFromGMT: Int

    func timeZone(identifier: String) -> TimeZone? {
        TimeZone(secondsFromGMT: secondsFromGMT)
    }

    func gregorianCalendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

private enum InjectedPlannerFailure: Error {
    case expected
}

private func date(_ value: String) -> Date {
    guard let date = ISO8601DateFormatter().date(from: value) else {
        preconditionFailure("Invalid fixture date: \(value)")
    }
    return date
}
