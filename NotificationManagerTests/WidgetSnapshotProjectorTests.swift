import Foundation
import NotificationManagerDomain
import Testing

@testable import NotificationManager

@Suite("WidgetSnapshotProjector")
struct WidgetSnapshotProjectorTests {
    @MainActor
    @Test func appEnvironmentPublishUsesTheRegisteredItemsAndSameGenerationForWidgetPublication()
        async throws
    {
        let reminder = makeProjectorReminder(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            title: "Environment publication",
            schedule: futureOneShotSchedule()
        )
        let fireDate = widgetProjectorDate("2040-09-01T10:00:00Z")
        let deviceState = try makePublishableProjectorDeviceState(
            reminderID: reminder.id,
            fireDate: fireDate
        )
        let recorder = AppEnvironmentWidgetPublicationRecorder()
        let environment = AppEnvironment(widgetSnapshotPublication: { snapshot, generation in
            await recorder.record(
                AppEnvironmentWidgetPublication(
                    generation: generation,
                    reminderIDs: snapshot.events.map(\.reminderID),
                    fireDates: snapshot.events.map(\.fireDate)
                ))
        })

        environment.publish(
            CompleteReminderSnapshot(reminders: [reminder], tags: []),
            deviceState: deviceState
        )
        let publication = try await recorder.next()

        #expect(environment.listModel.snapshot.generation == 1)
        #expect(environment.listModel.items.map(\.id) == [reminder.id])
        #expect(
            publication
                == AppEnvironmentWidgetPublication(
                    generation: 1,
                    reminderIDs: [reminder.id],
                    fireDates: [fireDate]
                ))
    }

    @MainActor
    @Test func projectionFailureStillPublishesTheReminderList() {
        let reminder = makeProjectorReminder(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            title: "List remains successful",
            schedule: futureOneShotSchedule()
        )
        let environment = AppEnvironment()

        environment.publish(
            CompleteReminderSnapshot(reminders: [reminder], tags: []),
            deviceState: makeProjectorDeviceState(globalFailure: .planning)
        )

        #expect(environment.listModel.snapshot.generation == 1)
        #expect(environment.listModel.items.map(\.id) == [reminder.id])
    }

    @MainActor
    @Test func excludesEveryReminderThatIsNotActiveAndScheduled() throws {
        let generatedAt = widgetProjectorDate("2026-09-01T09:00:00Z")
        let eligible = makeProjectorReminder(
            id: "10000000-0000-0000-0000-000000000000",
            title: "Eligible",
            schedule: oneShotSchedule(hour: 10)
        )
        let disabled = makeProjectorReminder(
            id: "20000000-0000-0000-0000-000000000000",
            title: "Disabled",
            enabled: false,
            schedule: oneShotSchedule(hour: 10)
        )
        let expired = makeProjectorReminder(
            id: "30000000-0000-0000-0000-000000000000",
            title: "Expired",
            schedule: oneShotSchedule(hour: 8)
        )
        let invalid = makeProjectorReminder(
            id: "40000000-0000-0000-0000-000000000000",
            title: "Invalid",
            scheduleState: .corrupt(originalData: Data([0xff]))
        )
        let permissionDenied = makeProjectorReminder(
            id: "50000000-0000-0000-0000-000000000000",
            title: "Permission denied",
            schedule: oneShotSchedule(hour: 10)
        )
        let capacity = makeProjectorReminder(
            id: "60000000-0000-0000-0000-000000000000",
            title: "Capacity",
            schedule: oneShotSchedule(hour: 10)
        )
        let schedulingError = makeProjectorReminder(
            id: "70000000-0000-0000-0000-000000000000",
            title: "Error",
            schedule: oneShotSchedule(hour: 10)
        )
        let fireDate = widgetProjectorDate("2026-09-01T10:00:00Z")
        let items = [
            makeProjectorItem(eligible, authoritative: fireDate, scheduledThrough: fireDate),
            makeProjectorItem(
                disabled,
                lifecycleStatus: .disabled,
                deviceStatus: .notApplicable,
                authoritative: fireDate,
                scheduledThrough: fireDate
            ),
            makeProjectorItem(
                expired,
                lifecycleStatus: .expired,
                deviceStatus: .notApplicable,
                authoritative: fireDate,
                scheduledThrough: fireDate
            ),
            makeProjectorItem(
                invalid,
                lifecycleStatus: .invalidSchedule,
                deviceStatus: .notApplicable,
                authoritative: fireDate,
                scheduledThrough: fireDate
            ),
            makeProjectorItem(
                permissionDenied,
                deviceStatus: .notScheduledPermissionDenied,
                authoritative: fireDate,
                scheduledThrough: fireDate
            ),
            makeProjectorItem(
                capacity,
                deviceStatus: .unscheduledCapacity,
                authoritative: fireDate,
                scheduledThrough: fireDate
            ),
            makeProjectorItem(
                schedulingError,
                deviceStatus: .unscheduledError,
                authoritative: fireDate,
                scheduledThrough: fireDate
            )
        ]

        let snapshot = try WidgetSnapshotProjector().project(
            reminders: [
                eligible, disabled, expired, invalid, permissionDenied, capacity,
                schedulingError
            ],
            items: items,
            deviceState: makeProjectorDeviceState(),
            generatedAt: generatedAt
        )

        #expect(snapshot.events.map(\.reminderID) == [eligible.id])
        #expect(snapshot.events.map(\.fireDate) == [fireDate])
    }

    @MainActor
    @Test func oneShotProjectionIncludesEarlyAndMainPhysicalEvents() throws {
        let generatedAt = widgetProjectorDate("2026-09-01T09:00:00Z")
        let earlyDate = widgetProjectorDate("2026-09-01T09:45:00Z")
        let mainDate = widgetProjectorDate("2026-09-01T10:00:00Z")
        let reminder = makeProjectorReminder(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            title: "Early and main",
            schedule: oneShotSchedule(
                hour: 10,
                early: EarlyReminder(value: 15, unit: .minutes)
            )
        )

        let snapshot = try WidgetSnapshotProjector().project(
            reminders: [reminder],
            items: [
                makeProjectorItem(
                    reminder,
                    authoritative: earlyDate,
                    scheduledThrough: mainDate
                )
            ],
            deviceState: makeProjectorDeviceState(),
            generatedAt: generatedAt
        )

        #expect(snapshot.events.map(\.fireDate) == [earlyDate, mainDate])
    }

    @MainActor
    @Test func authoritativeDateReplacesPredictedFirstRepeatingEvent() throws {
        let generatedAt = widgetProjectorDate("2026-09-01T09:00:00Z")
        let authoritative = widgetProjectorDate("2026-09-01T10:01:00Z")
        let reminder = makeProjectorReminder(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            title: "Authoritative",
            schedule: dailySchedule(endDay: 4)
        )

        let snapshot = try WidgetSnapshotProjector().project(
            reminders: [reminder],
            items: [
                makeProjectorItem(
                    reminder,
                    authoritative: authoritative,
                    scheduledThrough: widgetProjectorDate("2026-09-04T10:00:00Z"),
                    isRepeating: true
                )
            ],
            deviceState: makeProjectorDeviceState(),
            generatedAt: generatedAt
        )

        #expect(snapshot.events.first?.fireDate == authoritative)
        #expect(snapshot.events.dropFirst().allSatisfy { $0.fireDate > authoritative })
        #expect(
            snapshot.events.map(\.fireDate) == [
                authoritative,
                widgetProjectorDate("2026-09-02T10:00:00Z"),
                widgetProjectorDate("2026-09-03T10:00:00Z"),
                widgetProjectorDate("2026-09-04T10:00:00Z")
            ])
    }

    @MainActor
    @Test func authoritativeDateEarlierThanPredictedFirstReplacesItWithoutAPhantom() throws {
        let generatedAt = widgetProjectorDate("2026-09-01T09:00:00Z")
        let authoritative = widgetProjectorDate("2026-09-01T09:30:00Z")
        let reminder = makeProjectorReminder(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            title: "Earlier authority",
            schedule: dailySchedule(endDay: 4)
        )

        let snapshot = try WidgetSnapshotProjector().project(
            reminders: [reminder],
            items: [
                makeProjectorItem(
                    reminder,
                    authoritative: authoritative,
                    scheduledThrough: widgetProjectorDate("2026-09-04T10:00:00Z"),
                    isRepeating: true
                )
            ],
            deviceState: makeProjectorDeviceState(),
            generatedAt: generatedAt
        )

        #expect(
            snapshot.events.map(\.fireDate) == [
                authoritative,
                widgetProjectorDate("2026-09-02T10:00:00Z"),
                widgetProjectorDate("2026-09-03T10:00:00Z"),
                widgetProjectorDate("2026-09-04T10:00:00Z")
            ])
    }

    @MainActor
    @Test func missingOrNonfutureAuthoritativeDateExcludesTheReminder() throws {
        let generatedAt = widgetProjectorDate("2026-09-01T09:00:00Z")
        let missingAuthority = makeProjectorReminder(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            title: "Missing authority",
            schedule: dailySchedule(endDay: 3)
        )
        let nonfutureAuthority = makeProjectorReminder(
            id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            title: "Nonfuture authority",
            schedule: dailySchedule(endDay: 3)
        )

        let snapshot = try WidgetSnapshotProjector().project(
            reminders: [missingAuthority, nonfutureAuthority],
            items: [
                makeProjectorItem(
                    missingAuthority,
                    authoritative: nil,
                    scheduledThrough: widgetProjectorDate("2026-09-03T10:00:00Z"),
                    isRepeating: true
                ),
                makeProjectorItem(
                    nonfutureAuthority,
                    authoritative: generatedAt,
                    scheduledThrough: widgetProjectorDate("2026-09-03T10:00:00Z"),
                    isRepeating: true
                )
            ],
            deviceState: makeProjectorDeviceState(),
            generatedAt: generatedAt
        )

        #expect(snapshot.events.isEmpty)
    }

    @MainActor
    @Test func rollingRepeatingProjectionStopsAtScheduledThrough() throws {
        let generatedAt = widgetProjectorDate("2026-09-01T09:00:00Z")
        let reminder = makeProjectorReminder(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            title: "Rolling",
            schedule: dailySchedule(endDay: 7)
        )

        let snapshot = try WidgetSnapshotProjector().project(
            reminders: [reminder],
            items: [
                makeProjectorItem(
                    reminder,
                    authoritative: widgetProjectorDate("2026-09-01T10:00:00Z"),
                    scheduledThrough: widgetProjectorDate("2026-09-03T10:00:00Z"),
                    isRepeating: true
                )
            ],
            deviceState: makeProjectorDeviceState(),
            generatedAt: generatedAt
        )

        #expect(
            snapshot.events.map(\.fireDate) == [
                widgetProjectorDate("2026-09-01T10:00:00Z"),
                widgetProjectorDate("2026-09-02T10:00:00Z"),
                widgetProjectorDate("2026-09-03T10:00:00Z")
            ])
        #expect(!snapshot.isTruncated)
    }

    @MainActor
    @Test func rollingRepeatingWithoutScheduledThroughDoesNotBecomeUnbounded() throws {
        let generatedAt = widgetProjectorDate("2026-09-01T09:00:00Z")
        let reminder = makeProjectorReminder(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            title: "Rolling without a horizon",
            schedule: dailySchedule(endDay: 7)
        )

        let snapshot = try WidgetSnapshotProjector().project(
            reminders: [reminder],
            items: [
                makeProjectorItem(
                    reminder,
                    authoritative: widgetProjectorDate("2026-09-01T10:00:00Z"),
                    scheduledThrough: nil,
                    isRepeating: true
                )
            ],
            deviceState: makeProjectorDeviceState(),
            generatedAt: generatedAt
        )

        #expect(snapshot.events.map(\.fireDate) == [widgetProjectorDate("2026-09-01T10:00:00Z")])
        #expect(!snapshot.isTruncated)
    }

    @MainActor
    @Test func staticRepeatingProjectionContinuesWithoutScheduledThroughAcrossBatches() throws {
        let generatedAt = widgetProjectorDate("2026-09-01T09:00:00Z")
        let reminder = makeProjectorReminder(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            title: "Static repeating",
            schedule: dailySchedule(endDay: 7)
        )
        let identifier = try NotificationIdentifierCodec().repeatingIdentifier(
            reminderID: reminder.id,
            components: RepeatingTriggerComponents(
                timeZoneIdentifier: "Africa/Abidjan",
                hour: 10,
                minute: 0,
                second: 0
            )
        )

        let snapshot = try WidgetSnapshotProjector().project(
            reminders: [reminder],
            items: [
                makeProjectorItem(
                    reminder,
                    authoritative: widgetProjectorDate("2026-09-01T10:00:00Z"),
                    scheduledThrough: nil,
                    isRepeating: true
                )
            ],
            deviceState: makeProjectorDeviceState(staticRepeatingIdentifier: identifier),
            generatedAt: generatedAt
        )

        #expect(snapshot.events.count == 7)
        #expect(snapshot.events.last?.fireDate == widgetProjectorDate("2026-09-07T10:00:00Z"))
        #expect(!snapshot.isTruncated)
    }

    @MainActor
    @Test func staticProjectionCapsAfterAuthoritativeReplacement() throws {
        let generatedAt = widgetProjectorDate("2026-09-01T09:00:00Z")
        let authoritative = widgetProjectorDate("2026-09-01T20:30:00Z")
        let reminder = makeProjectorReminder(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            title: "Static replacement cap",
            schedule: hourlySchedule(endDay: 4)
        )
        let identifier = try NotificationIdentifierCodec().repeatingIdentifier(
            reminderID: reminder.id,
            components: RepeatingTriggerComponents(
                timeZoneIdentifier: "Africa/Abidjan",
                hour: 10,
                minute: 0,
                second: 0
            )
        )

        let snapshot = try WidgetSnapshotProjector().project(
            reminders: [reminder],
            items: [
                makeProjectorItem(
                    reminder,
                    authoritative: authoritative,
                    scheduledThrough: nil,
                    isRepeating: true
                )
            ],
            deviceState: makeProjectorDeviceState(staticRepeatingIdentifier: identifier),
            generatedAt: generatedAt
        )

        #expect(snapshot.events.count == 60)
        #expect(snapshot.events.first?.fireDate == authoritative)
        #expect(
            snapshot.events.dropFirst().first?.fireDate
                == widgetProjectorDate("2026-09-01T21:00:00Z"))
        #expect(snapshot.isTruncated)
    }

    @MainActor
    @Test func projectionCollapsesDuplicatesAndOrdersByFireDateThenUUID() throws {
        let generatedAt = widgetProjectorDate("2026-09-01T08:00:00Z")
        let laterB = makeProjectorReminder(
            id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            title: "Later B",
            schedule: oneShotSchedule(hour: 10)
        )
        let laterA = makeProjectorReminder(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            title: "Later A",
            schedule: oneShotSchedule(hour: 10)
        )
        let earlier = makeProjectorReminder(
            id: "cccccccc-cccc-cccc-cccc-cccccccccccc",
            title: "Earlier",
            schedule: oneShotSchedule(hour: 9)
        )
        let laterDate = widgetProjectorDate("2026-09-01T10:00:00Z")
        let earlierDate = widgetProjectorDate("2026-09-01T09:00:00Z")

        let snapshot = try WidgetSnapshotProjector().project(
            reminders: [laterB, laterA, earlier, laterB],
            items: [
                makeProjectorItem(laterB, authoritative: laterDate, scheduledThrough: laterDate),
                makeProjectorItem(laterA, authoritative: laterDate, scheduledThrough: laterDate),
                makeProjectorItem(
                    earlier,
                    authoritative: earlierDate,
                    scheduledThrough: earlierDate
                )
            ],
            deviceState: makeProjectorDeviceState(),
            generatedAt: generatedAt
        )

        #expect(snapshot.events.map(\.reminderID) == [earlier.id, laterA.id, laterB.id])
        #expect(snapshot.events.map(\.fireDate) == [earlierDate, laterDate, laterDate])
    }

    @MainActor
    @Test func projectionCapsAtSixtyAndMarksARealSixtyFirstEventAsTruncated() throws {
        let generatedAt = widgetProjectorDate("2026-09-01T09:00:00Z")
        let fireDate = widgetProjectorDate("2026-09-01T10:00:00Z")
        let reminders = (1...61).map { index in
            makeProjectorReminder(
                id: String(format: "00000000-0000-0000-0000-%012d", index),
                title: "Reminder \(index)",
                schedule: oneShotSchedule(hour: 10)
            )
        }

        let snapshot = try WidgetSnapshotProjector().project(
            reminders: reminders.reversed(),
            items: reminders.map {
                makeProjectorItem($0, authoritative: fireDate, scheduledThrough: fireDate)
            },
            deviceState: makeProjectorDeviceState(),
            generatedAt: generatedAt
        )

        #expect(snapshot.events.count == 60)
        #expect(snapshot.isTruncated)
        #expect(snapshot.events.first?.reminderID == reminders[0].id)
        #expect(snapshot.events.last?.reminderID == reminders[59].id)
        #expect(!snapshot.events.contains { $0.reminderID == reminders[60].id })
    }

    @MainActor
    @Test func globalSchedulingFailureRejectsTheProjection() {
        let reminder = makeProjectorReminder(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            title: "Previously valid",
            schedule: oneShotSchedule(hour: 10)
        )
        let fireDate = widgetProjectorDate("2026-09-01T10:00:00Z")

        #expect(throws: (any Error).self) {
            _ = try WidgetSnapshotProjector().project(
                reminders: [reminder],
                items: [
                    makeProjectorItem(
                        reminder,
                        authoritative: fireDate,
                        scheduledThrough: fireDate
                    )
                ],
                deviceState: makeProjectorDeviceState(globalFailure: .planning),
                generatedAt: widgetProjectorDate("2026-09-01T09:00:00Z")
            )
        }
    }
}

