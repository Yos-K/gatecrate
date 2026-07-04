---
name: gatecrate-setup
description: |
  gatecrate を使って対象プロジェクトに localmd-reader 並みの CI/リリースハーネス
  （PRタイトル検証・シークレット検査・ファイルサイズ・JVMテスト・ミューテーション・
  ビルド・エミュレータスモーク・更新伝播）を構築する。「ハーネス構築」「gatecrate で
  セットアップ」「localmd 並みのハーネスを入れて」「このプロジェクトに CI ハーネスを作って」
  で起動。プロジェクトを分析して harness.config.sh を生成し、consumed_scripts を採用、
  CI を配線して各ゲートを検証する。機械的 install では埋まらない固有判断をエージェントが担う。
  Do NOT use for: ハーネスの実行（各スクリプト/CI が行う）。kit の3層構造に乗らない独自
  ハーネスの新規設計。gatecrate 本体の改修（kit リポで直接行う）。
argument-hint: "[target-project-path]"
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
metadata:
  author: Yos-K
  version: 1.0.0
  requires: gatecrate v0.3.1 or later
---

# gatecrate-setup — 任意プロジェクトに gatecrate ベースのハーネスを構築

このスキルは、gatecrate を消費して対象プロジェクトに「localmd-reader 並み」の
ハーネスを組む手順をエージェント（Claude Code / Codex）に与える。Codex でも本文を
手順書としてそのまま follow できる。

## 中心原則

機械的な `install.sh` はスクリプトをコピーできるが、**プロジェクト固有の判断**
（どのスクリプトを採用するか・`harness.config.sh` の値・ロジック注入・floor の初期値）
は静的には埋まらない。**この判断こそエージェントの仕事**。kit の3層（汎用core /
スタックアダプタ / 固有設定 `harness.config.sh`）に乗せ、固有部分だけを生成する。

消費スクリプトは **git-rev-parse でルートを解決**し `harness.config.sh` を source する
「消費可能形」を使う。これにより kit と消費側で同一ファイルが動き、更新同期が差分ゼロになる。

**kit の所在（スクリプトのコピー元）**: gatecrate を **Claude Code プラグインとして導入**した場合、kit 一式
（`core/scripts/`・`adapters/`・`templates/`・`profiles/`）は **`${CLAUDE_PLUGIN_ROOT}` 配下**にある。ここから
消費プロジェクトの `scripts/` へコピーする（例: `cp "${CLAUDE_PLUGIN_ROOT}/core/scripts/<gate>.sh" scripts/`）。
gatecrate リポを直接 clone して使う場合はそのリポルートが kit ルート。どちらでも採用するゲートだけを選んでコピーする。

## 前提

- 対象プロジェクトが git リポジトリであること。
- gatecrate が手元にある（`git clone https://github.com/Yos-K/gatecrate`）。本文では `$KIT` と表記。
- 破壊的変更（既存スクリプト置換）はブランチを切って PR で。各ゲートは導入前後で挙動を確認する。

## 手順

### Phase 1 — プロジェクト評価（判断の材料を集める）

```sh
# スタック判定
ls settings.gradle* build.gradle* pom.xml package.json 2>/dev/null    # Android/JVM か他か
# テスト構成
ls -d src/test/java src/testMedium/java 2>/dev/null
# パッケージのルート（最頻 namespace）
grep -rhoE "^package [a-z0-9_.]+" src/main/java 2>/dev/null | sort | uniq -c | sort -rn | head
# 既存 CI とスクリプト
ls .github/workflows/ scripts/ 2>/dev/null
```

判定: Android-JVM なら core + adapters/android-jvm。非 Android/JVM なら core（汎用衛生）のみ。

### Phase 2 — プロファイル選択

