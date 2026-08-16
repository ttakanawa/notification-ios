import Testing

@testable import NotificationManager

struct NotificationContentTruncatorTests {
    @Test func extendedGraphemeClustersRemainWholeWithinUTF8Limit() {
        let family = "👨‍👩‍👧‍👦"
        let value = NotificationContentTruncator().truncate(
            String(repeating: family, count: 300),
            maximumBytes: 2_048,
            ellipsis: "…"
        )

        #expect(value == String(repeating: family, count: 81) + "…")
        #expect(value.utf8.count == 2_028)
        #expect(!value.contains("�"))
    }

    @Test func truncationIncludesEllipsisInsideExactByteLimit() {
        let value = NotificationContentTruncator().truncate(
            String(repeating: "a", count: 300),
            maximumBytes: 256,
            ellipsis: "…"
        )

        #expect(value == String(repeating: "a", count: 253) + "…")
        #expect(value.utf8.count == 256)
    }

    @Test func valueWithinLimitIsReturnedUnchanged() {
        let original = "旅程 👨‍👩‍👧‍👦"

        #expect(
            NotificationContentTruncator().truncate(
                original,
                maximumBytes: original.utf8.count,
                ellipsis: "…"
            ) == original)
    }

    @Test func nonPositiveLimitAndOversizedEllipsisReturnNoPartialGrapheme() {
        let truncator = NotificationContentTruncator()

        #expect(truncator.truncate("value", maximumBytes: 0, ellipsis: "…").isEmpty)
        #expect(truncator.truncate("value", maximumBytes: -1, ellipsis: "…").isEmpty)
        #expect(truncator.truncate("value", maximumBytes: 2, ellipsis: "…").isEmpty)
    }
}