private func makeProjectorReminder(
    id: String,
    title: String,
    enabled: Bool = true,
    schedule: ScheduleDefinition? = nil,
    scheduleState: ScheduleReadState? = nil
) -> ReminderSnapshot {
    guard let reminderID = UUID(uuidString: id) else {
        preconditionFailure("Invalid reminder fixture UUID: \(id)")
    }
    let resolvedSchedule =
        scheduleState ?? schedule.map {
            .valid($0, sourceVersion: 1, originalData: Data())
        } ?? .corrupt(originalData: Data([0xff]))
    return ReminderSnapshot(
        id: reminderID,
        title: title,
        notes: nil,
        urlString: nil,
        enabled: enabled,
        schedule: resolvedSchedule,
        tagIDs: [],
        createdAt: widgetProjectorDate("2026-08-01T00:00:00Z"),
        updatedAt: widgetProjectorDate("2026-08-02T00:00:00Z")
    )
}

private func makeProjectorItem(
    _ reminder: ReminderSnapshot,
    lifecycleStatus: LifecycleStatus = .active,
    deviceStatus: DeviceSchedulingStatus = .scheduled,
    authoritative: Date?,
    scheduledThrough: Date?,
    isRepeating: Bool = false
) -> ReminderListItemPresentation {
    ReminderListItemPresentation(
        id: reminder.id,
        title: reminder.title,
        reminderStatus: ReminderStatus(primary: lifecycleStatus, secondary: []),
        deviceSchedulingStatus: deviceStatus,
        nextPresentation: authoritative.map {
            .directOSFire(authoritative: $0, foundationPreview: $0)
        },
        isRepeating: isRepeating,
        enabled: reminder.enabled,
        scheduledThrough: scheduledThrough,
        updatedAt: reminder.updatedAt
    )
}