| profile | 入れるもの | 目安 |
|---------|-----------|------|
| minimal | 汎用コア衛生（title / secrets / version） | 小規模・どのスタックでも |
| **brownfield** | minimal + **差分カバレッジ ratchet**（diff-coverage） | **テストが無い/希薄なレガシー**（JVM=jacoco / rust・ts・python=lcov / go=coverprofile） |
| standard | minimal + Android-JVM アダプタ（unit / test-smell / balance） | ロジックを持つ Android-JVM |
| full | standard + 重い検査（mutation / smoke） | 状態複雑度 high × 失敗時被害 high |

#### テスト有無の判定（standard/full か brownfield か）

絶対 floor（standard/full の run-tests/koverVerify/mutation）は**既存テストが床以上に在る**ことが前提。
テストゼロのレガシーに入れると初日に必ず落ち、ゲートごと外され安全網が育たない。Phase 1 でテスト量を測り分岐する:

```sh
# テストソースの実数（0 or 極少なら brownfield 経路）
find . -path ./.git -prune -o \( -name '*Test.kt' -o -name '*Test.java' -o -name '*Tests.kt' \) -print | wc -l
```

- テストが**無い/希薄** → **brownfield**。`check-diff-coverage.sh` で「このPRの変更行だけ」に被覆を要求する
  （レガシー本体は対象外＝導入摩擦ゼロ）。消費側はテストで JaCoCo XML（kover/jacoco）を生成し、`harness.config.sh`
  に `COVERAGE_REPORT` / `COVERAGE_FORMAT`（jacoco|lcov|gocover）/ `DIFF_BASE` / `DIFF_COVERAGE_THRESHOLD`（既定80）を設定する。
- テストが**床以上に在る** → standard/full（絶対 floor / mutation）。
- **昇格パス**: brownfield で PR を重ねるとベースラインが育つ。育ったら standard（絶対 floor）→ full（mutation）へ。
  根拠と段階設計: `docs/test-selection-roi.md`「レガシー（テスト希薄）の入口」。

#### brownfield で「リファクタリングしたい」場合 — characterization 安全網を先に張る

diff-coverage は「変更行が被覆されたか（前進ラチェット）」を強制するが、**既存の振る舞いを壊していないか**は守れない
（時間の向きが逆）。テストの無いレガシーを**安全にリファクタリング**するには、触る前に現挙動を固定する golden-master
（characterization）テストが要る。そのブートストラップ一式を配る:

1. `cp -r $KIT/templates/characterization/ <consumer>/` し、`.example` を外して `src/test/kotlin/characterization/`
   に `Approvals.kt`（依存ゼロの golden-master ヘルパ）と `<Cluster>CharacterizationTest.kt` を置く。
2. `approve-characterization.sh` を `scripts/` に置き、`.gitignore` に `*.received.*` を追加。
3. **`check-no-received-approvals.sh`（core・prevention）を採用**: 未承認スナップショット（`*.received.*`）の
   コミットを reject ＝レビュー未通過の挙動が仕様として紛れ込む穴を塞ぐ。consumed_scripts と CI hygiene に配線。
4. ループ（分析→固定→意図/欠陥の仕分け→リファクタ→ratchet）の手順と「characterization の罠」回避は
   `$KIT/templates/characterization/README.md` に正典化。分析は `es-lint`/`es-render`/`bounded-context-analyzer`、
   リファクタは `refactoring-specialist`/`extract-*` スキルを使う。唯一の人間判断は「意図 vs 欠陥」の仕分け。

### Phase 3 — consumable スクリプトの採用 + sync-manifest

採用する各スクリプトを、消費可能形（git-root + config source）で `scripts/` に置く。
core のスクリプトは全て消費可能形へ移行済み（`check-file-sizes.sh` / `run-mutation-tests.sh` が
初期のパイロット2本）。もし未移行のアダプタスクリプトを見つけたら、kit で git-root 化してから
採用する（後述「kit への還元」）。

`sync-manifest.yaml`（リポルート）を作る:

