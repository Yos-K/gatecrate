# Rust 移植計画 — シェルスクリプト群の段階的移植（lib-first・配布形態は実測で決定）

このドキュメントは「95本・8,371行の sh スクリプトは抽象化に乏しく可読性が低い」という課題に対する
**Rust への段階移植**の設計を定める。読者はこの計画の承認判断と、移植作業の実施（人間/エージェント）に
必要な判断基準・順序・互換性契約を得る。

## 結論（何をするか）

1. **Rust workspace を新設**し、ロジックを**すべてライブラリ crate に置く（lib-first）**。
   バイナリ層は数十行の薄皮とし、**配布形態（単一バイナリ/ツール別/ソース配布）は今は決めない**——
   lib-first なら Cargo 設定の切替だけで後からどの形態へも移行できるため、Phase 0 パイロットの
   実測で決定する（下記「配布形態の決定手順」）。
2. **既存の `.sh` は「薄いシム」（≤15行）として残す**: `harness.config.sh` を source → Rust 実装へ exec。
   消費者の CI 配線・設定面・同期モデルは無変更のまま、実装だけが差し替わる。
3. sh のまま残すのは「**シェルであること自体が契約**」の部分のみ: git フック・installer・
   CI インラインステップ・`harness.config.sh`（source される設定）・シム自身・ROI が負の glue。

## なぜ（課題の根拠・2026-07-20 機械採取）

全数データは [rust-port-inventory.tsv](./rust-port-inventory.tsv)。要点:

| 事実 | 含意 |
|---|---|
| 95本・8,371行・平均88行 | 大半は小粒。しかし分布が極端に偏る |
| es-render-html.sh **800行**（300行ルールの例外登録で延命）・awk 8箇所 | sh で書くべきでない「コンパイラ」が sh に居る証拠 |
| awk 埋め込みが core 26本、measure-modularity は **10箇所** | sh+awk の2言語混在＝可読性劣化の主因。パース・集合演算・グラフ解析が文字列処理で書かれている |
| エージェント自身が sh の罠を踏んだ実録（handover: `emit_edge` の set -e 罠・mutation 検証での sed 不発→偽 SURVIVED） | 「読者は主にエージェント」時代でも sh の事故率は実害 |

**だから**: データ構造を要する「分析・コンパイラ層」を型のある言語へ移し、sh は「プロセス起動の
glue」以下に縮退させる。

## 守るもの（互換性契約 — これを壊す変更は本計画の対象外）

移植は実装の差し替えであり、以下の**外部契約は凍結**する:

| 契約 | 現状 | 移植後 |
|---|---|---|
| 呼び出し面 | `sh scripts/check-X.sh [args]` | 同一（シムが exec）。CI/preflight/フックの配線変更ゼロ |
| 設定面 | `harness.config.sh` を source → **実体は環境変数** | シムが source してから exec → Rust 側は `std::env` を読む。**設定契約は最初から env 変数だった**ので無修正互換 |
| exit code | 0=pass / 1=違反 / 2=setup | 同一 |
| 入出力形式 | PSV / TSV / `.es`・`.cmap` テキスト / HTML 射影 | 同一（既存挙動テストをゴールデンとして固定） |
| 同期・監査 | consumed_scripts の byte-identical 同期 | シムは従来どおり byte 同期。Rust 実装のバージョン整合は配布形態決定時に設計（未決定事項） |

## アーキテクチャ（lib-first）

```
crates/
  gatecrate-model/    # ライブラリ: .es/.cmap/PSV パーサと型（es-lint 系の核）
  gatecrate-gates/    # ライブラリ: 各ゲート = pub fn run(env, args) -> ExitCode
  gatecrate-metrics/  # ライブラリ: measure-*（coupling/complexity/modularity/diff-coverage）
  gatecrate-render/   # ライブラリ: HTML/ダッシュボード射影（es-render-html 等）
  bin/                # 薄皮。配布形態を知るのはここだけ（単一/複数/multi-call を後決め）
core/scripts/*.sh     # 移植済みはシム化・残留は従来どおり
```