private func makeProjectorDeviceState(
    globalFailure: SchedulingGlobalFailure? = nil,
    staticRepeatingIdentifier: String? = nil
) -> DeviceSchedulingStateSnapshot {
    let identifiers = Set([staticRepeatingIdentifier].compactMap { $0 })
    let kinds = Dictionary(
        uniqueKeysWithValues: identifiers.map { ($0, MaterializedNotificationKind.repeating) }
    )
    return DeviceSchedulingStateSnapshot(
        generation: 1,
        reconcileInProgressOrQueued: false,
        globalFailure: globalFailure,
        deviceNotificationsEnabled: true,
        authorization: NotificationAuthorizationSnapshot(state: .allowed, diagnostic: nil),
        outcomes: [:],
        scheduledThrough: [:],
        materializedKinds: kinds,
        nextTriggerDates: [:],
        pendingOrAddedIdentifiers: identifiers
    )
}

private func oneShotSchedule(
    hour: Int,
    early: EarlyReminder? = nil
) -> ScheduleDefinition {
    ScheduleDefinition(
        source: SourceWallClock(
            year: 2026,
            month: 9,
            day: 1,
            hour: hour,
            minute: 0,
            timeZoneIdentifier: "Africa/Abidjan"
        ),
        rule: .none,
        end: .never,
        early: early
    )
}