```yaml
harness_kit_version: "v0.3.1"     # 採用した kit のタグ
adapter: android-jvm
consumed_scripts:                 # opt-in したものだけ。同期はこの列挙に絞られる
  - scripts/check-file-sizes.sh
  - scripts/run-mutation-tests.sh
```

### Phase 4 — `harness.config.sh` をプロジェクト分析から生成

#### 非 Android / core-only（minimal プロファイル）の場合

mutation も BuildConfig も無い。`harness.config.sh` は言語非依存の衛生値だけ:

```sh
FILE_LINE_LIMIT=300
FILE_LINE_NAMES="*.sh *.md"   # 検査対象 glob（その PJ の主要言語の拡張子）
# FILE_LINE_PATHS は既定 "." で全走査。.git は自動 prune
```

consumed_scripts は `check-conventional-title` / `check-no-committed-secrets` /
`check-file-line-limit` の3本（汎用 core 版を使う。`check-file-sizes.sh` は `src/**.java`
専用なので非Android では何も検査しない）。以下の Android 系（BUILDCONFIG/TARGET/mutation）は
スキップ。**gatecrate 自身がこの経路の consumer #0** で、self-harness がこの3本を効かせている。

#### Android-JVM の場合

ここが本スキルの核。各値を**プロジェクトから導出**する（recipe 付き）:

```sh
# BUILDCONFIG_PACKAGE: BuildConfig を置くパッケージ（infrastructure 等）
grep -rl "BuildConfig" src/main/java | head -1   # 参照箇所からパッケージを特定

# TARGET_CLASSES: ミューテーション対象＝Android非依存のロジック層パッケージ
#   domain/viewer/file/infrastructure 等、src/main で android import の無い層
# TARGET_TESTS: テストの namespace（例 com.example.app.*）

# EXCLUDED_TESTS: architecture.*（構造テスト）, *Property（PBT は PITest を爆発させる）

# --- ロジック注入（値でなくロジックが固有な部分） ---
# BUILDCONFIG_FIELDS: コードが参照する BuildConfig フィールドを全て stub に出す
grep -rhoE "BuildConfig\.[A-Z_]+" src/main/java | sort -u   # → 各 boolean フィールド宣言に
```

#### 反復で確定する2項目（localmd 精度測定で「one-liner では当たらない」と判明した箇所）

機械的 grep で当たるのはここまで（測定: パッケージ・フィールド・TARGET_CLASSES/TESTS は完璧）。
次の2つは**1回回して結果を見て確定**する。最初は空/最小で置き、mutation を実走して調整する:

```sh
# EXTRA_MAIN_SOURCES（コンパイルエラー駆動）: まず空で run-mutation を実行。
#   "cannot find symbol" 等で presentation 内クラスが未解決なら、その .java を追加して再実行。
#   エラーが消えるまで反復（Android-free 集合が参照する数ファイルに収束する）。
# EXCLUDED_CLASSES（NO_COVERAGE 駆動）: base = *Test,*Tests,*Property,*Properties。
#   run-mutation の triage 出力で NO_COVERAGE が突出するクラス（i18n 文字列表など、
#   テストに値しない low-value）を EXCLUDED_CLASSES に追記して floor を実ロジックに寄せる。
#   例: 文字列カタログ ViewerText* 系。
# MUTATION_THRESHOLD: 上記で安定した緑スコア以下を floor にする（例 80。決して下げない）。
```

生成例（テンプレートは `$KIT/templates/harness.config.sh.example`）:

```sh
# harness.config.sh
FITNESS_MAX_LINES=300
BUILDCONFIG_PACKAGE=com.example.app.infrastructure
TARGET_CLASSES="com.example.app.domain.*,com.example.app.viewer.*"
TARGET_TESTS="com.example.app.*"
EXCLUDED_CLASSES="*Test,*Tests,*Property,*Properties,com.example.app.i18n.*"
EXCLUDED_TESTS="com.example.app.architecture.*,*Property,*Properties"
MUTATION_THRESHOLD=80
BUILDCONFIG_FIELDS="    public static final boolean PRO_FEATURES_ENABLED = false;"
EXTRA_MAIN_SOURCES=""
```

