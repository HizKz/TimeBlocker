# TimeBlocker

TimeBlockerは、macOSのメニューバーからカレンダーの予定とNotionのタスクを確認し、期限のタイミングで画面上に通知するアプリです。予定の追加やNotionタスクの作成・完了もメニューバーから操作できます。

## 主な機能

### カレンダー

- 通知対象にするカレンダーを選べます。カレンダー名と色で見分けられます。
- 予定開始の10分前・5分前・定刻から通知タイミングを選べます。
- メニューバー上の表示欄には次の予定とタスクの概要を表示し、次の予定まで6時間以内ならカウントダウンします。TimeBlockerをクリックすると、今日の予定とタスクの一覧を確認できます。
- 今日の予定は、予定名や場所で絞り込めます。
- 予定の開始時刻になると、半透明の全画面パネルで知らせます。同じ開始時刻の予定は一つのパネルにまとめます。
- パネルから予定のURLや会議リンクを開けます。5分・10分・15分後へのスヌーズと、通知を閉じる操作があります。
- アプリ起動時やMacのスリープ復帰時に、開始から設定した時間内の予定を通知します。通知猶予時間は1分・3分・5分・10分・15分から選べます（初期値は5分）。
- メニューバーから予定を追加できます。予定名、場所、URL、開始日時、所要時間、保存先カレンダーを指定できます。
- 初期の所要時間と保存先カレンダーを設定できます。カレンダーへの変更はEventKitを通してカレンダーアプリに保存されます。

### Notionタスク

- 単一のNotion Data Sourceに接続し、未完了タスクを表示します。期限切れや期限なしのタスクも一覧に残ります。
- 今日が期限のタスクを先に表示し、そのほかのタスクも別のまとまりで確認できます。
- 期限時刻が設定されたタスクは、同期時に期限を検知して全画面パネルで通知します。同じ期限時刻のタスクは一画面にまとめ、各タスクを個別に完了できます。同期は約60秒ごとなので、通知が期限時刻から最大約1分遅れることがあります。
- 「あとで通知」は表示中のタスク全体に適用され、5分・10分・15分から選べます。「通知を閉じる」でその通知を閉じられます。
- 日付だけの期限や期限なしのタスクは一覧に表示し、期限時刻の通知は出しません。
- メニューバーからタスクを追加できます。タスク名と、任意で時刻付きまたは日付のみの期限を指定できます。
- タスクを開く、完了にする、今すぐ同期する操作があります。完了状態はNotionに書き戻されます。
- 起動時、Notion設定の変更時、Macのスリープ復帰時に同期し、アプリ起動中は約60秒ごとに更新します。通信エラー時もカレンダーの同期・通知を続けます。

## 必要な環境

- macOS 14以降
- Xcode 15以降（ソースからビルドする場合）
- カレンダー機能を使う場合は、TimeBlockerにカレンダーへのフルアクセスを許可してください。
- Notion機能を使う場合は、Notion Integration Tokenと対象Data Sourceへのアクセス権が必要です。

## 起動方法

1. このリポジトリをCloneし、Xcodeプロジェクトを開きます。

   ```sh
   git clone https://github.com/HizKz/TimeBlocker.git
   cd TimeBlocker
   open TimeBlocker.xcodeproj
   ```

2. Xcodeで`TimeBlocker`スキームを選び、Runを実行します。
3. 初回起動時にカレンダーへのアクセスを許可します。
4. メニューバーのTimeBlockerをクリックして予定とタスクを確認します。各種設定は「設定」から開けます。

TimeBlockerはメニューバーアプリです。通常のDockアイコンやメインウィンドウは表示しません。アプリを終了するには、メニューバーのTimeBlockerを開いて「終了」を選びます。

## 配布用アプリの作成

配布用のUniversalアプリとDMGは、次のコマンドで作成できます。成果物は`dist/TimeBlocker.dmg`です。

DMGを開くと、TimeBlockerのアイコンとApplicationsフォルダを案内付きの背景に並べて表示します。

```sh
./scripts/package-release.sh
```

署名証明書を指定しない場合はアドホック署名で作成します。自分のMacでの確認用で、ほかのMacへ配布するとGatekeeperに止められる場合があります。一般向けに配布する場合はApple Developer ProgramのDeveloper ID Application証明書で署名し、公証してください。

Developer ID署名と公証がない配布版を別のMacで初めて開くときは、macOSが起動を止めることがあります。TimeBlockerをApplicationsフォルダへドラッグし、Applications内のアプリを一度開いてください。ブロックされた場合は「システム設定」→「プライバシーとセキュリティ」→「セキュリティ」へ進み、「このまま開く」を選んで確認画面でも「開く」を押します。

TimeBlockerはメニューバーアプリです。起動後もDockや通常のウィンドウには表示されず、画面上部のメニューバーにアイコンが表示されます。

v1.0.2はSparkle.frameworkの読み込み設定に不備があり、起動直後に終了します。v1.0.2を入れた場合は、v1.0.3のDMGをダウンロードし、Applications内のTimeBlockerを置き換えてください。v1.0.2から自動更新はできません。

Developer ID証明書をキーチェーンに登録済みで、公証用の`notarytool`プロファイルも作成済みの場合は、次のように実行します。

