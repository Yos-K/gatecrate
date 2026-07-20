# core/ — 汎用コア層

スタック非依存のハーネスコンポーネント。どのプロジェクト（Android/JVM/Web等）でも追加設定なしで動作する。

## 含まれるスクリプト

| ファイル | 用途 |
|---|---|
| check-conventional-title.sh | Conventional Commits タイトル検証 |
| check-no-committed-secrets.sh | コミット済みシークレット検出 |
| check-file-line-limit.sh | ファイル行数上限チェック（言語非依存・300行ルール） |
| check-adr-review.sh | ADR レビュー宣言ゲート（feat/fix コミットに `ADR-Review:` トレーラを1つ強制・参照先の構造検査は宣言コミット時点） |
| check-interaction-command-traceability.sh | model→実装→挙動テストのトレーサビリティガード（契約台帳の state+command が遷移にモデル化され、実装/テストの path+locator が生存していることを検査） |
| probe-gate-liveness.sh | 予防型ゲートの生存証明（合成違反を注入し ALIVE/DEAD を判定・ROADMAP P4 二階ループ） |
| version-env.sh | VERSIONファイル読み込み・エクスポート |
| version-show.sh | VERSION表示 |
| version-check.sh | VERSIONとマニフェストの一致検証 |
| start-work.sh | 作業ブランチ作成（mainから最新取得） |
| ResizePng.java | PNG画像リサイズユーティリティ |
| StripImageMetadata.java | 画像メタデータ除去・リサイズ |
| prepare-play-store-screenshot.sh | Play Storeスクリーンショット準備 |

## 設定が必要なパラメータ

### version-check.sh

| パラメータ | 環境変数 | 説明 | 例 |
|---|---|---|---|
| マニフェストファイルパス | `MANIFEST_PATH` | versionName/versionCodeを宣言するファイル | `src/main/AndroidManifest.xml` |

`MANIFEST_PATH` が未設定の場合、マニフェスト一致チェックはスキップされる（VERSIONファイルの形式検証のみ実行）。

### StripImageMetadata.java / prepare-play-store-screenshot.sh

| パラメータ | 環境変数 | デフォルト値 | 説明 |
|---|---|---|---|
| 出力幅 | `TARGET_WIDTH` | `1080` | Play Store縦向きスクリーンショット幅(px) |
| 出力高 | `TARGET_HEIGHT` | `1920` | Play Store縦向きスクリーンショット高(px) |

## 使用例

```sh
# コミットタイトル検証
sh core/scripts/check-conventional-title.sh "feat: add new feature"

# シークレット検出（git管理下のプロジェクトルートで実行）
sh core/scripts/check-no-committed-secrets.sh

# 予防型ゲートの生存証明（kit 自身の予防ゲートが今も「効いている」かを確認）
sh core/scripts/probe-gate-liveness.sh

# バージョン確認
sh core/scripts/version-show.sh

# Androidプロジェクトでのバージョン一致検証
MANIFEST_PATH=src/main/AndroidManifest.xml sh core/scripts/version-check.sh

# スクリーンショット準備（Java 8+が必要）
sh core/scripts/prepare-play-store-screenshot.sh input.png output.jpg
```
# updated for sync test - 20260607163028
