# Xcode Cloud での検証と手動 TestFlight 配布

作業ブランチを push すると検証する。 TestFlight に配布したいときは、 対象ブランチを選んで配布ワークフローを手動実行する。 実機で確認したビルドとコミットを PR に記録し、 OK なら main にマージする。 確認後に追加の push があれば、 新しいコミットで再配布・再確認する。

## リポジトリ側の実装

- [ci_post_clone.sh](../../ci_scripts/ci_post_clone.sh#L12) は、 Xcode Cloud の各ソースビルド環境で依存ツールを用意し、 [Makefile](../../Makefile#L95) の `ci-check` を実行する。
- [mise.toml](../../mise.toml#L1) に固定した SwiftLint を使用する。 Homebrew から jq、 ripgrep、 mise を導入し、 インストールや検証が失敗したらビルドを止める。
- `ci-check` は、 lint、 英語・日本語カタログ、 翻訳検証のテスト、 配布設定、 CI スクリプトのテスト、 コアパッケージのテストを実行する。 アプリ・統合・UI テストは Xcode Cloud の Test action が実行する。
- [配布設定検証](../../Scripts/validate-testflight-configuration.sh#L177) は、 アプリとウィジェットの Debug / Release 全4構成で同じ正の整数のビルド番号と同じバージョンを要求する。 特定のビルド番号には固定しない。
- 配布ワークフローは `CI_START_CONDITION` が `manual` または `manual_rebuild` の場合だけ進む。 push、 PR、 schedule による配布起動は拒否する。 検証ワークフローの Archive action も拒否する。
- `test-without-building` は、 ソースを持たないテスト実行環境でも動くよう、 依存インストールとソース検証を省く。 対応する `build-for-testing` 環境で同じ検証を済ませる。

ローカルで同じ検証を実行する場合:

  ```sh
  mise exec -- make ci-check
  ```

アプリ・統合・UI テストをローカルでも実行する場合は、 [Makefile](../../Makefile#L55) の `test-unit`、 `test-integration`、 `test-ui` を使用する。

## 初回接続

初回の Xcode Cloud 接続とサービス側のワークフロー設定は、 このリポジトリのスクリプトだけでは作成されない。 次の設定は所有者が Xcode と App Store Connect で行う。

1. この変更を含むブランチを GitHub に push する。 リポジトリは [ttakanawa/notification-ios](https://github.com/ttakanawa/notification-ios)。
2. Xcode で [NotificationManager.xcodeproj](../../NotificationManager.xcodeproj) を開き、 Report navigator の Cloud から Xcode Cloud の初期設定を開始する。
3. 製品は `NotificationManager`、 Apple Developer team は `6N3QVPQDH7`、 アプリは既存の `org.tknw.punctual` を選択する。
4. GitHub リポジトリへのアクセスを許可する。
5. 最初のビルドを開始する前に、 初期ワークフローを下記の検証用設定に変更し、 環境変数を追加する。 この変更を含むブランチで最初のビルドを実行する。

初回接続後は App Store Connect の対象アプリ → Xcode Cloud からワークフローを編集・実行できる。

## ワークフロー設定

共通設定:

| 項目 | 値 |
| ------ | ------ |
| プロジェクト | [NotificationManager.xcodeproj](../../NotificationManager.xcodeproj) |
| Scheme | `NotificationManager` |
| Xcode | 26系以降の利用可能な安定版を選び、 初回成功したバージョンに固定 |
| Test action | iOS、 アプリ・統合・UI の全テストターゲット、 Required To Pass を有効化 |
| テスト端末 | iPhone と iPad を各1種類指定 |

パッケージは Swift 6.2 以降を要求する。 [共有 scheme](../../NotificationManager.xcodeproj/xcshareddata/xcschemes/NotificationManager.xcscheme#L16) に既存の3つのテストターゲットが含まれている。 Apple Intelligence の実モデル品質テストは対応する実機が必要で、 シミュレーターの成功だけでは確認できない。

### Verify ワークフロー

| 項目 | 値 |
| ------ | ------ |
| 名前 | `Verify` |
| 開始条件 | Branch Changes → Any Branch |
| 環境変数 | `PUNCTUAL_CI_MODE=verify` |
| Actions | Test |
| 配布 postaction | 設定しない |

Test action 自体がテスト用アプリをビルドするため、 別の Build action は不要。

### TestFlight ワークフロー

| 項目 | 値 |
| ------ | ------ |
| 名前 | `TestFlight` |
| 開始条件 | 手動開始用のブランチ条件があれば使用。 なければ Branch Changes を予約名 `__manual_testflight_only__` のみに設定し、 この名前のブランチを作成・push しない |
| 環境変数 | `PUNCTUAL_CI_MODE=testflight` |
| Actions | Test と Archive。 Test は Required To Pass を有効化 |
| Archive | iOS、 Release、 Deployment Preparation は TestFlight (Internal Testing Only) |
| 配布 postaction | TestFlight → 用意した内部テスターグループ |

Apple の配布手順では、 自動では成立しない開始条件を設定して手動実行する方法を案内している。 配布側には Any Branch、 PR、 schedule、 tag による自動開始条件を追加しない。 誤って追加した場合も、 スクリプトが非手動起動を拒否する。

Test と Archive は独立した環境で実行される。 直列の Test → Archive を前提にしない。 Test を Required To Pass にし、 必須 action の成功後に配布する。

## 配布前のアカウント設定

- App Store Connect で内部テスターグループを作り、 自分を追加する。 配布 postaction の対象にこのグループを指定する。
- アプリの App ID `org.tknw.punctual` とウィジェットの App ID `org.tknw.punctual.widget` の両方に `group.org.tknw.punctual` を割り当てる。
- アプリの CloudKit container は `iCloud.org.tknw.punctual`。 ローカルの entitlement と Developer Portal の割り当てを照合する。
- App Store Connect → Xcode Cloud → Settings → Build Number で、 次の番号を現在の version `1.0` の既存ビルドと重複しない値にする。 番号の増加は Xcode Cloud に任せる。
- チームの Xcode Cloud 利用枠を確認する。 Apple Developer Program には月25 compute hours が含まれる。 Test と Archive の別環境や複数テスト端末の時間は合算される。

配布用証明書とプロファイルは Xcode Cloud の自動署名で管理する。 この構成では認証キーや証明書を Git リポジトリに保存する必要はない。

## 日常の操作と初回の完成確認

1. 作業ブランチを push し、 Verify の結果を確認する。
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
- [ビルド番号](https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds)
- [料金と compute hours](https://developer.apple.com/xcode-cloud/get-started/)