```sh
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="TimeBlocker-notary" \
./scripts/package-release.sh
```

`DEVELOPER_ID_APPLICATION`には`security find-identity -v -p codesigning`に表示される証明書名、`NOTARY_PROFILE`には`xcrun notarytool store-credentials`で登録したプロファイル名を指定します。

## 自動アップデート

v1.0.3からSparkleで更新を確認します。メニューバーまたは「設定」→「一般」から手動確認でき、自動確認も有効です。v1.0.2は起動できないため、まだv1.0.3へ入れ替えていない場合は一度手動でインストールしてください。

更新フィードは`appcast.xml`としてGitHubの`main`ブランチから配信します。次のリリースを作るときは、`CFBundleShortVersionString`と`CFBundleVersion`を増やし、アプリをビルドしてからEdDSA署名付き更新アーカイブを登録したフィードを生成します。同名の`TimeBlocker-${VERSION}.md`を`dist/updates`へ置くと、更新画面にリリースノートを表示できます。

```sh
VERSION="1.0.5"
mkdir -p dist/updates
ditto -c -k --sequesterRsrc --keepParent \
  dist/TimeBlocker.xcarchive/Products/Applications/TimeBlocker.app \
  "dist/updates/TimeBlocker-${VERSION}.zip"
dist/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast \
  --embed-release-notes \
  --download-url-prefix "https://github.com/HizKz/TimeBlocker/releases/download/v${VERSION}/" \
  dist/updates
cp dist/updates/appcast.xml appcast.xml
```

生成された`TimeBlocker-${VERSION}.zip`と`dist/TimeBlocker.dmg`を同じバージョンのGitHub Releaseへアップロードし、`appcast.xml`も`main`へpushしてください。過去バージョンのURLがそれぞれのGitHub Releaseを指していることも確認してください。更新用EdDSA秘密鍵はこのMacのログインキーチェーンに保存しています。秘密鍵はリポジトリやReleaseへ置かず、今後の署名に使えるようキーチェーンを保全してください。

## Notionとの接続

### 1. Notion Integrationを用意する

NotionでIntegrationを作成し、次の機能を許可します。

- **Read content**：Data Sourceとタスクを読み込むために必要です。
- **Update content**：タスクを完了にするために必要です。
- **Insert content**：TimeBlockerからタスクを追加するために必要です。

作成したIntegration Tokenは外部に公開しないでください。NotionのIntegration作成手順は[Notion APIの公式ガイド](https://developers.notion.com/docs/create-a-notion-integration)を参照してください。

### 2. Data SourceをIntegrationに共有する

対象のデータベースをTimeBlockerのIntegrationに共有します。共有されていないData Sourceは、正しいIDを入力しても取得できません。

### 3. TimeBlockerで接続する

1. TimeBlockerの「設定」→「Notion」を開きます。
2. Integration TokenとData Source IDを入力します。
3. 「Data Sourceのスキーマを取得」を押します。
4. タイトル、期限、完了の各プロパティを選びます。
5. 完了列の種類を`Status`、`Select`、`Checkbox`から選びます。`Status`または`Select`では、完了を表す値も選択します。
6. 「今すぐ同期」を押します。

期限プロパティにはNotionのDate列を指定してください。期限がないタスクを作る場合も、期限列そのものは設定が必要です。`Checkbox`ではチェック済みを完了として扱います。

## 設定

「設定」には「カレンダー」「Notion」「一般」の項目があります。

- **カレンダー**：通知対象にするカレンダーを選び、アクセス許可の状態を確認できます。
- **Notion**：Token、Data Source ID、タイトル・期限・完了列を設定し、スキーマ取得や手動同期を行えます。TokenはmacOSのKeychainに保存されます。
- **一般 → 通知**：予定開始の10分前・5分前・定刻から通知タイミングを選べます。スリープ復帰後に通知する予定の猶予時間も設定できます。また、10秒後のテスト通知を実行できます。
- **一般 → 表示**：通知パネルをすべてのディスプレイ、またはメインディスプレイのみに表示できます。
- **一般 → 予定の追加**：新しい予定の初期所要時間と初期保存先カレンダーを設定できます。

## データとプライバシー

- カレンダーの予定と通知履歴はMac上で扱い、TimeBlocker運営者のサーバーには送信しません。
- Notion連携では、入力したIntegration Tokenを使ってTimeBlockerからNotion APIへ直接通信します。TokenはKeychainに保存し、Notionのページ内容やタスク操作はNotion側に反映されます。
- Notionの接続設定や通知済みタスクの記録はMac上に保存されます。
- Notionとの通信に失敗した場合、Notionの状態欄にエラーが表示されます。カレンダー機能は独立して動作します。

## 現在の制限

- Notionは一つのData Sourceに接続します。
- 通知を受け取るにはTimeBlockerを起動しておく必要があります。ログイン時の自動起動には対応していません。
- 終日カレンダー予定は予定一覧・開始時刻通知の対象外です。
- Notionの期限通知は時刻付きの期限が対象です。日付だけの期限は一覧表示のみです。

## ライセンス

TimeBlockerは[MIT License](LICENSE)のもとで公開しています。