`harness.config.sh` はコミットする（PJ設定であり秘匿物でない）。同期では絶対に触らない。

### Phase 5 — CI 配線

- **どのスタックでも（衛生ゲートだけ）**: `$KIT/core/workflows/ci.yml` をそのまま
  `.github/workflows/ci.yml` へ置く。PRタイトル/ファイル行数/シークレットの3ゲートで、
  Android でなくても動く（実 pull_request で緑を実証済み）。非Android 消費者はここで完了。
- **Android-JVM はさらに**: `$KIT/adapters/android-jvm/workflows/`（ci.yml の test/gradle-build /
  mutation.yml / device-smoke.yml）を足す。必須ゲートと非ゲート（smoke/large は非必須）を
  test-strategy で分ける。`run: sh scripts/<name>.sh` でそのまま呼べる（git-root + config 自己解決）。
- **既存スクリプトの workflow ラッパー（任意）**: `$KIT/core/workflows/` の `merge-integrity.yml`
  （auto-merge レース検知）/ `harness-drift-check.yml`（consumed の kit ドリフト・advisory）/
  `domain-model-check.yml`（Alloy・advisory）を、対応スクリプトを採用しているなら足す。
- **保護**: ゲートが実績を出したら `main` のブランチ保護で required check 化する
  （`scripts/setup-branch-protection.sh REQUIRED_CHECKS=...` で半自動化・kit 自身も同様）。

### Phase 6 — 更新伝播（harness-sync）の設置

`$KIT/.github/workflows/sync-propose.yml` を `.github/workflows/harness-sync.yml` として置く。
週次 + 手動で kit 最新と pin を比較し、**consumed_scripts だけ**を更新する PR を起票する
（v0.3.1 で opt-in 限定にスコープ修正済み。未採用スクリプトと `harness.config.sh` は触らない）。

### Phase 6.5 — 仕様駆動ループを使うなら: spec 文書と鮮度ゲートを scaffold（任意）

cc-sdd 連携 / spec-driven loop を採用する場合、規則を書き留める場所と鮮度ゲートを turnkey で用意する。
これを省くと、規則がコードの中だけに残り、mutation で生存＝未テスト制約として後から露出する
（実消費者で観測した症状）。

1. `cp -r $KIT/templates/spec/ docs/spec/` し、`README.md.example`/`area.md.example` を消して
   プロジェクトの領域別 `docs/spec/<area>.md` に置き換える（規則を `R-<n>` ミニ言語で記述）。
2. `cp $KIT/rule-doc-lanes.tsv.example rule-doc-lanes.tsv` し、規則担持コード→`docs/spec/<area>.md`
   のレーンを定義（タブ区切り）。
3. CI の hygiene ジョブに `check-rule-doc-currency.sh` を追加（PR 時・`RULE_DOC_BASE=origin/<base>`）。
   これで規則担持コードを変更したら spec も同 PR で更新（or `Docs-Impact:` 宣言）が機械強制される。
4. mutation を採用するスタックでは、生存ミュータントを規則の盲点として `docs/spec` に反映する
   （reflect→measure ループ。詳細は `docs/spec-rules.md` / `docs/test-selection-roi.md`）。
5. **形式手法（順序/状態規則）**: `cp $KIT/templates/spec/models/example.als.example docs/domain/models/<area>.als`
   で雛形から起こし（生成は `alloy-spec-model-generator` スキル）、`domain-model-check.yml` を CI に足す。
6. **二階ループ／規則 reflect の orchestration を使うなら**: `install.sh --with-skills` で `.claude/skills/`
   （`alloy-spec-model-generator` / `gatecrate-evaluate`）と `.takt/`（`harness-evaluate-cycle` /
   `harness-liveness-converge` / `harness-rule-reflect` ＋ personas）を配布する。規則起票の richer な
   様式は `docs/proposed-rule-format.md`。
