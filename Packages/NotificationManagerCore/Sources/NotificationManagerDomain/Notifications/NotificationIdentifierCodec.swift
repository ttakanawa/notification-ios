import Foundation

public enum NotificationIdentifierCodecError: Error, Sendable, Equatable {
    case invalidAlertInstant
    case invalidRepeatingComponents
}

public struct NotificationIdentifierCodec: Sendable {
    public static let root = "notification-manager.local."

    public init() {}

    public func oneShotIdentifier(reminderID: UUID, alertInstant: Date) throws -> String {
        let seconds = alertInstant.timeIntervalSince1970
        guard seconds.isFinite,
            seconds.rounded(.towardZero) == seconds,
            seconds >= -9_223_372_036_854_775_808.0,
            seconds < 9_223_372_036_854_775_808.0
        else {
            throw NotificationIdentifierCodecError.invalidAlertInstant
        }
        let unixSeconds = Int64(seconds)
        return Self.root + "v1.o.\(reminderID.uuidString.lowercased()).\(unixSeconds)"
    }

    public func repeatingIdentifier(
        reminderID: UUID,
        components: RepeatingTriggerComponents
    ) throws -> String {
        let digest = try repeatingDigest(components: components)
        return Self.root + "v1.r.\(reminderID.uuidString.lowercased()).\(digest)"
    }

    public func repeatingDigest(components: RepeatingTriggerComponents) throws -> String {
        let document = try canonicalDocument(for: components)
        return SHA256.hash(document).map { String(format: "%02x", $0) }.joined()
    }

    public func classify(_ rawValue: String) -> NotificationIdentifierClassification {
        guard rawValue.hasPrefix(Self.root) else { return .unrelated }
        let namespace = rawValue.dropFirst(Self.root.count)
        let fields = namespace.split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count == 4,
            fields[0] == "v1",
            let reminderID = canonicalUUID(String(fields[2]))
        else {
            return .appOwnedStale
        }

        let suffix = String(fields[3])
        switch fields[1] {
        case "o":
            guard let unixSeconds = Int64(suffix), String(unixSeconds) == suffix else {
                return .appOwnedStale
            }
            return .currentOneShot(reminderID: reminderID, unixSeconds: unixSeconds)
        case "r":
            guard suffix.utf8.count == 64,
                suffix.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
            else {
                return .appOwnedStale
            }
            return .currentRepeating(reminderID: reminderID, digest: suffix)
        default:
            return .appOwnedStale
        }
    }