private func dailySchedule(endDay: Int) -> ScheduleDefinition {
    ScheduleDefinition(
        source: SourceWallClock(
            year: 2026,
            month: 9,
            day: 1,
            hour: 10,
            minute: 0,
            timeZoneIdentifier: "Africa/Abidjan"
        ),
        rule: .daily(interval: 1),
        end: .onDate(SourceDate(year: 2026, month: 9, day: endDay)),
        early: nil
    )
}

private func hourlySchedule(endDay: Int) -> ScheduleDefinition {
    ScheduleDefinition(
        source: SourceWallClock(
            year: 2026,
            month: 9,
            day: 1,
            hour: 10,
            minute: 0,
            timeZoneIdentifier: "Africa/Abidjan"
        ),
        rule: .hourly(interval: 1),
        end: .onDate(SourceDate(year: 2026, month: 9, day: endDay)),
        early: nil
    )
}

private func futureOneShotSchedule() -> ScheduleDefinition {
    ScheduleDefinition(
        source: SourceWallClock(
            year: 2040,
            month: 9,
            day: 1,
            hour: 10,
            minute: 0,
            timeZoneIdentifier: "Africa/Abidjan"
        ),
        rule: .none,
        end: .never,
        early: nil
    )
}

private func makePublishableProjectorDeviceState(
    reminderID: UUID,
    fireDate: Date
) throws -> DeviceSchedulingStateSnapshot {
    let identifier = try NotificationIdentifierCodec().oneShotIdentifier(
        reminderID: reminderID,
        alertInstant: fireDate
    )
    return DeviceSchedulingStateSnapshot(
        generation: 1,
        reconcileInProgressOrQueued: false,
        globalFailure: nil,
        deviceNotificationsEnabled: true,
        authorization: NotificationAuthorizationSnapshot(state: .allowed, diagnostic: nil),
        outcomes: [
            AlertGroupID(
                reminderID: reminderID,
                baseOccurrenceInstant: fireDate
            ): .scheduled
        ],
        scheduledThrough: [reminderID: fireDate],
        materializedKinds: [identifier: .oneShot],
        nextTriggerDates: [identifier: fireDate],
        pendingOrAddedIdentifiers: [identifier]
    )
}

private struct AppEnvironmentWidgetPublication: Sendable, Equatable {
    let generation: UInt64
    let reminderIDs: [UUID]
    let fireDates: [Date]
}

private actor AppEnvironmentWidgetPublicationRecorder {
    private var buffered: [AppEnvironmentWidgetPublication] = []

    func record(_ publication: AppEnvironmentWidgetPublication) {
        buffered.append(publication)
    }

    func next(timeout: Duration = .seconds(1)) async throws -> AppEnvironmentWidgetPublication {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if !buffered.isEmpty {
                return buffered.removeFirst()
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw WidgetPublicationRecorderError.timedOut
    }
}

private enum WidgetPublicationRecorderError: Error {
    case timedOut
}

private func widgetProjectorDate(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let parsed = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    else {
        preconditionFailure("Invalid widget projector date fixture: \(value)")
    }
    return parsed
}