7. **Fitness 計測（advisory）**: `measure-complexity.sh`（PMD・`COMPLEXITY_LANG`）/ `measure-coupling.sh`
   （`COUPLING_PKG_PREFIX`・未設定時は git co-change のみ）を回し、`docs/code-quality-metrics.md` の閾値で
   ホットスポットを見る。`collect-gate-history.sh --group-map gate-groups.tsv`（雛形 `gate-groups.tsv.example`）で
   ROI 集計の論理ゲートを整える。
8. **アーキテクチャ品質ゲート（Balanced Coupling ratchet・JVM 消費者向け）**: 結合の悪化を機械で
   止めたい場合に採用する。手順は「計測→凍結→強制→分類」の順:
   1. `harness.config.sh` に `COUPLING_PKG_PREFIX`（内部ルートパッケージ）を設定し、
      `sh scripts/measure-modularity.sh` を1回実走して RED（強い×遠い×変動）と unclassified の件数を見る。
   2. `sh scripts/check-modularity-ratchet.sh --emit-baseline` で既存 RED を `modularity-baseline.tsv`
      に凍結し、**凍結一覧に「なぜ許容するか」を添えて人間レビューへ**（負債の受入は人間の承認事項）。
   3. CI に `check-modularity-ratchet.sh` を配線（ベースライン外の新規 RED だけ reject する ratchet。
      絶対 floor をレガシーに入れない——初日に落ちてゲートごと外される）。`PROBE_GATES` に
      `scripts/check-modularity-ratchet.sh:modularity` を登録し生存証明に載せる。
   4. unclassified エッジは `modularity-review` スキル（判断層）で contract/model/functional/intrusive に
      証拠つき分類し `modularity-strength.tsv` を育てる。閾値・式の定義は `docs/code-quality-metrics.md`。
   非JVM スタックは import 解析が働かないため現状は対象外（temporal coupling のみ advisory で見る）。

### Phase 7 — 検証（必須）

1. 採用した各ゲートを**ローカル実走**して通ることを確認（`sh scripts/<name>.sh`）。
   - **「存在」ではなく「実走」で検証する（必須）**: ゲートのファイルが在るだけでは不十分。
     **実際に実行して期待の出力（スコア・件数・pass/fail）が出ることを確認**せよ。とくに
     **mutation は `run-mutation.sh` を1回回し「mutation score が出る」ことまで確認**する。
     ツール版の非互換でクラッシュしても**非ゼロで落ちず黙って素通り**する構成があり得る
     （例: Vitest 4 × `@stryker-mutator` 8.x は dry-run でクラッシュ＝ゲートが一度も走らない）。
     版整合は各アダプタ README を参照（例: TS は Vitest 3/4 に `@stryker-mutator` ≥9）。
     `npx --no-install` でも実行できる版が入っているかを setup 時に固定せよ。
   - **予防ゲートは生存証明を全域化する**: 採用した reject 型ゲートを `PROBE_GATES` に登録し、
     `sh scripts/probe-gate-liveness.sh --audit` で**未登録の probe 可能ゲートが無いことを確認**（CI にも配線）。
     これで「ゲートを足したが生存証明に登録し忘れた」死角を構造で防ぐ。injectable kind: title/secrets/
     filesize/hard-constraints/posix/escalation/doc-currency/rule-doc/merge-integrity/release-version/
     third-party/modularity。
   - **ゲートには必ず挙動テストを置く**: `sh scripts/check-gate-tests.sh` で採用した reject 型ゲートに
     `tests/test-<gate>.sh` が在ることを機械確認（CI に配線）。テスト無しゲートは黙って壊れても気づけない
     （file-line の glob 走査漏れで実証）。
