# 使い方

プロジェクトで gatecrate を導入・設定し CI に組み込む方法。既定は **fire-and-forget**:
インストール → 設定 → CI 配線、で**スクリプトはあなたのもの**になり、追跡する版も走らせる同期も
ありません。同期し続けることと還元は**任意**です（Advanced 参照・複数 PJ を1つの kit で束ねるチーム向け）。

English: [usage.md](./usage.md)。構成と理由は [structure.ja.md](./structure.ja.md)。

## 1. インストール

プロジェクトルートでインストーラを実行し、プロファイルを選ぶ:

```sh
sh /path/to/gatecrate/install.sh --profile auto --target .
```

| プロファイル | 導入内容 |
|---|---|
| `minimal` | 汎用コア衛生のみ（タイトル検証・シークレット・ファイルサイズ）— **スタック中立** |
| `auto` | スタックを自動判定（pyproject.toml→python 等）— **推奨の既定** |
| `standard` | minimal + Android-JVM アダプタのスクリプト — **スタック中立でない（Android）** |
| `python` / `go` / `rust` / `typescript` / `kotlin` / … | minimal + そのスタックのアダプタ |
| `full` | standard + 重いチェック（mutation・smoke） |

インストーラは選択スクリプトを `<target>/scripts/` にコピーし、**テンプレートから `harness.config.sh` を生成し**
（既存なら skip）、`.gitignore` に `build/` を追記する。

**加算フラグ（必要なものを選ぶ）:**
- **`--with-skills`** — `.claude/skills/` と `.takt/` も導入し、**エージェント駆動のハーネスループ**
  （`gatecrate-setup`・`legacy-domain-extraction`・TAKTワークフロー）を使えるようにする。高価値な経路で、
  スクリプトのみの導入では省かれる。
- `--with-cc-sdd` — **cc-sdd 本体を `npx cc-sdd@latest` で導入**し、gatecrate の steering を `.kiro/steering/` に
  重ね、さらに mutation の Stop hook まで入れる（後述の仕様駆動ループ節を参照）。

**コピーされたスクリプトは、もうあなたのものです。** `git rev-parse` で repo root を解決するので
そのまま動きます。自由に編集・削除してよく、版の追跡も同期も不要です。

## 2. 設定: `harness.config.sh`

`install.sh` が repo root に `harness.config.sh` をテンプレートから生成済み（既存なら skip）。
これを開いて必要な値を設定する。手動で用意する場合は:

```sh
cp /path/to/gatecrate/templates/harness.config.sh.example harness.config.sh
```

これは shell で、スクリプトが source する（YAML ではない）。上書きしたい変数だけ設定する（各々デフォルトあり）。例:

```sh
# harness.config.sh
FILE_LINE_LIMIT=300                                    # check-file-line-limit.sh（core・全プロファイル）
FILE_LINE_NAMES="*.sh *.md"                            # 行数ゲートの対象ファイル
# BUILDCONFIG_PACKAGE=com.example.app.infrastructure   # run-mutation-tests.sh（Android-JVM）
# APP_PACKAGE=com.example.app                          # emulator-smoke.sh（Android-JVM）
# SPEC_LOOP_MODE=autonomous                            # 仕様駆動ループ: autonomous | expert-gated
# SPEC_TEST_MUTATION_CMD="sh scripts/run-mutation-tests.sh"  # Stop hook の survivor-strict mutation ゲート
```

シークレットは置かない。これは PJ 設定なのでコミットする（秘匿ストアではない）。

### AIエージェントの仕様駆動学習ループ

衛生ゲートに加え、gatecrate は「エージェントがクラスタを探索→コードが示唆するモデルを提案→仕様を文書化→
ROI で選んだ手段でテスト→mutation で十分性を計測」するループを同梱する（`autonomous` / `expert-gated`
モード・任意の cc-sdd 統合＋`validate-impl` 後に mutation を機械強制する Stop hook 付き）。詳細ガイド:
**[`spec-driven-loop.ja.md`](spec-driven-loop.ja.md)**。

cc-sdd 連携を有効化するには、インストーラに `--with-cc-sdd` を付ける。**cc-sdd 本体を
`npx cc-sdd@latest` で導入**（Node.js/`npx` が必要）した上で、gatecrate 自身の steering を
`.kiro/steering/` に重ねる。cc-sdd の導入先は env で上書き可能:

```sh
sh /path/to/gatecrate/install.sh --profile standard --target . --with-cc-sdd
# CC_SDD_AGENT（既定 --claude-skills。例: --codex-skills / --cursor-skills）
# CC_SDD_LANG （既定 ja。例: en / zh / ko ...）
# CC_SDD_FLAGS（cc-sdd への追加引数。例: --kiro-dir docs）
```

`--with-cc-sdd` は **mutation の Stop hook**（`.claude/hooks/spec-test-mutation-gate.sh` ＋
`.claude/settings.json`）も入れる＝生存ミュータントがある間は `validate-impl` を「緑テストだけ」で
終えられない（ループの機械層）。`.claude/settings.json` が既存なら触らず、
`templates/hooks/settings-stop-hook.json` の `hooks.Stop` を手動マージする。

`npx` が無い場合は警告して cc-sdd の導入はスキップするが、steering と Stop hook は配置する。手動で行うには
`npx cc-sdd@latest --claude-skills --lang ja` を実行し、`templates/kiro-steering/gatecrate-spec-test-loop.md`
を `.kiro/steering/` にコピーする。なお steering は `.kiro/steering/`（既定の `--kiro-dir`）に置く。
`--kiro-dir` を変える場合はそれに合わせて移動すること。

導入後は **mutation スクリプトを1回回し、mutation スコアが出る（ツールのクラッシュでない）こと
を確認**する＝存在するが実行されないゲートは偽りの安心になる。スクリプト名はアダプタごとに異なる:
Android-JVM（standard/full プロファイル）は `sh scripts/run-mutation-tests.sh`、他アダプタは
`sh scripts/run-mutation.sh`。

## 3. スクリプトを実行し CI に組み込む

kit スクリプトは repo root を解決し `harness.config.sh` を source するので、そのまま実行できる:

```sh
sh scripts/check-file-line-limit.sh
```

他のスクリプト同様 CI に組み込む:

```yaml
- name: file line limit
  run: sh scripts/check-file-line-limit.sh
```

**これで fire-and-forget は完了です。** スクリプトはあなたの repo に自分のファイルとしてコミットされます。
以下は一切不要 — 興味があれば「kit 自身の CI」だけ読めば十分です。

---

## Advanced: 同期し続ける・還元する（opt-in・チーム向け）

> **複数 PJ を1つの kit で束ね、ハーネス修正を伝播させたい場合以外、ここは読み飛ばして構いません。**
> fire-and-forget の消費者は以下のファイルを一切作りません — 導入済みスクリプトは既にあなたのものです。
> これは複数 PJ を運用するオーナーのワークフローです。

### kit バージョンの追跡: `sync-manifest.yaml`

消費している kit リリースを pin して更新を検知可能にする（opt-in）:

```yaml
# sync-manifest.yaml（repo root）
harness_kit_version: "v0.8.0"
adapter: android-jvm
consumed_scripts:
  - scripts/check-file-sizes.sh
```

opt-in した `consumed_scripts` は、そのスクリプト間依存（co-dependency）も併せて同期される。

### 更新を受け取る（下流: kit → 自分）

kit の `sync-propose.yml` を自分の `.github/workflows/` にコピーする。週次（および手動）で pin した
バージョンと kit 最新リリースを比較し、変更された kit 管理スクリプトを含む**同期 PR**を起票する。
自分の CI がその PR をゲートし、`harness.config.sh` は触られない。`HARNESS_SYNC_PAT` を設定すると
同期 PR が CI を起動する（未設定だと未ゲートで作成される — ワークフローが警告を入れる）。緑を確認してマージ。

### 改善を還元する（上流: 自分 → kit）

ハーネス改善はたいてい消費側で生まれる。還元の手順:

1. kit の**汎用形**に移植する — パラメータ化（`$VAR` デフォルト・`#!/bin/sh`・git 解決の root）を保つ。
   消費側固有のドリフト（ハードコード id・ホスト固有パス）は**還元しない**。kit が既に汎用化済みのものは飛ばす。
2. kit に PR を出し、`CHANGELOG.md` エントリ追加・バージョン bump。

詳細は [CONTRIBUTING.md](../CONTRIBUTING.md) と [AGENTS.md](../AGENTS.md)。

## kit 自身の CI

kit は自分の PR をゲートする（`.github/workflows/ci.yml`）: `sh -n` 構文・ShellCheck（`-S error`）・
sync-manifest 整合性・sync-check 挙動テスト。`main` は保護（CI 必須・会話解決必須）。消費側には不要
（kit 自身を守るもの）。
