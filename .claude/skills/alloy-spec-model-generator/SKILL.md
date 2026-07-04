---
name: alloy-spec-model-generator
description: |
  JavaクラスタからAlloy 6形式仕様モデルを3段パイプライン
  （仕様抽出→流儀サマリ→形式化）+ CI昇格判断（Phase 4）で生成・検査する。
  「Alloyモデル作りたい」「仕様を形式化したい」「ドメインモデルを検査可能に
  したい」「.alsを作って」「check-domain-model.shで検査したい」で起動。
  Do NOT use for: 状態・写像・不変条件のない純粋CRUDクラスタ、
  Alloy以外の形式手法（TLA+等）、一般的なJavaリファクタリング。
argument-hint: "[cluster-name or target-class-path]"
allowed-tools: Read, Grep, Glob, Bash, Write
---

# alloy-spec-model-generator

Javaクラスタ → Alloy 6 検査可能仕様モデルを 3段パイプライン＋CI昇格判断で生成する。

## North Star

状態・写像・不変条件を持つJavaクラスタを、機械検査可能な Alloy 6 形式仕様に変換する。
生成した `.als` を `check-domain-model.sh` で全 PASS させ、設計保証を証明する。

## 適用判断

**適用すべき4条件（全て満たすこと）**

| 条件 | 具体例（購入状態クラスタ） |
|------|------------------------|
| 有限の状態列挙（enum）が存在する | PurchaseState: 5状態（Purchased/NotPurchased/Pending/Unknown/BillingUnavailable） |
| 永続化コード↔状態の写像がある | persistenceCode() / fromPersistenceCode() |
| 「この状態のときだけXが真」という不変条件がある | entitlement(): purchased のみ Pro |
| fail-safe（未知入力→デフォルト状態）ロジックがある | 未知コード → unknown() |

**適用不可の3ケース**

- 状態列挙のない純粋なCRUDリポジトリクラス
- 写像・不変条件のないユーティリティクラス（文字列変換等）
- 全フィールドがmutableで遷移ルールが外部依存のクラス

**候補クラスタを扱う場合は必ずコードを確認すること**

タスクYAMLや他エージェントの報告に「適用候補」とあっても、コード未読のまま適用を決定しない。
`src/main/java/` の実際のenumや写像関数を確認してから判断する。

## Phase 1: 仕様抽出

対象クラスタの `src/main/java/` と `src/test/java/` を読み、5セクションでレポートを作成する。
出力先: `queue/tmp/{cluster-name}_analysis.md`（手本: `queue/tmp/001a_purchase_analysis.md`）

| # | セクション | 内容 |
|---|-----------|------|
| 1 | 状態列挙 | 全状態値の対応表（enum値・内部コード・文字列コード）＋写像関数の仕様 |
| 2 | 不変条件 | Alloy assert 候補（単射性・ラウンドトリップ・排他性・fail-safe） |
| 3 | 関連型の役割 | 生成元・保持者・消費者・独立型の分類と根拠 |
| 4 | 外部からの状態変化 | 値オブジェクトか否か → 静的/動的モデルの選択根拠 |
| 5 | 既存テストが確認している仕様 | テスト名と確認している仕様の対応表 |

**根拠ルール**: 全記述にソースコードのファイル名を付記する。行番号を書く場合は `grep -n` で実測した値のみ使用すること（推測禁止）。

## Phase 2: 流儀サマリ

`docs/domain/models/*.als` と `scripts/check-domain-model.sh` を読み、5セクションでサマリを作成する。
出力先: `queue/tmp/{cluster-name}_conventions.md`（手本: `queue/tmp/001b_alloy_conventions.md`）

| # | セクション | 内容 |
|---|-----------|------|
| 1 | ファイル先頭コメントの形式 | 必須4要素（目的・対応仕様・実装ファイル・実行方法） |
| 2 | Alloy 6 構文パターン | module/enum/sig/fun/pred/fact/assert/check の書き方 |
| 3 | 静的/動的モデルの使い分け基準 | 静的部分と動的部分の判断基準表 |
| 4 | check-domain-model.sh の実行方法 | 引数なし/特定モデル/期待出力形式/反例出力先 |
| 5 | 新 .als ファイル作成チェックリスト | 各構成要素のチェック項目 |

**直接引用ルール**: 構文・コードは `.als` ファイルから直接引用する。「おそらく〜」での転記禁止。
ファイル名を出典として明記する（例: `appearance-theme.als`）。

## Phase 3: 形式化

Phase 1 レポート + Phase 2 サマリ + 手本 `.als` を入力として `.als` ファイルを生成する。
出力先: `docs/domain/models/{camelCaseName}.als`