2. スクリプト置換は**置換前後で挙動が同じ**ことを確認（生成物・スコア・件数を diff）。
   - 例: run-mutation は生成 BuildConfig.java と main-sources.txt が旧版と一致するか。
   - ミューテーションのローカル実走が不安定（PITest minion timeout）なら **CI を権威ゲート**に。
3. PR を出し、CI 全ゲート緑を確認してマージ。
4. 可能なら**自己ドッグフード**: そのプロジェクトの汎用ルール（conventional title 等）を、
   採用した kit スクリプト自身で gate する。

### Phase 8 — 罠の回避（localmd で踏んだもの）

- **同一ロジックの二重実装を揃える**: あるルール（例: コードフェンス検出）が複数箇所に
  実装されている場合、片方だけ直すと不整合になる。両方を同じ規則に揃える。
- **currency ゲート**: harness スクリプト/ワークフロー変更時は、ルール文書を更新するか
  コミットに `Rule-Docs-Impact: none (...)` トレーラ行を入れる（行頭から。PR本文の backtick は不可）。
- **マージ機構**: 全CI緑でも BLOCKED なら、必須チェックの方式・strict（最新必須）・
  会話解決必須（未解決レビュースレッド）を疑う。
- **git-root で差分ゼロ**: 消費スクリプトは無改変コピーで動く形に保つ（install 時の ROOT 書き換えに依存しない）。

## kit への還元（双方向）

採用したいスクリプトがまだ消費可能形（git-root + config）でない場合、kit 側で
git-root 化 + 注入口追加を行い、新タグを切ってから消費する（消費側固有のハードコードは
kit に戻さない＝汎用形を保つ）。手順は `$KIT/CONTRIBUTING.md`「Upstreaming」を参照。

## 精度（localmd で測定・2026-06-13）

本スキルのレシピを localmd-reader（構築済みハーネス＝正解）に**盲適用**し、実 `harness.config.sh`
と突合した結果（10決定項目）:

- **完全自動 7/10（70%）**: スタック・プロファイル・BUILDCONFIG_PACKAGE・BUILDCONFIG_FIELDS・
  TARGET_CLASSES・TARGET_TESTS・EXCLUDED_TESTS は grep ベースで正確に当たる。
- **+1（mutation 1回実走で）= 8/10**: MUTATION_THRESHOLD（緑スコアを floor）。
- **+2（反復で）= 10/10**: EXTRA_MAIN_SOURCES（コンパイルエラー駆動）と EXCLUDED_CLASSES の
  NO_COVERAGE 除外（ViewerText 等）。上記「反復で確定する2項目」の手順で到達する。

含意: 機械的な値はスキルで一発、固有ロジックは「1回回して結果を見て調整」の反復が要る。
だから本スキルは run-mutation を**早めに1回回して** triage とコンパイルエラーを読むことを推奨する。

## 精度（gatecrate で測定・非Android/shell-only・2026-06-14）

別スタック（shell-only）の gatecrate 自身を2人目の消費者として本スキルを実走した結果:

- **適用される core 決定は 3/3 自動**: スタック分類（非Android→core-only）・プロファイル（minimal）・
  consumed_scripts（衛生3本）はすべて grep/ls ベースで一発。
- **Android 固有の7決定（BUILDCONFIG/TARGET/mutation/EXTRA_MAIN_SOURCES/EXCLUDED_CLASSES 等）は
  N/A**: shell-only スタックには mutation フェーズ自体が無い。**＝「8→10」の反復ループはここでは発生しない**。
- 実走で2欠陥を発見・修正: ①minimal プロファイルが Android 版 `check-file-sizes.sh` を参照していた
  （→汎用 `check-file-line-limit.sh` に修正）、②本スキルに core-only の Phase 4 経路が無かった（→上記追記）。

含意: 本スキルは**核（mutation 反復）が Android-JVM 前提**。非Android では衛生3本に縮退し反復は無い。
よって反復ループの自動化（TAKT 等）を検証するには **Android 消費者2号**が要る。gatecrate は core
経路の正しさは検証できるが、反復ループは構造上検証できない。

