import Foundation

public enum CanonicalHTTPURLError: Error, Sendable, Equatable {
    case malformed
    case unsupportedScheme
    case missingHost
}

public struct CanonicalHTTPURL: Sendable, Equatable {
    public let string: String

    public init(_ value: String) throws {
        let forbidden = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        guard !value.isEmpty,
              value.unicodeScalars.allSatisfy({ !forbidden.contains($0) }),
              Self.hasValidPercentEscapes(value),
              Self.hasValidExplicitPort(value),
              var components = URLComponents(string: value)
        else {
            throw CanonicalHTTPURLError.malformed
        }

        guard let inputScheme = components.scheme else {
            throw CanonicalHTTPURLError.malformed
        }
        let scheme = inputScheme.lowercased()
        guard scheme == "http" || scheme == "https" else {
            throw CanonicalHTTPURLError.unsupportedScheme
        }
        guard let inputHost = components.host, !inputHost.isEmpty else {
            throw CanonicalHTTPURLError.missingHost
        }
        if let port = components.port, !(0...65_535).contains(port) {
            throw CanonicalHTTPURLError.malformed
        }

        components.scheme = scheme
        components.host = inputHost.lowercased()
        if (scheme == "http" && components.port == 80)
            || (scheme == "https" && components.port == 443)
        {
            components.port = nil
        }

        guard let result = components.string,
              let reparsed = URLComponents(string: result),
              reparsed.scheme == scheme,
              let host = reparsed.host,
              !host.isEmpty
        else {
            throw CanonicalHTTPURLError.malformed
        }
        string = result
    }

    private static func hasValidPercentEscapes(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        var index = bytes.startIndex
        while index < bytes.endIndex {
            if bytes[index] == 0x25 {
                guard index + 2 < bytes.endIndex,
                      isHexDigit(bytes[index + 1]),
                      isHexDigit(bytes[index + 2])
                else {
                    return false
                }
                index += 3
            } else {
                index += 1
            }
        }
        return true
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte)
            || (0x41...0x46).contains(byte)
            || (0x61...0x66).contains(byte)
    }

    private static func hasValidExplicitPort(_ value: String) -> Bool {
        guard let schemeEnd = value.range(of: "://") else { return false }
        let remainder = value[schemeEnd.upperBound...]
        let authorityEnd = remainder.firstIndex(where: { "/?#".contains($0) }) ?? remainder.endIndex
        var hostAndPort = remainder[..<authorityEnd]
        if let userInfoEnd = hostAndPort.lastIndex(of: "@") {
            hostAndPort = hostAndPort[hostAndPort.index(after: userInfoEnd)...]
        }

        let portText: Substring?
        if hostAndPort.first == "[" {
            guard let closingBracket = hostAndPort.firstIndex(of: "]") else { return false }
            let suffix = hostAndPort[hostAndPort.index(after: closingBracket)...]
            guard suffix.isEmpty || suffix.first == ":" else { return false }
            portText = suffix.isEmpty ? nil : suffix.dropFirst()
        } else if let separator = hostAndPort.lastIndex(of: ":") {
            portText = hostAndPort[hostAndPort.index(after: separator)...]
        } else {
            portText = nil
        }

        guard let portText else { return true }
        guard !portText.isEmpty,
              portText.allSatisfy(\.isNumber),
              let port = Int(portText)
        else {
            return false
        }
        return (0...65_535).contains(port)
    }
}
