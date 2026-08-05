import Foundation
import NotificationManagerDomain

public protocol SchedulePayloadCoding: Sendable {
    func decode(_ data: Data) -> ScheduleReadState
    func encodeCurrent(_ definition: ScheduleDefinition) throws -> Data
}