**ファイル構成順序**:
1. ファイル先頭コメント（目的・対応仕様・実装ファイル・実行方法）
2. `module <camelCaseName>`
3. 語彙（enum定義）
4. 写像関数（fun定義）
5. 静的な保証（assert + check expect 0）
6. 既知の制約（check expect 1 ＝意図した反例を期待）

**assert 6パターン**（出典: `pro-purchase-state.als`）

| パターン | 検査する性質 |
|---------|------------|
| `XxxIsInjective` | 写像の単射性（異なる入力→異なる出力） |
| `RoundTripRestoresXxx` | 双方向写像の整合性 |
| `OnlyXxxGrantsYyy` | 特定条件のみが権限を付与 |
| `XxxArePairwiseExclusive` | 状態フラグの排他性 |
| `UnrecognizedXxxFailsSafe` | 未知入力のfail-safe |
| `EveryXxxIsRestorable` | 全射性（全状態に到達可能） |

**静的 vs 動的モデル判断表**

| 条件 | 選択 |
|------|------|
| 不変の値オブジェクト（セッターなし・遷移メソッドなし） | 静的モデルのみ |
| 「ある時点での状態が何か」を表す型 | 静的モデルで十分 |
| セッション中に状態が変化するシナリオを検査したい | 動的モデル（`var` + `fact behaviour`） |
| 「N操作後も不変条件が崩れないか」を検査したい | 動的モデル + `for N but M..K steps` |

## Phase 4: CI昇格判断

**4-1. check-domain-model.sh のadvisory設計確認**

`scripts/check-domain-model.sh` を読み、java未インストール時・jar取得失敗時に exit 0 でスキップする
advisory設計が存在するか確認する。存在しなければ gatecrate の core/workflows/domain-model-check.yml と
core/scripts/check-domain-model.sh を採用する。

```sh
if ! command -v java >/dev/null 2>&1; then
  echo "domain-model: java not found; skipping (advisory check)." >&2
  exit 0
fi
```

**4-2. 既存workflow調査**

`.github/workflows/` を確認し、`domain-model-check.yml` が存在するかチェックする。

**4-3. domain-model-check.yml 追加判断表**

| 条件 | 判断 |
|------|------|
| `docs/domain/models/*.als` が存在する | 追加すべき |
| `scripts/check-domain-model.sh` が存在する | 追加すべき |
| GitHub Actions が利用可能 | 追加すべき |
| `domain-model-check.yml` が既に存在する | スキップ（重複防止） |

**4-4. 設計原則4点**（skip可視化ステップ等の詳細は `domain-model-check.yml` を直接参照）

1. Advisory設計を維持: required check に登録しない（ブロックしない）
2. continue-on-error を使わない: 本物の異常（予期しない反例・jar checksum不一致）は赤で見える
3. スキップは警告として表示: `::warning::` で可視化し「検証されなかった」ことを明示
4. path フィルタ: `.als` ファイルと `check-domain-model.sh` の変更時のみ起動

**重要**: required check への誤った登録（advisory なのに必須化）は環境依存でのビルドブロックを引き起こす。
CI設定管理者に確認してから追加すること。

## 教訓（落とし穴）

**落とし穴1: equals() 未オーバーライドの等価性モデリング**

出典: `pro-purchase-state.als`、`001a_purchase_analysis.md`

状態enum（例: `PurchaseState`）に `equals()` がオーバーライドされていない場合、ラウンドトリップ検査は「同一インスタンスへの復元」ではなく「同値状態への復元（機能的等価）」として解釈する。モデルファイルの先頭コメントに「各 atom は value フィールドが等しい状態の同値類を表す」と明記すること。

**落とし穴2: 意図された非単射（fromPersistenceCode は単射ではない）**

出典: `pro-purchase-state.als`（`check FromPersistenceCodeIsInjective expect 1`）

`fromPersistenceCode` は複数の未知コード（例: `UnknownCode` と `UnrecognizedCode`）が同じ `Unknown` 状態に写るため単射でないことがある。これは「バグ」ではなく fail-closed 設計の意図。`check expect 1`（反例1件を期待）として文書化し、修正しないこと。

**落とし穴3: 一見「未知コード」に見える明示分岐を見落とさない**

出典: `001a_purchase_analysis.md`、状態enumの実装ファイル

`"billing_unavailable"` のようなコードは一見「未知コード」に見えるが、`fromPersistenceCode()` に明示的な分岐があり既定状態に倒れないことがある。必ずコードを直接確認すること（推測禁止）。

## バリデーション

```sh
# 全モデル検査
sh scripts/check-domain-model.sh

# 特定モデルのみ
sh scripts/check-domain-model.sh docs/domain/models/<name>.als
```

全 assert が `expect 0`（または意図した `expect 1`）で PASS したら完了。

**ネットワーク制限環境の注意**: Alloy jar の自動ダウンロードが失敗する場合がある。
その場合は `ALLOY_HOME` 環境変数で手動配置した jar のパスを指定する。
