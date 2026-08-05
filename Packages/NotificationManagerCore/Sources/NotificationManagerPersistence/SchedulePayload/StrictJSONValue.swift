import Foundation

enum StrictJSONValue: Sendable, Equatable {
    case object([String: StrictJSONValue])
    case array([StrictJSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    static func parse(_ data: Data) throws -> StrictJSONValue {
        guard !data.starts(with: [0xEF, 0xBB, 0xBF]) else {
            throw StrictJSONError.invalidDocument
        }
        var parser = StrictJSONParser(bytes: Array(data))
        let value = try parser.parseDocument()
        return value
    }

    static func probeEnvelope(_ data: Data) throws -> StrictJSONEnvelopeProbe {
        guard !data.starts(with: [0xEF, 0xBB, 0xBF]) else {
            throw StrictJSONError.invalidDocument
        }
        var parser = StrictJSONParser(bytes: Array(data))
        return try parser.parseEnvelopeProbe()
    }

    var objectValue: [String: StrictJSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    func integer<T: FixedWidthInteger>(as type: T.Type = T.self) -> T? {
        guard case let .number(lexeme) = self,
              !lexeme.contains("."),
              !lexeme.contains("e"),
              !lexeme.contains("E")
        else {
            return nil
        }
        return T(lexeme)
    }
}

enum StrictJSONError: Error {
    case invalidDocument
}

struct StrictJSONEnvelopeProbe: Sendable, Equatable {
    let format: String
    let version: UInt32
}

private struct StrictJSONParser {
    private let bytes: [UInt8]
    private var index = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func parseDocument() throws -> StrictJSONValue {
        skipWhitespace()
        let value = try parseValue(depth: 0)
        skipWhitespace()
        guard index == bytes.count else { throw StrictJSONError.invalidDocument }
        return value
    }

    mutating func parseEnvelopeProbe() throws -> StrictJSONEnvelopeProbe {
        skipWhitespace()
        try consume(0x7B)
        skipWhitespace()
        var format: String?
        var version: UInt32?
        var foundFormat = false
        var foundVersion = false

        if !consumeIfPresent(0x7D) {
            while true {
                guard current == 0x22 else { throw StrictJSONError.invalidDocument }
                let key = try parseString()
                skipWhitespace()
                try consume(0x3A)
                skipWhitespace()

                switch key {
                case "format":
                    guard !foundFormat, current == 0x22 else {
                        throw StrictJSONError.invalidDocument
                    }
                    foundFormat = true
                    format = try parseString()
                case "version":
                    guard !foundVersion else { throw StrictJSONError.invalidDocument }
                    foundVersion = true
                    let lexeme = try parseNumber()
                    guard lexeme.allSatisfy({ $0.isASCII && $0.isNumber }),
                          let parsedVersion = UInt32(lexeme)
                    else {
                        throw StrictJSONError.invalidDocument
                    }
                    version = parsedVersion
                default:
                    try skipValue()
                }

                skipWhitespace()
                if consumeIfPresent(0x7D) { break }
                try consume(0x2C)
                skipWhitespace()
            }
        }
        skipWhitespace()
        guard index == bytes.count, let format, let version else {
            throw StrictJSONError.invalidDocument
        }
        return StrictJSONEnvelopeProbe(format: format, version: version)
    }

    private mutating func skipValue() throws {
        var tasks: [SkippedJSONTask] = [.value]
        while let task = tasks.popLast() {
            switch task {
            case .value:
                guard let byte = current else { throw StrictJSONError.invalidDocument }
                switch byte {
                case 0x7B:
                    try consume(0x7B)
                    skipWhitespace()
                    tasks.append(.objectContents)
                case 0x5B:
                    try consume(0x5B)
                    skipWhitespace()
                    tasks.append(.arrayContents)
                case 0x22:
                    _ = try parseString()
                case 0x74:
                    try consumeLiteral([0x74, 0x72, 0x75, 0x65])
                case 0x66:
                    try consumeLiteral([0x66, 0x61, 0x6C, 0x73, 0x65])
                case 0x6E:
                    try consumeLiteral([0x6E, 0x75, 0x6C, 0x6C])
                case 0x2D, 0x30 ... 0x39:
                    _ = try parseNumber()
                default:
                    throw StrictJSONError.invalidDocument
                }
            case .arrayContents:
                if consumeIfPresent(0x5D) { continue }
                tasks.append(.arrayContinuation)
                tasks.append(.value)
            case .arrayContinuation:
                skipWhitespace()
                if consumeIfPresent(0x5D) { continue }
                try consume(0x2C)
                skipWhitespace()
                tasks.append(.arrayContinuation)
                tasks.append(.value)
            case .objectContents:
                if consumeIfPresent(0x7D) { continue }
                try parseSkippedObjectMember(tasks: &tasks)
            case .objectContinuation:
                skipWhitespace()
                if consumeIfPresent(0x7D) { continue }
                try consume(0x2C)
                skipWhitespace()
                try parseSkippedObjectMember(tasks: &tasks)
            }
        }
    }

    private mutating func parseSkippedObjectMember(tasks: inout [SkippedJSONTask]) throws {
        guard current == 0x22 else { throw StrictJSONError.invalidDocument }
        _ = try parseString()
        skipWhitespace()
        try consume(0x3A)
        skipWhitespace()
        tasks.append(.objectContinuation)
        tasks.append(.value)
    }

    private mutating func parseValue(depth: Int) throws -> StrictJSONValue {
        guard depth <= 128, let byte = current else { throw StrictJSONError.invalidDocument }
        switch byte {
        case 0x7B:
            return try parseObject(depth: depth + 1)
        case 0x5B:
            return try parseArray(depth: depth + 1)
        case 0x22:
            return .string(try parseString())
        case 0x74:
            try consumeLiteral([0x74, 0x72, 0x75, 0x65])
            return .bool(true)
        case 0x66:
            try consumeLiteral([0x66, 0x61, 0x6C, 0x73, 0x65])
            return .bool(false)
        case 0x6E:
            try consumeLiteral([0x6E, 0x75, 0x6C, 0x6C])
            return .null
        case 0x2D, 0x30 ... 0x39:
            return .number(try parseNumber())
        default:
            throw StrictJSONError.invalidDocument
        }
    }

    private mutating func parseObject(depth: Int) throws -> StrictJSONValue {
        try consume(0x7B)
        skipWhitespace()
        var object: [String: StrictJSONValue] = [:]
        if consumeIfPresent(0x7D) { return .object(object) }

        while true {
            guard current == 0x22 else { throw StrictJSONError.invalidDocument }
            let key = try parseString()
            guard object[key] == nil else { throw StrictJSONError.invalidDocument }
            skipWhitespace()
            try consume(0x3A)
            skipWhitespace()
            object[key] = try parseValue(depth: depth)
            skipWhitespace()
            if consumeIfPresent(0x7D) { return .object(object) }
            try consume(0x2C)
            skipWhitespace()
        }
    }

    private mutating func parseArray(depth: Int) throws -> StrictJSONValue {
        try consume(0x5B)
        skipWhitespace()
        var array: [StrictJSONValue] = []
        if consumeIfPresent(0x5D) { return .array(array) }

        while true {
            array.append(try parseValue(depth: depth))
            skipWhitespace()
            if consumeIfPresent(0x5D) { return .array(array) }
            try consume(0x2C)
            skipWhitespace()
        }
    }

    private mutating func parseString() throws -> String {
        try consume(0x22)
        var result = ""
        var segmentStart = index

        while let byte = current {
            if byte == 0x22 {
                try appendUTF8Segment(from: segmentStart, to: index, to: &result)
                index += 1
                return result
            }
            if byte < 0x20 { throw StrictJSONError.invalidDocument }
            if byte != 0x5C {
                index += 1
                continue
            }

            try appendUTF8Segment(from: segmentStart, to: index, to: &result)
            index += 1
            guard let escape = current else { throw StrictJSONError.invalidDocument }
            index += 1
            switch escape {
            case 0x22: result.append("\"")
            case 0x5C: result.append("\\")
            case 0x2F: result.append("/")
            case 0x62: result.append("\u{08}")
            case 0x66: result.append("\u{0C}")
            case 0x6E: result.append("\n")
            case 0x72: result.append("\r")
            case 0x74: result.append("\t")
            case 0x75:
                let first = try parseHexQuad()
                let scalar: UInt32
                if (0xD800 ... 0xDBFF).contains(first) {
                    try consume(0x5C)
                    try consume(0x75)
                    let second = try parseHexQuad()
                    guard (0xDC00 ... 0xDFFF).contains(second) else {
                        throw StrictJSONError.invalidDocument
                    }
                    scalar = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
                } else {
                    guard !(0xDC00 ... 0xDFFF).contains(first) else {
                        throw StrictJSONError.invalidDocument
                    }
                    scalar = first
                }
                guard let unicodeScalar = UnicodeScalar(scalar) else {
                    throw StrictJSONError.invalidDocument
                }
                result.unicodeScalars.append(unicodeScalar)
            default:
                throw StrictJSONError.invalidDocument
            }
            segmentStart = index
        }
        throw StrictJSONError.invalidDocument
    }

    private mutating func parseHexQuad() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let byte = current else { throw StrictJSONError.invalidDocument }
            index += 1
            let digit: UInt32
            switch byte {
            case 0x30 ... 0x39: digit = UInt32(byte - 0x30)
            case 0x41 ... 0x46: digit = UInt32(byte - 0x41 + 10)
            case 0x61 ... 0x66: digit = UInt32(byte - 0x61 + 10)
            default: throw StrictJSONError.invalidDocument
            }
            value = value * 16 + digit
        }
        return value
    }

    private mutating func parseNumber() throws -> String {
        let start = index
        _ = consumeIfPresent(0x2D)
        guard let byte = current else { throw StrictJSONError.invalidDocument }
        if byte == 0x30 {
            index += 1
            if let next = current, (0x30 ... 0x39).contains(next) {
                throw StrictJSONError.invalidDocument
            }
        } else if (0x31 ... 0x39).contains(byte) {
            repeat { index += 1 } while current.map { (0x30 ... 0x39).contains($0) } == true
        } else {
            throw StrictJSONError.invalidDocument
        }

        if consumeIfPresent(0x2E) {
            guard current.map({ (0x30 ... 0x39).contains($0) }) == true else {
                throw StrictJSONError.invalidDocument
            }
            repeat { index += 1 } while current.map { (0x30 ... 0x39).contains($0) } == true
        }
        if current == 0x65 || current == 0x45 {
            index += 1
            if current == 0x2B || current == 0x2D { index += 1 }
            guard current.map({ (0x30 ... 0x39).contains($0) }) == true else {
                throw StrictJSONError.invalidDocument
            }
            repeat { index += 1 } while current.map { (0x30 ... 0x39).contains($0) } == true
        }

        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    private mutating func consumeLiteral(_ literal: [UInt8]) throws {
        guard bytes[index...].starts(with: literal) else { throw StrictJSONError.invalidDocument }
        index += literal.count
    }

    private mutating func appendUTF8Segment(
        from start: Int,
        to end: Int,
        to result: inout String
    ) throws {
        guard let segment = String(bytes: bytes[start..<end], encoding: .utf8) else {
            throw StrictJSONError.invalidDocument
        }
        result.append(segment)
    }

    private var current: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private mutating func skipWhitespace() {
        while let byte = current, byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
            index += 1
        }
    }

    private mutating func consume(_ byte: UInt8) throws {
        guard current == byte else { throw StrictJSONError.invalidDocument }
        index += 1
    }

    private mutating func consumeIfPresent(_ byte: UInt8) -> Bool {
        guard current == byte else { return false }
        index += 1
        return true
    }
}

private enum SkippedJSONTask {
    case value
    case arrayContents
    case arrayContinuation
    case objectContents
    case objectContinuation
}
