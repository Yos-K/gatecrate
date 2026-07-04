# gatecrate

[![CI](https://github.com/Yos-K/gatecrate/actions/workflows/ci.yml/badge.svg)](https://github.com/Yos-K/gatecrate/actions/workflows/ci.yml)

CI / 品質ゲートスクリプトの移植可能キット — 3層構造（実プロダクト [localmd-reader](https://github.com/Yos-K/localmd-reader) から抽出）。

> **English README**: [README.md](./README.md)
>
> **ゲート状態を一目で:** 上の CI バッジは `main` で全ゲートが通れば緑。ゲート別ダッシュボード（型 / 生存 /
> ROI判定）は [`docs/harness-status.md`](./docs/harness-status.md) にコミットされ**リポからそのまま見える**。各 CI 実行の
> **Summary** ページにも描画される。仕組み: [`docs/harness-dashboard.md`](./docs/harness-dashboard.md)。

## gatecrate とは

gatecrate は、CI / 品質ゲートスクリプト（衛生チェック・テスト/ミューテーションゲート・
build/release ヘルパー）を 8 スタック分そろえたライブラリです。既定の使い方は
**fire-and-forget — スクリプトを vendoring したら、それはあなたのものになる**です:

- `install.sh` は選んだスクリプトを導入先の `scripts/` に**コピー**します。その瞬間から
  **それはあなたのファイル**です — commit・編集・削除、自由。版の固定も manifest も不要で、
  この repo を追跡・同期する義務はありません。
- 静的 install では埋まらない固有判断（どのスクリプトを残すか・`harness.config.sh` の値・
  mutation の floor・CI 配線）は **gatecrate-setup エージェントスキル**が担います。Claude Code / Codex
  をプロジェクトに向ければ、その判断を代行します。

**進化的アーキテクチャ**（Ford / Parsons / Kua）の言葉で言えば、gatecrate は**適応度関数
（fitness function）のポータブルなキット**であり、さらに**適応度関数自体の適応度を保つ二階ループ**を
備えています。各ゲートは自動・トリガー型の適応度関数。probe は*適応度関数に対する適応度関数*
（合成違反を注入し、沈黙する予防ゲートがまだ計測できていることを証明する）。ROI 判定が関数の集合を
剪定し、絶対 floor がレガシーでゲートごと外される場面には **ratchet 型関数**（導関数述語＝
「ベースラインより悪化していない」）を出荷して、関数が現実に接触しても生き残るようにします。
背後の二重ループ・モデル: [docs/development-workflow.ja.md](./docs/development-workflow.ja.md)。

下の「Advanced」は、**1つの kit で複数プロジェクトを束ねて運用する**場合以外、読む必要はありません。

## 2つの使い方

| | **Fire-and-forget（既定）** | **同期し続ける（opt-in・チーム向け）** |
|---|---|---|
| 対象 | プロジェクトに良いゲートを入れたい全員 | 1つの kit で複数 PJ を運用するオーナー |
| install 後 | スクリプトは**あなたのもの** — 自由に改変 | kit の版を追跡し、更新を PR で受け取る |
| 設定 | `install.sh` で完了 | + `sync-manifest.yaml` と同期ワークフローを追加 |
| 義務 | **なし** — 還元も版追跡も不要 | opt-in: 更新を取り込み、任意で還元 |

repo にゲートを入れたいだけなら、**Quick Start で終わりです**。sync 機構
（`sync-manifest`・`sync-propose`・版追跡）は**完全に任意**で、複数 PJ 運用のためだけに存在します
（末尾の Advanced を参照）。

## 使い方（Quick Start）

### プラグインとして導入（推奨・Claude Code）

```
/plugin marketplace add Yos-K/gatecrate
/plugin install gatecrate@gatecrate
```

gatecrate の**エージェントスキル**（`gatecrate-setup`・`legacy-domain-extraction`・`gatecrate-evaluate`・
`alloy-spec-model-generator`）が導入されます。次に **`gatecrate-setup`** を対象プロジェクトで実行すると、
リポを分析してハーネスを配線します——ゲート（`${CLAUDE_PLUGIN_ROOT}` に同梱）をプロジェクトの `scripts/` へ
コピーし、`harness.config.sh` を生成し、CI を配線。静的インストーラでは埋まらない固有判断をスキルが担います。

**更新**: `/plugin marketplace update gatecrate` で最新化されます。本プラグインは **`version` を固定しない**ため
リポのコミットに追従し、マーケットプレイスを更新すれば常に `main` の最新が入ります（バージョン bump 不要）。
確実に入れ直すなら `/plugin uninstall gatecrate@gatecrate` → 再インストール。

> Codex: 同じスキルを利用できます。本リポを Codex のスキル/エージェントディレクトリに追加するか、下の shell
> インストーラを使ってください（マーケットプレイス導入は Claude Code の機構）。詳細は [docs/usage.ja.md](./docs/usage.ja.md)。

### シェルインストーラ（エージェント無し／CI ブートストラップ）

```sh
sh install.sh --profile auto --target /path/to/your/project
```

> **プロファイル名の注意**: `minimal` はスタック中立（汎用ゲートのみ）、`auto` はスタックを自動判定
> （pyproject.toml→python 等）で**推奨の既定**。**`standard` はスタック中立ではなく `minimal` + Android-JVM
> アダプタ**です。他スタックは `python`/`go`/`rust`/`typescript`/`kotlin`/…（または `auto`）を選んでください。

プロファイルを選び、選択スクリプトを導入先の `scripts/` にコピーし、設定テンプレートを置きます。
自分の値を入れた `harness.config.sh` を作り、スクリプトを CI に組み込みます。
全手順は [docs/usage.ja.md](./docs/usage.ja.md) を参照。

**3つの導入経路**（必要なものを選ぶ・フラグは加算的）:

| 目的 | コマンド |
|------|---------|
| ゲートだけ（撃ちっぱなし） | `sh install.sh --profile <p> --target <dir>` |
| **＋エージェント駆動ループ**（`.claude/skills/` と `.takt/` を導入） | **`--with-skills`** を追加 |
| ＋cc-sdd（仕様駆動）連携 | `--with-cc-sdd` を追加 |

`--with-skills` が高価値なエージェント経路（`gatecrate-setup`・`legacy-domain-extraction`・TAKTループ）を有効化します。
上のプラグイン導入を使う場合は既にスキルが入っているので、`--with-skills` はシェルインストーラ経路向けです。

**これ以降、`scripts/` 配下はあなたのものです。** 他にやることはありません — 固定する版も、
走らせる同期も、送り返す PR もなし。プロジェクトの都合で自由に編集・削除してください。

## シェル・プラットフォーム対応

出荷スクリプトは全て **POSIX `sh`**（`#!/bin/sh`・bashism なし — CI の `check-posix-portability.sh`
で機械強制）。スクリプトは*実行*されるもので対話シェルに*source*しないため、対話シェルが何であれ
shebang が `/bin/sh` を選ぶ：

| シェル | 対応 | 備考 |
|---|---|---|
| **bash** | ✅ | POSIX スクリプトをそのまま実行 |
| **zsh** | ✅ | 同上。shebang で `/bin/sh` 実行 |
| **fish** | ✅ | `./script.sh` は shebang で exec。スクリプトを fish に *source* させる設計は無い |
| **PowerShell / コマンドプロンプト**（Windows） | ⚠️ POSIX 層経由 | cmd/PowerShell は POSIX `sh` を native 実行できない。**Git Bash**（git に付随・既に依存）か **WSL** を使う |

要件: `git` と POSIX コアユーティリティ（`sed`・`grep`・`awk`・`find`・`mktemp`）。macOS/Linux は
native、Windows は Git Bash か WSL に付属。一部アダプタはスタックのツールチェーン（`cargo`・`gradle` 等）も要る。

## ドキュメント

| ガイド | 内容 |
|---|---|
| [docs/development-workflow.ja.md](./docs/development-workflow.ja.md) ([EN](./docs/development-workflow.md)) | **まずここ** — ライフサイクル概観: 二重ループ・モデル（速いコード↔CI 内側ループ / 遅いハーネス自己評価の外側ループ）と何がいつ走るか |
| [docs/usage.ja.md](./docs/usage.ja.md) ([EN](./docs/usage.md)) | 導入・設定（`harness.config.sh`）・CI 配線; （任意）同期・還元 |
| [docs/structure.ja.md](./docs/structure.ja.md) ([EN](./docs/structure.md)) | 3層モデル・構成・消費機構・バージョニング |
| [docs/test-selection-roi.ja.md](./docs/test-selection-roi.ja.md) ([EN](./docs/test-selection-roi.md)) | **どの検証**が CI 採用に値するか — PBT / ステートフル PBT / mutation / モデル検査を ROI で |
| [docs/spec-rules.ja.md](./docs/spec-rules.ja.md) ([EN](./docs/spec-rules.md)) | テストと**モデル検査の両方**を駆動する**ルールを文書化** — ミニ言語・1ルール=2反映・トレーサビリティ・意図/欠陥ゲート |
| [docs/harness-roi-evaluation.ja.md](./docs/harness-roi-evaluation.ja.md) ([EN](./docs/harness-roi-evaluation.md)) | 入れた層を時間軸で**評価・剪定** — 2軸（CIコスト除去・維持負荷統合）・5判定 |
| [.claude/skills/gatecrate-setup/SKILL.md](./.claude/skills/gatecrate-setup/SKILL.md) | **エージェントスキル**（Claude Code / Codex）: プロジェクトにハーネス一式を構築。静的 install では埋まらない固有判断を担う |
| [.claude/skills/gatecrate-evaluate/SKILL.md](./.claude/skills/gatecrate-evaluate/SKILL.md) | **エージェントスキル**: 二階ループを回す — 各ゲートを計測し5判定を当て、剪定/統合を提案 |
| [templates/es-living-model-sample/](./templates/es-living-model-sample/) | **完成品の見本** — `sample-es.html` を開くと6タブのドメインモデルビューア（ドメイン中立の例）が見られる |
| [ROADMAP.md](./ROADMAP.md) | 消費ループの実証と育成の方針 |
| [CONTRIBUTING.md](./CONTRIBUTING.md) ([JA](./CONTRIBUTING.ja.md)) | バージョニング規則・PR ガイドライン |

## ディレクトリ構造

```
gatecrate/
├── core/                         # 汎用コア（スタック非依存 — どのプロジェクトでも動く）
│   ├── scripts/                  # スタック非依存スクリプト40本超（衛生ゲート・計測・ES文法・ハーネス自己検査）
│   ├── workflows/                # 汎用 CI（ci.yml・dashboard.yml 等）
│   └── docs/                     # コア層メモ
├── adapters/
│   ├── android-jvm/              # Android + JVM スタック固有アダプタ
│   │   ├── scripts/              # build/test/release スクリプト（mutation・smoke・build-* 等）
│   │   ├── workflows/            # ci.yml / mutation.yml / device-smoke.yml
│   │   └── gradle/               # build.gradle テンプレート
│   ├── python/                   # Python アダプタ（uv）: pytest/coverage + mutmut + ci.yml
│   ├── go/                        # Go アダプタ: go test/coverage + ci.yml
│   ├── typescript/                # TypeScript アダプタ（vitest）: test/coverage + ci.yml
│   ├── rust/                      # Rust アダプタ（cargo-llvm-cov）: test/coverage + ci.yml
│   ├── kotlin/                    # Kotlin アダプタ（Gradle + kover）: test/coverage + ci.yml
│   ├── haskell/                   # Haskell アダプタ（cabal）: test ゲート + ci.yml
│   └── lean4/                     # Lean4 アダプタ（lake）: build = 型/証明検査
├── templates/                    # 消費側へコピーされる設定テンプレート
├── profiles/                     # インストーラ選択プロファイル定義（minimal / standard / full / スタック別）
├── sync-manifests/               # （Advanced）opt-in 同期用 kit 管理ファイルのホワイトリスト
├── scripts/sync-check.sh         # （Advanced）kit 内部の同期ツール
├── .github/workflows/ci.yml      # kit 自身の CI（sh -n + shellcheck + manifest 整合性 + テスト）
└── install.sh                    # インストーラエントリポイント
```

全構成と消費機構: [docs/structure.ja.md](./docs/structure.ja.md)。

### 3層の役割

| 層 | ディレクトリ | 説明 |
|---|---|---|
| 汎用コア | `core/` | スタック非依存。コピーだけで動く（40本超。ゲート単位の台帳は [`docs/harness-status.md`](./docs/harness-status.md)） |
| アダプタ | `adapters/{android-jvm,python,go,typescript,rust,kotlin,haskell,lean4}/` | スタック固有。8スタック（各々を**検証専用の消費者**で実 pull_request 上で緑検証・外部プロダクトでの実採用はまだ）で core/adapter 境界がスタック非依存と実証 |
| プロジェクト固有 | `harness.config.sh`（導入先） | **kit に実値を置かない**。各プロジェクトが管理 |

## プロファイル

インストール時にプロファイルを選択します:

| プロファイル | 内容 |
|---|---|
| **Minimal** | 汎用コア衛生チェックのみ（conventional commits・シークレット検出・ファイルサイズ） |
| **Standard** | Minimal + JVM テストハーネス（テストスメル検出） |
| **Full** | Standard + mutation testing・スモークテスト |

`install.sh --profile auto` はスタックを自動判定します（pyproject.toml → python、Cargo.toml → rust 等）。

---

## Advanced: 同期し続ける・還元する（opt-in・チーム向け）

> **1つの kit で複数 PJ を運用する場合以外、ここは読み飛ばして構いません。** fire-and-forget の
> 消費者に以下は不要です — 導入済みスクリプトは既にあなたのものです。

sync 機構は**複数 PJ を束ねるオーナー**のためにあります。多数のプロジェクトを 1つの kit で運用すると、
ハーネスの修正を伝播させ、ある PJ で生まれた改善を還元したくなる。これは **opt-in** で、`install.sh` は
一切作りません。`sync-manifest.yaml`（kit の版 + 消費するスクリプトを宣言）を追加し、`sync-propose`
ワークフローをプロジェクトにコピーすることで有効化します。

### 同期の仕組み

`sync-manifests/<stack>.yaml` は、どのファイルを消費者へ伝播させてよいかを制御するホワイトリストです:

- `core/` と `adapters/` 配下のみを列挙。`src/**`・`harness.config.sh`・`profiles/` は含まない。
- 更新は PR（`sync-propose.yml`）として届き、受け側の CI ゲートを通過してからマージ
  （`HARNESS_SYNC_PAT` を設定すると同期 PR が CI を起動する）。
- opt-in した `consumed_scripts` は、そのスクリプト間依存（co-dependency）も併せて同期される。
- バージョンは SemVer。ラチェット締め付け（閾値引き下げ）は必ず **MAJOR** バンプ。

双方向の手順は [docs/usage.ja.md](./docs/usage.ja.md) §5–6 と [CONTRIBUTING.md](./CONTRIBUTING.md) を参照。

### 双方向の貢献（consumer ⇄ kit）

gatecrate は localmd-reader（**消費者第1号・現状 core のみ採用／アダプタ採用は進行中**）から抽出され、関係は双方向です:

- **上流（consumer → kit）**: 改善はまず消費側で生まれ（ハーネスが実際に動くのは消費側だから）、
  kit の汎用・パラメータ化形へ還元する。消費側固有のドリフト（ハードコードID・ホスト固有パス）は
  **還元しない**ので kit は移植性を保つ。
- **下流（kit → consumers）**: タグ付きリリースが同期 PR として各消費者へ伝播し、各消費者の CI で検証。

これはオーナーの運用フローであり、第三者の利用者に課す要件ではありません。エージェント向け規則は
[AGENTS.md](./AGENTS.md)、ループの実証は [ROADMAP.md](./ROADMAP.md) を参照。

---

## 日英ドキュメント同期

| ファイル | 言語 | 役割 |
|---|---|---|
| `README.md` | 英語 | **正文書** |
| `README.ja.md` | 日本語 | 補足翻訳 — `README.md` 変更時に同時更新すること |

## ライセンス

Apache License 2.0 — [LICENSE](./LICENSE) を参照。
