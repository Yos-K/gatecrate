# adapters/android-jvm/ — Android-JVM アダプタ層

このディレクトリには、Android/JVM スタック向けのハーネスコンポーネントを格納する。
汎用コア（`core/`）と異なり、Android SDK・Gradle・JVM 直接実行環境を前提とする。

## 含まれるコンポーネント

### scripts/（スクリプト）

| ファイル | 用途 | 必須環境変数 |
|---|---|---|
| check-file-sizes.sh | Javaソースの行数チェック | FITNESS_MAX_LINES (opt) |
| check-test-smells.sh | Javaテストのスメル検出 | なし |
| check-release-basics.sh | リリースAPK検証 | APP_NAME |
| run-unit-tests.sh | JUnit5/ArchUnit/jqwik実行（Kotlin/Java混在対応） | BUILDCONFIG_PACKAGE |
| run-mutation-tests.sh | PITestミューテーション（Kotlin/Java混在対応） | BUILDCONFIG_PACKAGE, TARGET_CLASSES, TARGET_TESTS |
| android-kotlin-compile.sh | kt/java混在コンパイルヘルパー（sourced） | KOTLIN_VERSION (opt), KOTLIN_JVM_TARGET (opt) |
| check-native-libs.sh | APK内 native lib(.so)同梱検証 | NATIVE_LIB_APK, NATIVE_LIB_NAMES |
| test-balance-report.sh | small/medium/large比率確認 | なし |
| android-dependency-env.sh | Android依存クラスパス組み立て | なし |
| prepare-android-dependencies.sh | Android依存ダウンロード | なし |
| prepare_android_dependencies.py | 同上（Pythonロジック） | なし |
| build-free-debug-apk.sh | Free デバッグAPKビルド | APP_PACKAGE (opt) |
| build-pro-debug-apk.sh | Pro デバッグAPKビルド | APP_PACKAGE (opt) |
| build-release-aab.sh | リリースAABビルド | BUILDCONFIG_PACKAGE, APP_RELEASE_KEYSTORE, BUNDLETOOL_JAR |
| build-release-apk.sh | リリースAPKビルド | BUILDCONFIG_PACKAGE, APP_RELEASE_KEYSTORE |
| build-signed-release.sh | 署名リリース（対話型） | APP_RELEASE_KEYSTORE |
| smoke-debug-app.sh | Termux/ADBスモーク | APP_PACKAGE |
| emulator-smoke.sh | CI エミュレータスモーク | APP_PACKAGE, APP_OPEN_ACTION, APP_EXTRA_* |
| capture-debug-screenshot.sh | デバッグスクリーンショット | なし |
| capture-play-store-screenshot.sh | Play Storeスクリーンショット | なし |
| capture-theme-screenshots.sh | テーマ別スクリーンショット | APP_PACKAGE, APP_OPEN_ACTION, APP_THEMES, APP_THEME_PREF_KEY |
| export-play-store-feature-graphic.sh | フィーチャーグラフィック生成 | なし |
| export-play-store-icon.sh | アイコン生成 | なし |
| ExportPlayStoreFeatureGraphic.java | フィーチャーグラフィックJavaソース | — |
| ExportPlayStoreIcon.java | アイコンJavaソース | — |
| version-bump.sh | バージョンインクリメント | なし |
| version-apply-manifest.sh | マニフェストへのバージョン反映 | なし |
| version-code-bump.sh | versionCode のみ更新 | なし |
| create-release-keystore.sh | キーストア生成 | なし |

### workflows/（GitHub Actionsワークフロー）

| ファイル | 用途 |
|---|---|
| ci.yml | フィットネスゲート + JVMテスト + Gradleビルド |
| mutation.yml | PITestミューテーション（変更検知スキップ付き） |
| device-smoke.yml | エミュレータスモーク（手動トリガー） |

### gradle/（Gradle設定）

| ファイル | 用途 |
|---|---|
| build.gradle | ルート build.gradle（AGP宣言） |

## CI のカスタマイズ（ci.yml はテンプレート）

`workflows/ci.yml` の `test`/`gradle-build` ジョブは **localmd-reader の形に強く依存**している:
Play Billing 依存の取得（`prepare-android-dependencies.sh`）、free/pro flavor、署名、`bundleRelease`。
**だから汎用 Android プロジェクトにそのままは使えない。Gradle タスクを自分のプロジェクトに合わせて
差し替える**（fitness ジョブ＝core 衛生だけは無改変で動く）。

実証: 最小 Android プロジェクト（単一モジュール・flavor/署名/billing なし）を private 消費者で配線し、
ci.yml を `:app:assembleDebug` + `:app:testDebugUnitTest` に差し替えて、**実 pull_request で
fitness + android-build を緑**にした（AGP 8.13.1 / Gradle 8.14 / Android SDK 35、約1分20秒）。
学び: **core 衛生 CI は turnkey だが、Android のビルド/テスト CI はプロジェクト固有のカスタマイズが要る**。

## Kotlin ロジック層の test/mutation（gatecrate#25 Gap1）

**なぜ**: 従来 `run-{unit,mutation}-tests.sh` は `javac` だけで `.kt` を扱えず、AGP+Kotlin
プロジェクトの Kotlin ロジック層を「Android SDK 不要・JVM 直接実行」の経路で回せなかった
（kotlin アダプタは非Android前提）。**だから** `.kt` があれば `kotlinc` で先にコンパイルして
`.class` を混ぜ、既存の JUnit/PITest 経路にそのまま流す（Gradle/AGP 非依存を維持）。

