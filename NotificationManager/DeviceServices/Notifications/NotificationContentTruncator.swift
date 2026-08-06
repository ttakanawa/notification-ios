struct NotificationContentTruncator: Sendable {
    func truncate(_ value: String, maximumBytes: Int, ellipsis: String) -> String {
        guard maximumBytes > 0 else { return "" }
        guard value.utf8.count > maximumBytes else { return value }
        guard ellipsis.utf8.count <= maximumBytes else { return "" }

        let contentLimit = maximumBytes - ellipsis.utf8.count
        var result = ""
        var byteCount = 0
        for character in value {
            let characterBytes = String(character).utf8.count
            guard byteCount + characterBytes <= contentLimit else { break }
            result.append(character)
            byteCount += characterBytes
        }
        return result + ellipsis
    }
}
