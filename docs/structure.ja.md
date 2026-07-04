# 構造

gatecrate の構成と、その理由。English: [structure.md](./structure.md)。

本書はリポジトリ構成と消費機構の正典。スクリプト追加・新アダプタ追加・設定解決方法の
変更を行う前に読むこと。

## 3層モデル（なぜ）

再利用可能なハーネスは、変化する理由が異なる3つを分離する必要がある:

| 層 | いつ変わるか | 置き場所 |
|---|---|---|
| **汎用コア** | 普遍的に正しい衛生ルールが変わるとき（例: 「シークレットを置かない」） | `core/` |
| **スタックアダプタ** | スタックのツールが変わるとき（例: JVM テストランナのフラグ） | `adapters/<stack>/` |
| **プロジェクト設定** | 個別PJの値が変わるとき（パッケージID・閾値） | **消費側の** `harness.config.sh`（kit には絶対に置かない） |

この分離こそが移植性の核。消費側は core + 自分のスタックのアダプタを取り込み、
**自分の値だけ**を供給する。プロジェクト固有値が kit に入らないので、1つの kit が
多数のPJに使える。

## ディレクトリ構成

```
gatecrate/
├── core/                       # 汎用・スタック非依存層
│   ├── scripts/                #   スタック非依存スクリプト40本超（衛生ゲート・計測・ES文法・ハーネス自己検査）
│   ├── workflows/              #   汎用 CI（ci.yml・dashboard.yml・merge-integrity.yml 等）
│   └── docs/                   #   コア層メモ
├── adapters/
│   ├── android-jvm/            # Android + JVM スタックのアダプタ
│   │   ├── scripts/            #   build/test/release スクリプト30本超（mutation・smoke・build-* 等）
│   │   ├── workflows/          #   ci.yml / mutation.yml / device-smoke.yml
│   │   ├── gradle/             #   build.gradle テンプレート
│   │   └── README.md           #   アダプタメモ
│   ├── python/                 # Python アダプタ（uv）: run-tests.sh + run-mutation.sh + ci.yml
│   ├── go/                     # Go アダプタ: run-tests.sh（go test/coverage）+ ci.yml
│   ├── typescript/             # TypeScript アダプタ（vitest）: run-tests.sh + ci.yml
│   ├── rust/                   # Rust アダプタ（cargo-llvm-cov）: run-tests.sh + ci.yml
│   ├── kotlin/                 # Kotlin アダプタ（Gradle + kover）: run-tests.sh + ci.yml
│   ├── haskell/                # Haskell アダプタ（cabal）: run-tests.sh + ci.yml
│   └── lean4/                  # Lean4 アダプタ（lake build = 型/証明検査）
├── templates/                  # 消費側 scaffold（プロジェクトごとにコピー/調整）
│   ├── harness.config.sh.example   # 設定インタフェース（SHELL・source される・install.sh が harness.config.sh にコピー）
│   ├── hooks/                  # Claude Code Stop hook（spec-test mutation ゲート）＋ settings
│   ├── kiro-steering/          # cc-sdd custom steering（spec-test ループ）
│   ├── spec/                   # 規則文書の骨子（README＋area.md）＋ models/example.als.example
│   ├── takt/                   # TAKT オーケストレーション: config＋workflows（evaluate-cycle / liveness-converge / rule-reflect）＋personas
│   └── gate-groups.tsv.example # collect-gate-history の論理ゲート relabel マップ
├── .claude/skills/             # kit エージェントスキル: gatecrate-setup, gatecrate-evaluate, alloy-spec-model-generator
├── profiles/                   # インストーラのプロファイル定義（minimal / standard / full）
├── sync-manifests/             # スタック別の kit 管理ファイル ホワイトリスト（android-jvm.yaml）
├── scripts/                    # kit 内部ツール（sync-check.sh）
├── install.sh                  # インストーラ入口（プロファイル選択器）
├── .github/workflows/
│   ├── ci.yml                  # kit 自身の CI（sh -n + shellcheck + manifest 整合性）
│   └── sync-propose.yml        # 消費側がコピーして kit 更新を PR で受け取るテンプレート
├── ROADMAP.md  CHANGELOG.md  CONTRIBUTING.md  README.md (+ .ja)
```

件数は意図的に概数で書く——正確な数は kit の成長とともに必ず陳腐化する。ゲート単位の
正確な台帳はコミット済みダッシュボード（`docs/harness-status.md`）が担う。

## 消費機構（kit スクリプトが消費側でどう動くか）

kit スクリプトは2箇所で**無改変のまま**動く必要がある: ここ（例
`adapters/android-jvm/scripts/check-file-sizes.sh`）と、消費側へインストールされた形
（`scripts/check-file-sizes.sh`）。これを可能にする2原則:

1. **repo root は相対深度でなく git で解決。** スクリプトは
   `git rev-parse --show-toplevel`（失敗時は相対パスにフォールバック）で root を求める。
   kit と消費側ではパス深度が異なるため、`../../..` のハードコードはインストールで壊れる。
   git 解決は深度非依存。これにより kit↔消費側の同期が**差分ゼロ**になる（同一バイトのファイルが両方で動く）。

2. **設定は `harness.config.sh` を存在すれば source。** スクリプトは環境変数を読み、
   repo root の `harness.config.sh` があれば source する。kit には無い（＝デフォルト適用）、
   消費側がそこに自分の値を置く。設定は shell（`.` で source）— スクリプトが env var を読むため、
   YAML では配線できない。

> 状態: core の全スクリプトが本消費モデルへ移行済み（`check-file-sizes.sh` がパイロット。
> [ROADMAP.md](../ROADMAP.md) P2 の移行は `core/` について完了）。値だけでなく
> **固有ロジック**を持つスクリプト（例 `run-mutation-tests.sh`）は、設定シーム経由でロジックを注入する。

## バージョニング

SemVer。ratchet を締める（閾値を下げる）等、消費側を壊す変更は **MAJOR**。スクリプト/設定の
追加は MINOR、修正は PATCH。各タグに `CHANGELOG.md` エントリ必須。[CONTRIBUTING.md](../CONTRIBUTING.md) 参照。