- **lib-first の理由**: 「単一バイナリが正か」は現時点で判断材料が足りない（下記比較表）。ロジックを
  ライブラリに置けば、bin 層の組み替えだけで全形態に対応でき、**配布形態の決定を最も安い時点まで
  遅延できる**。
- **シムの形**（移植済みスクリプトの最終形・全シム共通の骨格）:

```sh
#!/bin/sh
# [shim] 実装は Rust（<version> 以降）。設定面と呼び出し面の互換のためだけに在る。
set -eu
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
BIN="${GATECRATE_BIN:-gatecrate}"
command -v "$BIN" >/dev/null 2>&1 || { echo "gatecrate: Rust implementation not found (see docs/design/rust-port-plan.md)" >&2; exit 2; }
exec "$BIN" check adr-review "$@"
```

- **移行期間の二重実装は持たない**（ドリフト源になる）。1本の移植が完了＝ゴールデンテスト一致した
  時点で旧 sh 実装をシムに置換し、同一 PR で切り替える。ロールバックは git revert で行う。

## 配布形態 — 決めないことを決める（本計画の要）

### 選択肢と本質的トレードオフ

| | A. 単一バイナリ（サブコマンド） | B. ツール別バイナリ | C. ソース配布（cargo install / features） |
|---|---|---|---|
| 採用の粒度 | ✗ consumed_scripts の「1本ずつ opt-in」哲学と不整合 | ◎ 現行哲学と一致 | ◎ features で選択可 |
| リリース結合 | ✗ 1ゲート修正で全体再リリース | ◎ 独立 | ○ |
| 配布物の数/サイズ | ◎ 5プラットフォーム×1個 | ✗ 5×N artifact・数十MB超 | ◎ artifact ゼロ |
| 消費者の導入摩擦 | ○ installer 1回 | △ 必要分だけDL（管理煩雑） | ✗ Rust toolchain 必須（CI はキャッシュで緩和可） |
| Termux 等の特殊環境 | △ クロスビルド依存 | △ 同左 | ○ ローカルビルドで逃げられる |
| バージョン整合検査（kit-drift 拡張） | ○ 1バージョン | ✗ N バージョンの整合 | ○ Cargo.lock/version 1点 |

### 決定手順（Phase 0 で実測してから決める）

1. パイロット（es-render-html 1本）を **C: ソース/手元ビルドで先に動かす**（配布インフラ不要で最速）。
2. 実測する: 消費者 CI での導入手数とビルド/キャッシュ時間・Termux での可否・リリース作業の手数。
3. 決定基準に照らして A / B / C / 混成（例: 分析層だけ束ねる multi-call）を選ぶ:
   - 消費者の導入手数が「現行の sh コピー＋α」以内か
   - リリース1回の手数（cargo-dist 等の自動化込み）
   - kit-drift のバージョン整合検査が素直に書けるか
4. 決定は ADR として記録する（`check-adr-review` のドッグフード対象）。

## 移植境界の基準（[ADR-0002](../adr/0002-rust-port-boundary.md) で確定）

境界は「ゲートか射影か」という層ではなく、**判定が構造を持つか**で引く（consumer 側エージェントの
独立レビューで層基準の誤分類——パーサを持つゲート es-lint を凍結し、構造の薄い check-adr-review を
移植する——が指摘され、基準を差し替えた）:

- **Rust へ**: 判定にパーサ・グラフ探索・集合演算を含むもの。実務閾値は「**埋め込み awk が30行を
  超えたら Rust を検討**」。2つの独立したエージェントが同クラスの sh 事故（変数展開・sed 不発の
  偽結果・行指向パースの構造誤り）を踏んでおり、いずれも shellcheck -S error は検出しない。
- **sh のまま（凍結でなく正解として）**: 正規表現1本・ファイル存在で終わる単純検査。cp 可搬性の
  価値がコストを上回り、**probe-gate-liveness が「スクリプト単体を使い捨てリポへコピーして注入」する
  前提とも互換**（シム化ゲートは単体コピーで動かない——binary 不在は exit 2 なので偽 ALIVE には
  ならないが、probe の対象にはできない）。
- **シェルであること自体が契約のもの**: git hooks・CI inline step・installer・source される設定・シム。

初期分類（inventory の機械採取 + 上記基準。最終判定は各移植 PR で確定）:

| 区分 | 本数目安 | 代表 |
|---|---|---|
| Rust へ（構造判定: パーサ/グラフ/集合演算） | ~18 | es-lint(-info)・es-cmap-lint・check-es-evidence・es-coverage・measure-*4本・render-harness-dashboard・classify-gate-type・check-diff-coverage・collect-gate-history・gate-roi-verdict |
| sh のまま（単純検査・probe 対象） | ~25 | check-conventional-title・check-no-committed-secrets・check-file-line-limit・check-hard-constraints・check-doc-currency 等 |
| sh 残留（シェル自体が契約） | ~10 | install.sh・フックテンプレ・シム・pr-preflight（CI 契約の入口） |
| sh 残留（ROI 判断の glue） | ~35 | adapters のビルド/エミュレータ/スクショ glue。**残留は永久指定ではない**（ROI が立てば移植可） |
| 例外（原型検証で移植済みの2ゲート） | 2 | check-adr-review・check-interaction-traceability の Rust 版は**消費者向けでなく kit 自身の CI 用**。消費者は sh 版を使い続ける（二重実装は役割分離で管理・ADR-0002 参照） |

## テスト戦略（移植の正しさをどう保証するか）

1. **既存 49 挙動テストスイートがそのままゴールデンテストになる**: テストは `sh script.sh` を叩き
   exit code とメッセージを検証している。シム化後も同じテストが Rust 実装を検証する——**テストを
   書き換えずに移植の等価性を証明できる**のが本設計の要。
2. Rust 側は crate 単位の unit test ＋ proptest（パーサの不変条件）。mutation は cargo-mutants。
3. 移植 PR の完了定義: 既存挙動テスト green（シム経由）＋ Rust unit green ＋ 実消費者1つで CI green
   （AGENTS.md ペアリング規則の維持）。

## 移行順序

| Phase | 内容 | 完了の定義 |
|---|---|---|
| 0 | workspace/シム機構の骨格＋**パイロット: es-render-html**（最大痛点・not-a-gate で消費者 CI 無リスク）＋ Termux 検証＋**配布形態の決定（ADR 化）** | パイロットのゴールデン一致・配布形態 ADR 承認 |
| 1 | 構造判定をもつ射影・計測（measure-*・es-coverage・dashboard・classify） | 各スクリプトの既存テスト green |
| 2 | 構造判定をもつゲート（es-lint 系・check-es-evidence・check-diff-coverage。**単純検査は移植しない** — ADR-0002） | 同上＋消費者1つで実走 |
| 3 | 二階ループの集計系＋残留最終判定＋シム最終化 | inventory 全行に Rust/sh-残留 の確定ラベル |

## 未決定事項

| 決めること | 影響度 | 判断に必要な材料 |
|---|---|---|
| **配布形態（A/B/C/混成）** | 高 | Phase 0 の実測（導入手数・ビルド時間・Termux 可否・リリース手数）→ ADR |
| Termux 対応の必須度 | 高 | Phase 0 の実機検証（localmd の実行環境が Termux） |
| リポ構成: 本リポ同居 workspace か別リポか | 中 | sync-propose/CI の改修量見積り。第一感は同居（consumer⇄kit ループを崩さない） |
| バージョン整合検査（kit-drift 拡張）の仕様 | 中 | 配布形態決定後。シム byte 一致＋実装 version 一致の2軸を MAJOR にしない書き方 |
| MSRV・edition・依存ポリシー（clap/serde 以外をどこまで許すか） | 低 | Phase 0 で確定 |
| 300行ルールの Rust への適用単位（ファイル or 関数） | 低 | 既存 fitness-metrics（S-03 クラス300行）に整合させる |

## この計画がやらないこと

- **配布形態の先行確定**（lib-first で遅延し、Phase 0 の実測と ADR で決める）
- 二重実装の並走維持（切替は PR 単位で不可逆・revert で戻す）
- `harness.config.sh` の形式変更（TOML 化等）——設定契約は env 変数のまま
- 残留 glue の無理な移植（ROI が立ってから）
- ratchet 閾値・ゲート挙動の変更（移植は挙動等価が原則。挙動改善は別 PR）
