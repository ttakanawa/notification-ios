import NotificationManagerApplication
import NotificationManagerDomain

struct RecordMapper: Sendable {
    let scheduleCodec: any SchedulePayloadCoding

    func reminder(_ record: ReminderRecordV1) -> ReminderSnapshot {
        ReminderSnapshot(
            id: record.id,
            title: record.title,
            notes: record.notes,
            urlString: record.urlString,
            enabled: record.enabled,
            schedule: scheduleCodec.decode(record.scheduleData),
            tagIDs: Set((record.tags ?? []).map(\.id)),
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    func tag(_ record: TagRecordV1) -> TagSnapshot {
        TagSnapshot(
            id: record.id,
            name: record.name,
            normalizedName: record.normalizedName,
            normalizationVersion: record.normalizationVersion,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }
}
