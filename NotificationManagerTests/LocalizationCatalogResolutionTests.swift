import Foundation
import Testing

@testable import NotificationManager

struct LocalizationCatalogResolutionTests {
    @Test func liveProviderResolvesRepresentativeKeyFromEveryOwnedCatalog() {
        let provider = LocalizedTextProvider.live
        let fixtures: [(key: String, english: String, japanese: String)] = [
            ("common.retry", "Retry", "再試行"),
            ("reminder.form.error.title-required", "A title is required.", "タイトルは必須です。"),
            ("reminder.action.cancel", "Cancel", "キャンセル"),
            (
                "localization.source-time.sentence",
                "Source time: %1$@ (%2$@).",
                "基準時刻：%1$@（%2$@）。"
            ),
            ("settings.title", "Settings", "設定"),
            ("tags.action.create", "Create Tag", "タグを作成"),
            (
                "tags.picker.create-suggestion",
                "Create “%1$@”",
                "「%1$@」を作成"
            ),
            ("data_unavailable.title", "Data Unavailable", "データを利用できません")
        ]

        for fixture in fixtures {
            #expect(
                provider.value(
                    for: fixture.key,
                    locale: Locale(identifier: "en_US")
                ) == fixture.english
            )
            #expect(
                provider.value(
                    for: fixture.key,
                    locale: Locale(identifier: "ja_JP")
                ) == fixture.japanese
            )
        }
    }

    @Test func capacityMessageUsesReminderFormFormat() {
        let provider = LocalizedTextProvider.live
        let locale = Locale(identifier: "en_US")
        let format = provider.value(
            for: "reminder.form.capacity-confirmation.message",
            locale: locale
        )
        let message = String(
            format: format,
            locale: locale,
            arguments: [Int64(60)]
        )
        #expect(message.contains("up to 60 notifications"))
        #expect(message.hasSuffix("Save anyway?"))
    }
}
