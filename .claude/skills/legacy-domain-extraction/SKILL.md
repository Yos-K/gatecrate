---
name: legacy-domain-extraction
description: |
  テストの無い手続き型レガシーから、ドメイン知識（用語の定義・用語固有の不変条件・用語間の関係）を
  ハーネス構築駆動で抽出し、概念モデルとして文書化する。「レガシーのドメイン分析」「ルールを抽出して
  モデル化」「手続き型コードから仕様を起こす」「用語と不変条件を洗い出す」で起動。characterization で
  挙動を pin → mutation で未固定ルールを機械的に炙り出し → 宣言的配線/call graph から用語別 invariant を
  回収 → 用語・不変条件・関係の概念モデルを生成。必要に応じ形式モデル(Alloy)・探索的テスト(stateful PBT)へ。
  Do NOT use for: 既にクリーンな OO ドメインモデルがあるコード（読めば足りる）／純CRUD（不変条件が無い）／
  ハーネス自体の構築（gatecrate-setup を使う）／ドメイン知識でなく CI ゲートの新設。
argument-hint: "[target-cluster-or-module-path]"
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
metadata:
  author: Yos-K
  version: 0.1.0
---

# legacy-domain-extraction — 手続き型レガシーからドメイン知識を抽出し概念モデル化する

## 中心原則（なぜ・何を）

**なぜ**: 手続き型レガシーのドメインルールは if 連鎖・手続きフロー・定数に埋もれ、**目で読み出せない**。
要件文も無い。「読んで起こす」は精度が出ず、観測挙動をそのまま固定すると欠陥を仕様化する（characterization の罠）。

**だからどうするか**: ルールを**読まずに機械的に炙り出す**。mutation はコードの書き方を問わず挙動を摂動するので、
「誰もテストで固定していない振る舞い＝ルールの候補」を生存ミュータントとして指す。これを分類・命名・関係づけして
**用語中心の概念モデル**（用語の定義／その用語固有の不変条件／用語間の関係）に落とす。

**抽出するもの（出力の中心）**:
1. **用語の定義 + 用語固有の不変条件**（value/entity と invariant・実値）
2. **用語間の関係**（包含・ペア・多重度・条件付・整合・コンテキスト間の同一性）
3. **hotspot**（コードだけでは確定できない＝業務オーナー判断: なぜその値か／意図vs欠陥／同一性の疑い）

各ルールは「ミニ言語の宣言 / evidence(実コード行) / それを固定するテスト」の3点でトレース可能にする。

## フロー（開発フローと同型）

```
テスト作成 → 知識抽出 → モデル化 → (必要なら)形式モデル化 → (必要なら)探索的テスト検討
characterize  mutation+配線   概念モデル      Alloy                    stateful PBT
```

### Phase 0 — 成果物の品質バー（毎成果物・提示前の自己レビュー必須）

各成果物は**提示する前に**次を自分で通す。指摘されてから直すのでなく、この基準に達してから出す（レビューは
内容の妥当性判断に使ってもらい、欠落・体裁・整理の指摘に使わせない）。機械チェックはゲートが、判断チェックは本Phaseが担保する。

- **読み手チェック（機械）**: `check-jargon.sh`（記号・専門用語の説明併記）＋ `es-lint-info.sh`（情報完全性）＋
  `check-es-evidence.sh`（根拠の実在）を通す。加えて: なぜ→だからどうするの因果を書く／憶測禁止（根拠 or「未確認」明記）。
- **網羅チェック（判断）**: ドメインエキスパートが当然見る次元を落とさない（要求元の区別／システム思考の強化R・バランスB
  ループ／計測の取得方法・計算方法／整合性 強・結果／RDB・NoSQL 等）。「この観点は要らないか？」を一度問う。
  カード単位の網羅も確認: **AS-IS/TO-BE 両方の全カードに `role=`** が在り、**全コマンドが `.spec` か in/out/decide を持つ**
  （ビューアに「未分析」カードが残らない）こと、**AS-IS の各カードに `becomes=`（TO-BE対応）** が在ること。
  「TO-BEだけ埋める／一部コマンドだけ埋める／変化対応を欠く」を残さない。
- **完了チェック（判断）**: 機能は「動いた」で未完。ワークフロー組み込み＋behaviorテスト＋文書化＋ゲートまで揃えて完了。
- **一歩先（判断）**: 明らかに品質を上げる次の一歩（調整案v2・整理・図）は、聞く前に作ってから出す。最小版で止めない。