- `.kt` が main/test ソースルートにあれば自動で有効化。`.kt` が無ければ `kotlinc` はダウンロード
  されず、従来の Java 限定挙動と完全に一致する。
- 混在コンパイルは共通ヘルパー `android-kotlin-compile.sh` に集約（2スクリプト間のドリフト防止）。
  **`run-unit-tests.sh` / `run-mutation-tests.sh` は本ヘルパーを source する必須依存**（純 Java でも
  コンパイルは `ak_compile` 経由）。採用時は必ず一緒に同梱すること（欠落時はスクリプトが明示エラーで落ちる）。
- **マルチモジュール対応**: `JVM_MAIN_SRC_DIRS` / `JVM_TEST_SRC_DIRS`（repo-root 相対・スペース区切り）
  でソースルートを指定できる（既定は単一モジュール `src/main/java src/main/kotlin`）。
  例: vibe-coder は `:exec` モジュールなので `JVM_MAIN_SRC_DIRS="exec/src/main/kotlin"`。
- **Kotlin `internal` の可視性**: main と test を別々の kotlinc で compile するため、Gradle と同じく
  `-Xfriend-paths`（test compile に main 出力を渡す）で main の `internal` 宣言を test から見せている。
  これが無いと `internal` を使う Kotlin（idiomatic）で test がコンパイル不能になる。ヘルパーが自動処理。
- **Android 依存ファイルの除外**: `android.*` を import するクラスは JVM 直接コンパイル不可なので、
  `MAIN_SOURCES_EXCLUDE`（compile 時の glob 除外・既定 `*/presentation/*`）で外す。
  例: vibe-coder は `MAIN_SOURCES_EXCLUDE="*LibDirExecProbe.kt"`（純関数 classify のみ残す）。
- 版は `KOTLIN_VERSION`（既定 2.0.21）/ `KOTLIN_JVM_TARGET`（既定 17）で上書き可。
- mutation.yml の変更検知も `.kt` と Kotlin ソース dir を対象に含むよう拡張済み。
- **PITest の Kotlin 注意**: PITest 標準ミューテータは Kotlin が生成する null チェック等の
  バイトコードにも変異を作るため、複雑な Kotlin では等価変異（殺せない変異）でスコアが下がりうる。
  その場合は `EXCLUDED_CLASSES` で対象を絞るか、Kotlin 特化の Arcmutate プラグイン導入を検討する。
- **検証状況**: 実 AGP+Kotlin 消費者 **vibe-coder の `:exec` モジュール（マルチモジュール・Kotlin・
  JUnit4・NDK）で実走確認済み**。`run-unit-tests.sh`（JUnit4 テスト5件を vintage で実行・緑）/
  `run-mutation-tests.sh`（純関数 `classify` の変異を 100% kill・閾値80%クリア）。このループで
  マルチモジュール／`internal` 可視性／Android 依存除外の3点を発見し、上記の対応を入れた。

## NDK / native build（gatecrate#25 Gap2）

**なぜ**: `externalNativeBuild { cmake {} }` を持つプロジェクトは NDK/CMake が必要だが、ci.yml は
`platforms`+`build-tools` しか入れず、APK への `.so` 同梱検証も無かった。**だから** NDK/CMake を
オプション install し、APK 内の native lib 同梱を実機 sideload 前に CI で一次検証する。

- GitHub の repository variables（Settings > Variables）で以下を設定すると有効化:
  - `ANDROID_NDK`（例 `27.0.12077973`）/ `ANDROID_CMAKE`（例 `3.22.1`）→ sdkmanager で install。
    値は `externalNativeBuild` の `ndkVersion` / cmake `version` と**一致**させること。
  - `NATIVE_LIB_NAMES`（例 `libprobe.so`）設定時のみ、`gradle-build` 後に `check-native-libs.sh` が
    `lib/<abi>/<name>.so` の同梱を assert。`NATIVE_LIB_ABIS`（既定 `arm64-v8a x86_64`）/ `NATIVE_LIB_APK` で調整。
- 未設定なら NDK install も `.so` 検証もスキップ（NDK 不要プロジェクトに影響なし）。
- **検証状況**: vibe-coder PR#3 の CI（実 AGP+NDK ビルド）で `check-native-libs.sh` が実 APK の
  `lib/arm64-v8a/libprobe.so` / `lib/x86_64/libprobe.so` 同梱を assert し緑。実消費者 CI で実証済み。

## 設定方法

1. `templates/harness.config.sh.example` をプロジェクトルートに `harness.config.sh` としてコピー（install.sh が自動実行）
2. 使用するスクリプトに対応する変数を設定（コメントを参照）
3. 各スクリプトの先頭に `. "$ROOT/harness.config.sh"` の読み込みを追加（install.sh が自動処理）

## インストール後のROOTパス注意

このディレクトリのスクリプトは `ROOT="$(dirname -- "$0")/../../.."` でkit rootを参照している。
install.sh がプロジェクトの `scripts/` にコピーする際、`ROOT="$(dirname -- "$0")/.."` に書き換える。
