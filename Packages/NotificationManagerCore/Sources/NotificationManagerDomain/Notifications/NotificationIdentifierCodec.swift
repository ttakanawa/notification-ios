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
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ]

    private static let constants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
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
                words[index] = UInt32(message[start]) << 24
                    | UInt32(message[start + 1]) << 16
                    | UInt32(message[start + 2]) << 8
                    | UInt32(message[start + 3])
            }
            for index in 16..<64 {
                let s0 = rotateRight(words[index - 15], by: 7)
                    ^ rotateRight(words[index - 15], by: 18)
                    ^ (words[index - 15] >> 3)
                let s1 = rotateRight(words[index - 2], by: 17)
                    ^ rotateRight(words[index - 2], by: 19)
                    ^ (words[index - 2] >> 10)
                words[index] = words[index - 16] &+ s0 &+ words[index - 7] &+ s1
            }

            var a = state[0]
            var b = state[1]
            var c = state[2]
            var d = state[3]
            var e = state[4]
            var f = state[5]
            var g = state[6]
            var h = state[7]

            for index in 0..<64 {
                let sum1 = rotateRight(e, by: 6) ^ rotateRight(e, by: 11) ^ rotateRight(e, by: 25)
                let choose = (e & f) ^ ((~e) & g)
                let temporary1 = h &+ sum1 &+ choose &+ constants[index] &+ words[index]
                let sum0 = rotateRight(a, by: 2) ^ rotateRight(a, by: 13) ^ rotateRight(a, by: 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temporary2 = sum0 &+ majority
                h = g
                g = f
                f = e
                e = d &+ temporary1
                d = c
                c = b
                b = a
                a = temporary1 &+ temporary2
            }

            state[0] &+= a
            state[1] &+= b
            state[2] &+= c
            state[3] &+= d
            state[4] &+= e
            state[5] &+= f
            state[6] &+= g
            state[7] &+= h
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
