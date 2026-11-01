# Xcode Cloud での手動 TestFlight 配布

TestFlight に配布したいときだけ、 対象ブランチを選んで配布ワークフローを手動実行する。 ジョブの起動は手動に限定し、 実行時に検証・テスト・アーカイブ・配布を行う。 実機で確認したビルドとコミットを PR に記録し、 OK なら main にマージする。 確認後に追加の push があれば、 必要なタイミングで新しいコミットを再配布・再確認する。

## リポジトリ側の実装

- [ci_post_clone.sh](../../ci_scripts/ci_post_clone.sh#L12) は、 Xcode Cloud の各ソースビルド環境で依存ツールを用意し、 [ci-check](../../Makefile#L95-L99) を実行する。
- [mise.toml](../../mise.toml#L1) に固定した SwiftLint を使用する。 Homebrew から jq、 ripgrep、 mise を導入し、 インストールや検証が失敗したらビルドを止める。
- [ci-check](../../Makefile#L95-L99) は、 lint、 英語・日本語カタログ、 翻訳検証のテスト、 配布設定、 CI スクリプトのテスト、 コアパッケージのテストを実行する。 アプリ・統合・UI テストは Xcode Cloud の Test action が実行する。
- [配布設定検証](../../Scripts/validate-testflight-configuration.sh#L177) は、 アプリとウィジェットの Debug / Release 全4構成で同じ正の整数のビルド番号と同じバージョンを要求する。 特定のビルド番号には固定しない。
- 配布ワークフローは Apple 標準の `CI_START_CONDITION` が `manual` または `manual_rebuild` の場合だけ進む。 push、 PR、 schedule による配布起動は、 依存ツールの導入や検証を始める前に拒否する。 独自の環境変数は使用しない。
- `test-without-building` は、 ソースを持たないテスト実行環境でも動くよう、 依存インストールとソース検証を省く。 対応する `build-for-testing` 環境で同じ検証を済ませる。

ローカルで同じ検証を実行する場合:

  ```sh
  mise exec -- make ci-check
  ```

アプリ・統合・UI テストをローカルでも実行する場合は、 [test-unit](../../Makefile#L55-L59)、 [test-integration](../../Makefile#L61-L64)、 [test-ui](../../Makefile#L66-L69) を使用する。

## 初回接続

初回の Xcode Cloud 接続とサービス側のワークフロー設定は、 このリポジトリのスクリプトだけでは作成されない。 次の設定は所有者が Xcode と App Store Connect で行う。

1. この変更を含むブランチを GitHub に push する。 リポジトリは [ttakanawa/notification-ios](https://github.com/ttakanawa/notification-ios)。
2. Xcode で [NotificationManager.xcodeproj](../../NotificationManager.xcodeproj) を開き、 Report navigator の Cloud から Xcode Cloud の初期設定を開始する。
3. 製品は `NotificationManager`、 Apple Developer team は `6N3QVPQDH7`、 アプリは既存の `org.tknw.punctual` を選択する。
4. GitHub リポジトリへのアクセスを許可する。
5. 最初のビルドを開始する前に、 初期ワークフローを下記の手動配布設定に変更する。 自動開始条件を削除し、 この変更を含むブランチで最初のビルドを手動実行する。

初回接続後は App Store Connect の対象アプリ → Xcode Cloud からワークフローを編集・実行できる。

## ワークフロー設定

作成するワークフローは手動配布用の1つだけとする。

| 項目 | 値 |
| ------ | ------ |
| 名前 | `TestFlight`。 用途を見分ける表示名で、 スクリプトは名前に依存しない |
| プロジェクト | [NotificationManager.xcodeproj](../../NotificationManager.xcodeproj) |
| Scheme | `NotificationManager` |
| Xcode | 26系以降の利用可能な安定版を選び、 初回成功したバージョンに固定 |
| 開始条件 | Manual Start - Branch のみ。 任意の作業ブランチを選べるようにする |
| 環境変数 | 独自の変数は追加しない |
| Actions | Test と Archive |
| Test action | iOS、 アプリ・統合・UI の全テストターゲット、 Required To Pass を有効化 |
| テスト端末 | iPhone と iPad を各1種類指定 |
| Archive | iOS、 Release、 Distribution Preparation は App Store Connect |
| 配布 postaction | TestFlight の内部テスター向け配布 → 用意した内部テスターグループ |

パッケージは Swift 6.2 以降を要求する。 [共有 scheme](../../NotificationManager.xcodeproj/xcshareddata/xcschemes/NotificationManager.xcscheme#L16) に既存の3つのテストターゲットが含まれている。 Apple Intelligence の実モデル品質テストは対応する実機が必要で、 シミュレーターの成功だけでは確認できない。

Xcode のワークフロー編集画面では、 左側の項目から設定する。

1. Start Conditions の Branch Changes を削除し、 Manual Start - Branch を残す。 PR、 schedule、 tag による開始条件も設定しない。
2. Actions の横の「+」から Test と Archive を追加する。 Test はビルドも行うため、 既存の Build - iOS は削除する。
3. Post-Actions の横の「+」から内部テスター向けの TestFlight 配布を追加し、 対象グループを選択する。
4. 保存前に、 他の有効なワークフローにも自動開始条件が残っていないことを確認する。

自動開始条件を削除するのは、 push のたびに Cloud ジョブが起動して利用枠を消費することを防ぐため。 スクリプトの手動起動チェックは、 誤って自動開始条件を追加したときに配布を止めるための補助であり、 ジョブの起動自体は防げない。

この CI スクリプトを含むブランチを選択する。 別の機能ブランチを配布する場合は、 先にこの変更を取り込む。

Test と Archive は独立した環境で実行される。 直列の Test → Archive を前提にしない。 Test を Required To Pass にし、 必須 action の成功後に配布する。

Archive は内部・外部テストの両方に利用できる形式とし、 このワークフローの Post-Actions は内部テスターへの配布だけを行う。 友人などへ配る場合は、 後から App Store Connect で同じビルドを外部テスターグループに追加し、 ベータ審査へ提出する。 初回の外部配布には審査が必要で、 この操作のために再ビルドする必要はない。

## 配布前のアカウント設定

- App Store Connect で内部テスターグループを作り、 自分を追加する。 配布 postaction の対象にこのグループを指定する。
- アプリの App ID `org.tknw.punctual` とウィジェットの App ID `org.tknw.punctual.widget` の両方に `group.org.tknw.punctual` を割り当てる。
- アプリの CloudKit container は `iCloud.org.tknw.punctual`。 ローカルの entitlement と Developer Portal の割り当てを照合する。
- App Store Connect → Xcode Cloud → Settings → Build Number で、 次の番号を現在の version `1.0` の既存ビルドと重複しない値にする。 番号の増加は Xcode Cloud に任せる。
- チームの Xcode Cloud 利用枠を確認する。 Apple Developer Program には月25 compute hours が含まれる。 Test と Archive の別環境や複数テスト端末の時間は合算される。

配布用証明書とプロファイルは Xcode Cloud の自動署名で管理する。 この構成では認証キーや証明書を Git リポジトリに保存する必要はない。

## 日常の操作と初回の完成確認

1. 配布したい作業ブランチを push する。 この操作だけでは Cloud ジョブを起動しない。
2. Xcode または App Store Connect の Xcode Cloud で TestFlight ワークフローの Start Build を選ぶ。
3. 確認したい作業ブランチを選び、 開始する。 タグは作らない。
4. Cloud のログでコミット、 テスト結果、 Archive と配布結果を確認する。
5. Apple 側の処理完了後に、 内部テスターが TestFlight でそのビルドをインストールできることを確認する。
6. 実機で通知、 iCloud 同期、 ウィジェットからの起動と共有データを確認する。 確認したビルド番号とコミットを PR に記録し、 OK なら main にマージする。

初回の完成条件は、 手動開始したブランチのコミットが内部テスターへ配布され、 実機で確認できること。 ローカルのスクリプトテストや Cloud の Archive 成功だけでは、 配布完了とは扱わない。

## 公式資料

- [Xcode Cloud 初期設定](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow)
- [カスタムビルドスクリプト](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts)
- [依存ツールの導入](https://developer.apple.com/documentation/xcode/making-dependencies-available-to-xcode-cloud)
- [環境変数](https://developer.apple.com/documentation/xcode/environment-variable-reference)
- [Actions の設定](https://developer.apple.com/documentation/xcode/configuring-your-xcode-cloud-workflow-s-actions)
- [配布ワークフロー](https://developer.apple.com/documentation/xcode/creating-a-workflow-that-builds-your-app-for-distribution)
- [内部 TestFlight 配布](https://developer.apple.com/documentation/xcode/distributing-your-xcode-cloud-builds-through-testflight)
- [外部テスターへの配布](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers)
- [ビルド番号](https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds)
- [料金と compute hours](https://developer.apple.com/xcode-cloud/get-started/)
