import Foundation

public struct DisplayTextSegment: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case text, remaining, elapsed
    }

    public let kind: Kind
    public let text: String

    public init(kind: Kind = .text, text: String = "") {
        self.kind = kind
        self.text = text
    }
}

public struct LiveActivityDisplayText: Codable, Hashable, Sendable {
    public let title: [DisplayTextSegment]
    public let body: [DisplayTextSegment]

    public init(title: [DisplayTextSegment], body: [DisplayTextSegment]) {
        self.title = title
        self.body = body
    }
}

public struct DisplayTemplateValues: Sendable {
    public let title: String
    public let notes: String
    public let notificationTime: String
    public let timeZone: String

    public init(title: String, notes: String?, notificationTime: String, timeZone: String) {
        self.title = title
        self.notes = notes ?? ""
        self.notificationTime = notificationTime
        self.timeZone = timeZone
    }
}

public enum DisplayTemplateError: Error, Equatable, Sendable {
    case tooLong
    case invalidBraces
    case unknownField(String)
    case timerUnavailable
    case emptyTitle
}

/// Parses a small, non-executable language. Doubled braces represent literal braces.
public enum DisplayTemplateRenderer {
    public static let fields = ["title", "notes", "notificationTime", "timeZone"]
    public static let timerFields = ["remaining", "elapsed"]
    public static let maximumTemplateBytes = 1_024

    public static func render(
        _ template: String, values: DisplayTemplateValues, allowsTimers: Bool
    ) throws -> [DisplayTextSegment] {
        guard template.utf8.count <= maximumTemplateBytes else {
            throw DisplayTemplateError.tooLong
        }
        var result: [DisplayTextSegment] = []
        var literal = ""
        var index = template.startIndex
        func appendLiteral() {
            guard !literal.isEmpty else { return }
            result.append(DisplayTextSegment(text: literal))
            literal = ""
        }
        while index < template.endIndex {
            let character = template[index]
            let next = template.index(after: index)
            if character == "{" {
                if next < template.endIndex, template[next] == "{" {
                    literal.append("{")
                    index = template.index(after: next)
                    continue
                }
                guard let close = template[next...].firstIndex(of: "}") else {
                    throw DisplayTemplateError.invalidBraces
                }
                let name = String(template[next..<close])
                switch name {
                case "title": literal += values.title
                case "notes": literal += values.notes
                case "notificationTime": literal += values.notificationTime
                case "timeZone": literal += values.timeZone
                case "remaining", "elapsed":
                    guard allowsTimers else { throw DisplayTemplateError.timerUnavailable }
                    appendLiteral()
                    result.append(
                        DisplayTextSegment(kind: name == "remaining" ? .remaining : .elapsed))
                default: throw DisplayTemplateError.unknownField(name)
                }
                index = template.index(after: close)
            } else if character == "}" {
                guard next < template.endIndex, template[next] == "}" else {
                    throw DisplayTemplateError.invalidBraces
                }
                literal.append("}")
                index = template.index(after: next)
            } else {
                literal.append(character)
                index = next
            }
        }
        appendLiteral()
        guard result.count <= 32 else { throw DisplayTemplateError.tooLong }
        return result
    }

    public static func liveActivity(
        title: String, body: String, values: DisplayTemplateValues
    ) throws -> LiveActivityDisplayText {
        let titleSegments = try render(title, values: values, allowsTimers: true)
        let bodySegments = try render(body, values: values, allowsTimers: true)
        guard
            titleSegments.contains(where: {
                $0.kind != .text || !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        else {
            throw DisplayTemplateError.emptyTitle
        }
        let result = LiveActivityDisplayText(title: titleSegments, body: bodySegments)
        // Reserve space for ActivityKit metadata and the ordinary timing state within 4 KB.
        guard try JSONEncoder().encode(result).count <= 1_800 else {
            throw DisplayTemplateError.tooLong
        }
        return result
    }

    public static func notification(
        title: String, body: String, values: DisplayTemplateValues
    ) throws -> (title: String, body: String) {
        let title = try render(title, values: values, allowsTimers: false).map(\.text).joined()
        let body = try render(body, values: values, allowsTimers: false).map(\.text).joined()
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DisplayTemplateError.emptyTitle
        }
        return (title, body)
    }
}