    func canonicalDocument(for components: RepeatingTriggerComponents) throws -> Data {
        _ = try components.validated()

        var fields = [#""calendar":"gregorian""#]
        if let day = components.day { fields.append(#""day":\#(day)"#) }
        fields.append(#""hour":\#(components.hour)"#)
        fields.append(#""minute":\#(components.minute)"#)
        if let month = components.month { fields.append(#""month":\#(month)"#) }
        fields.append(#""repeats":true"#)
        fields.append(#""second":0"#)
        fields.append(#""timeZone":"\#(components.timeZoneIdentifier)""#)
        if let weekday = components.weekday { fields.append(#""weekday":\#(weekday)"#) }
        return Data(("{" + fields.joined(separator: ",") + "}").utf8)
    }

    private func canonicalUUID(_ rawValue: String) -> UUID? {
        guard rawValue.utf8.count == 36,
            rawValue == rawValue.lowercased(),
            let uuid = UUID(uuidString: rawValue),
            uuid.uuidString.lowercased() == rawValue
        else {
            return nil
        }
        return uuid
    }
}

private enum SHA256 {
    private static let initial: [UInt32] = [
        0x6a09_e667, 0xbb67_ae85, 0x3c6e_f372, 0xa54f_f53a,
        0x510e_527f, 0x9b05_688c, 0x1f83_d9ab, 0x5be0_cd19
    ]

    private static let constants: [UInt32] = [
        0x428a_2f98, 0x7137_4491, 0xb5c0_fbcf, 0xe9b5_dba5,
        0x3956_c25b, 0x59f1_11f1, 0x923f_82a4, 0xab1c_5ed5,
        0xd807_aa98, 0x1283_5b01, 0x2431_85be, 0x550c_7dc3,
        0x72be_5d74, 0x80de_b1fe, 0x9bdc_06a7, 0xc19b_f174,
        0xe49b_69c1, 0xefbe_4786, 0x0fc1_9dc6, 0x240c_a1cc,
        0x2de9_2c6f, 0x4a74_84aa, 0x5cb0_a9dc, 0x76f9_88da,
        0x983e_5152, 0xa831_c66d, 0xb003_27c8, 0xbf59_7fc7,
        0xc6e0_0bf3, 0xd5a7_9147, 0x06ca_6351, 0x1429_2967,
        0x27b7_0a85, 0x2e1b_2138, 0x4d2c_6dfc, 0x5338_0d13,
        0x650a_7354, 0x766a_0abb, 0x81c2_c92e, 0x9272_2c85,
        0xa2bf_e8a1, 0xa81a_664b, 0xc24b_8b70, 0xc76c_51a3,
        0xd192_e819, 0xd699_0624, 0xf40e_3585, 0x106a_a070,
        0x19a4_c116, 0x1e37_6c08, 0x2748_774c, 0x34b0_bcb5,
        0x391c_0cb3, 0x4ed8_aa4a, 0x5b9c_ca4f, 0x682e_6ff3,
        0x748f_82ee, 0x78a5_636f, 0x84c8_7814, 0x8cc7_0208,
        0x90be_fffa, 0xa450_6ceb, 0xbef9_a3f7, 0xc671_78f2
    ]

    static func hash(_ data: Data) -> [UInt8] {
        var message = Array(data)
        let bitLength = UInt64(message.count) &* 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift)))
        }

        var state = initial
        for offset in stride(from: 0, to: message.count, by: 64) {
            var words = [UInt32](repeating: 0, count: 64)
            for index in 0..<16 {
                let start = offset + index * 4
                words[index] =
                    UInt32(message[start]) << 24
                    | UInt32(message[start + 1]) << 16
                    | UInt32(message[start + 2]) << 8
                    | UInt32(message[start + 3])
            }
            for index in 16..<64 {
                let smallSigmaZero =
                    rotateRight(words[index - 15], by: 7)
                    ^ rotateRight(words[index - 15], by: 18)
                    ^ (words[index - 15] >> 3)
                let smallSigmaOne =
                    rotateRight(words[index - 2], by: 17)
                    ^ rotateRight(words[index - 2], by: 19)
                    ^ (words[index - 2] >> 10)
                words[index] =
                    words[index - 16] &+ smallSigmaZero &+ words[index - 7] &+ smallSigmaOne
            }

            var workingA = state[0]
            var workingB = state[1]
            var workingC = state[2]
            var workingD = state[3]
            var workingE = state[4]
            var workingF = state[5]
            var workingG = state[6]
            var workingH = state[7]

            for index in 0..<64 {
                let sum1 =
                    rotateRight(workingE, by: 6)
                    ^ rotateRight(workingE, by: 11)
                    ^ rotateRight(workingE, by: 25)
                let choose = (workingE & workingF) ^ ((~workingE) & workingG)
                let temporary1 =
                    workingH &+ sum1 &+ choose &+ constants[index] &+ words[index]
                let sum0 =
                    rotateRight(workingA, by: 2)
                    ^ rotateRight(workingA, by: 13)
                    ^ rotateRight(workingA, by: 22)
                let majority =
                    (workingA & workingB) ^ (workingA & workingC) ^ (workingB & workingC)
                let temporary2 = sum0 &+ majority
                workingH = workingG
                workingG = workingF
                workingF = workingE
                workingE = workingD &+ temporary1
                workingD = workingC
                workingC = workingB
                workingB = workingA
                workingA = temporary1 &+ temporary2
            }

            state[0] &+= workingA
            state[1] &+= workingB
            state[2] &+= workingC
            state[3] &+= workingD
            state[4] &+= workingE
            state[5] &+= workingF
            state[6] &+= workingG
            state[7] &+= workingH
        }

        return state.flatMap { word in
            [
                UInt8(truncatingIfNeeded: word >> 24),
                UInt8(truncatingIfNeeded: word >> 16),
                UInt8(truncatingIfNeeded: word >> 8),
                UInt8(truncatingIfNeeded: word)
            ]
        }
    }

    private static func rotateRight(_ value: UInt32, by count: UInt32) -> UInt32 {
        (value >> count) | (value << (32 - count))
    }
}
