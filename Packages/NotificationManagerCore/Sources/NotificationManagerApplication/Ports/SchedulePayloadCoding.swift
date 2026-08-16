import Foundation
import NotificationManagerDomain

public struct EncodedSchedulePayload: Sendable, Equatable {
    public let version: UInt32
    public let data: Data

    public init(version: UInt32, data: Data) {
        precondition(version > 0, "An encoded schedule version must be positive")
        self.version = version
        self.data = data
    }
}

public protocol SchedulePayloadCoding: Sendable {
    func decode(_ data: Data) -> ScheduleReadState
    func encodeCurrent(_ definition: ScheduleDefinition) throws -> EncodedSchedulePayload
}