`es-converge`(TAKT) は読み手チェック（機械）を毎周回す。判断チェックはエージェント（本スキル）が提示前に自答する。


## フェーズ索引（実行時に reference/ を読む）

**手順の詳細は分割ファイルにある。各 Phase に着手する前に、該当 reference を必ず Read すること**
（常時適用の規律は本ファイルに残している——読むのは「手順」、守るのは「規律」）。

| Phase | 内容（1行） | 詳細 |
|---|---|---|
| 1-5 | クラスタ選定→隔離→characterize→mutation収束→用語・不変条件の回収 | [reference/extraction.md](reference/extraction.md) |
| 6〜6.8 | `.es`モデル化→ユースケース→ビジネス分析/CLD→リファクタ+ハーネス計画→永続化設計 | [reference/modeling.md](reference/modeling.md) |
| 7-9（任意） | Alloy形式化 / stateful PBT / TAKT収束ループ | [reference/extraction.md](reference/extraction.md) |

## 常時適用の規律（ダイジェスト——詳細・理由は reference/modeling.md）

- **ES意味規律**: 真のドメインイベントのみ（取得/照会/ロック等の問合せ・技術操作は event にしない）。アクター起点、
  actor→command→aggregate→event の順序。**1図=1BCスライス（40ノード以下）**、ドメイン全体は `.cmap` で俯瞰。
- **カード網羅**: AS-IS/TO-BE 全カードに `role=`、全コマンドに `.spec` か in/out/decide、AS-IS 各カードに
  `becomes=<TO-BE id> | 変化。なぜ: 理由`。動詞・状態には「// ドメイン上の意味」。**「未分析」カードを残さない**。
- **源泉一本化**: ドメイン知識の源泉は `.es`/`.spec`/`.cmap`。用語集等の読み物は射影。手書きで二重管理しない。
- **完成と収束**: 完成は感覚でなく **`check-es-deliverables` の exit 0**（自分でゲートを回し green まで直してから出す。
  TAKT `es-complete`/`es-converge` は外部ガードレール）。render 前に `es-lint-info` WARN→0。

## hotspot（コードだけでは出せない＝人間へ）

| 出せない | なぜ | 扱い |
|---|---|---|
| なぜその値か（業務意味） | mutation は What を pin するが Why を持たない | hotspot → オーナー |
| 意図 vs 欠陥 | 観測挙動からは判定不能（命名と実装の乖離等） | proposed-rule で起票・人間裁可 |
| コンテキスト間の同一性 | 別名・別長の概念が同一か | context-map に疑いとして残す |
| 横断/順序の不変条件 | 単一クラスタ mutation の範囲外 | Phase 7/8 へ |

## 完了の判定

- 被検クラスタの mutation strength が収束（≈100% / 残り等価のみ）。
- 用語の定義＋固有不変条件（実値）＋用語間の関係が、evidence と固定テスト付きで概念モデルに記載。
- 確定できなかった点が hotspot として列挙され、オーナー確認待ちが可視。
- **成果物の完全性ゲート通過（最重要・手抜き防止）**: `check-es-deliverables` が **ERROR=0**＝AS-IS/TO-BE/コンテキスト
  マップ/ビジネス分析源泉/分析レポートが揃い、各 .es/.cmap が文法を通る（6タブの源泉が完備）。TAKT `es-complete` で駆動。
- **Phase 0 品質バー通過**: 全成果物が `check-jargon`/`es-lint-info`/`check-es-evidence` を通り、網羅・完了・一歩先の判断チェック済み。
- ビジネス分析（収益/価値/UX分類・オブザーバビリティ・因果ループの調整案）が出ている（Phase 6.6）。
- AS-IS→TO-BE リファクタ＋ハーネス ロードマップ（Phase 6.7）と 永続化設計（Phase 6.8）が、TO-BE集約と相互参照付きで出ている。
- （理想）順序/状態の不変条件が Alloy assert に、毎PR の回帰が実装テストに、二重反映されている。

## 参照

- 手順詳細: [reference/extraction.md](reference/extraction.md) / [reference/modeling.md](reference/modeling.md)

- ハーネス構築: `gatecrate-setup` スキル / `docs/test-selection-roi.md`（検証選定）
- characterization 雛形: `templates/characterization/`（Java/Kotlin・依存ゼロ golden-master）
- 文法ゲート: `core/scripts/es-lint.sh` / `es-render.sh`、`docs/event-storming-grammar.md`
- 形式モデル: `alloy-spec-model-generator` スキル / `core/scripts/check-domain-model.sh`