## 反復ループの実証（mutation 経路・JVM 消費者・2026-06-14）

4トリガーを仕込んだ pure-JVM 消費者 `harness-probe-jvm` で「8→10」反復を実観測した結果:

- 機械値（BUILDCONFIG_PACKAGE/FIELDS・TARGET_CLASSES/TESTS）は grep レシピで一発。
- 反復は **3回の決定的ゲート実走で収束**:
  1. `javac` 未解決シンボル（presentation 参照）→ `EXTRA_MAIN_SOURCES` に当該ファイル。
  2. PITest 69%<floor、triage が **SURVIVED**（domain の境界変異）と **NO_COVERAGE**（i18n 文字列表）を分離 →
     SURVIVED は**テスト追加**で潰し、NO_COVERAGE は低価値なので `EXCLUDED_CLASSES` で除外。
  3. 100% 緑 → `MUTATION_THRESHOLD` を floor に設定。
- CI（temurin JDK17）でも mutation ゲート緑。

学び: 各ステップは「ゲート実走→決定的バケット（コンパイルエラー種別 / SURVIVED・NO_COVERAGE）を読む→
1つの config 変数 or テストに対応付け」で規則的。**だから run-mutation を早めに1回回す**価値が定量的に裏づいた。
唯一の判断分岐は「SURVIVED=テスト追加 / NO_COVERAGE=低価値なら除外」で、ここはエージェントの判断が要る。

## Phase 9（任意）— TAKT で反復を自動化

mutation 経路の反復（EXTRA_MAIN_SOURCES / EXCLUDED_CLASSES / threshold）は終了条件が機械判定ゲート
なので [TAKT](https://github.com/nrslib/takt) で統率できる。**実走実証済み**（provider `claude`・
`--pipeline`・1 iteration で収束、command ゲートが `run-mutation-tests.sh` を機械実行、独立再実行でも
exit 0 ≈92%）。手順:

```sh
npm install -g takt                                   # TAKT CLI（v0.46+ 検証済み）
# ~/.takt/config.yaml: provider: claude / model: sonnet / language: ja
# 消費側 .takt/config.yaml に  workflow_command_gates: { custom_scripts: true }
cp takt/harness-config-derive.yaml      <consumer>/.takt/workflows/   # 名前は <name>.yaml 必須
cp takt/personas/gatecrate-setup.md       <consumer>/.takt/personas/
# 前提: scripts/run-mutation-tests.sh 採用済み・JDK17+curl・harness.config.sh は機械値だけ埋め反復項目は空
takt -t "harness.config.sh を mutation ゲートが exit 0 になるまで収束（floor は下げない）" \
  -w harness-config-derive --provider claude --model sonnet --pipeline --skip-git
```

`type: command` ゲートが各ターン後に `run-mutation-tests.sh` を実行し、exit code と triage を同ステップへ
差し戻して収束させる。**TAKT はループ統率とゲート強制のみ。判断（SURVIVED→テスト / NO_COVERAGE→除外・
floor を達成スコアへ引き上げ）は persona＝本スキルが供給する**。詳細・実走結果は [`takt/README.md`](./takt/README.md)。

## 完了の判定

- 採用ゲートが CI で緑。
- `harness.config.sh` に固有値・注入口が埋まり、`sync-manifest.yaml` が pin を持つ。
- `harness-sync.yml` が設置され、consumed_scripts 限定で更新を受け取れる。
- （理想）汎用ゲートをプロジェクト自身に self-harness として効かせている。

## 参照

- 構造と消費機構: `$KIT/docs/structure.md`
- 使い方（導入〜同期〜還元）: `$KIT/docs/usage.md`
- 設定テンプレート: `$KIT/templates/harness.config.sh.example`
- ロードマップ（消費成熟度・残タスク）: `$KIT/ROADMAP.md`
