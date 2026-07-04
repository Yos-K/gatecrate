# コンテキストマップ文法（`.cmap`）と BC 導出法

本書は、イベントストーミング(ES)の結果から**境界づけられたコンテキスト(BC)**を導出し、BC間・BC-外部の
関係を描く `.cmap` 文法と、その文法ゲート `es-cmap-lint`、そして**BCを客観的に導く手順**を説明する。
読者は「なぜそのBC分割になるのか」を、人の好みでなく**アクター・同一性キー・語彙**から説明できるようになる。

## なぜ BC 導出に手順が要るか（因果）

**なぜ問題か**: BCを「同じ業務フローに出てくるから」で束ねると、別言語・別ライフサイクルの集約が1つのBCに
混ざる（実例: チャージ要求・決済取引・ステップチャージ受付を「容量管理」に一括 → 決済の言語が容量の言語に埋もれた）。
**だからどうするか**: BCは次の客観シグナルで導く。**集約名だけでは不十分**で、アクター（立場）まで見る。

## 複数リポ・境界混在のときの進め方（リポ≠BC）

**リポ ≠ BC**。1リポに複数BCが同居し、1BCが複数リポにまたがるのが普通。だから「リポごとに `.es`」も
「全リポを1つの `.es` に詰める」も誤り（後者は100ノード級の毛玉になる＝R9）。**BCを軸に**進める:

1. **Big Picture**: 全リポ横断でドメインイベントを収集→**同一状態変化は1つに統合**（別名併記）、**非ドメイン
   （取得/照会/ロック/CRUD/技術）は除外**（R10）。
2. **BC導出**: 下の「集約所有＋アクター＋同一性＋語彙」でクラスタリング（**リポ/パッケージ＝Conwayで切らない**）。
   `.cmap` に各BCを置き、**`repos=` でどのリポ群が実装するかを記録**（リポ⇔BCのM:Nを可視化）。
3. **スライス**: **BCごとに `.es` を1本**（15〜40ノードの読める図）。1BCの `.es` は複数リポのコードを束ねてよい。
4. **連結**: `.cmap` の関係（CS/Conformist/ACL/…）と**連結キー**でBC間（＝リポ間）の統合を表す。
   「境界が混じり合う点＝同じ識別子で複数BCが突合する箇所」は、共有モデルでなく**連結キー**として REL に現れる。
5. **精製**: BCごとに characterization→mutation→`es-converge`(WARN→0)。

**混在のサイン**: 同じリポが複数BCの `repos=` に出る→責務過多(分割候補) / 1BCが複数リポにまたがる→分散(統合/ACL候補)
/ 同一識別子が多BCに出る→共有カーネルでなく連結キー（複製＋乖離があれば無管理重複）。

## BC 導出法（アクター＋同一性キー＋語彙）

各 command→aggregate→event の流れについて、集約ごとに次を並べて**クラスタリング**する。

| シグナル | 何を見るか | BC分割の含意 |
|---|---|---|
| **同一性キー** | 集約が何で一意になるか（例 顧客ID vs 注文ID＋決済ID）| キーが違えば一貫性境界が違う → 別BC候補 |
| **語彙** | fields/states/behaviors の用語（在庫数/引当 vs 与信/売上確定）| 語彙体系が違えば別の言語 → 別BC |
| **アクター/トリガー** | 誰が・何で起こすか（ユーザの都度要求 vs 外部システムのイベント通知 vs 定期バッチ）| **同名集約でも立場で必要情報が違えば別BC** |
| **外部依存** | どの外部システムと話すか（在庫システム vs 決済システム）| 連携先が違えば関心が違う |

**原則（kawasima ユビキタス言語より）**: 「同じ言葉でも立場によって必要な情報が違う」。同じ顧客を
扱っていても、在庫引当の立場は在庫数を、決済の立場は決済IDを必要とする → **別BC**。
共有される識別子（顧客ID等）は**共有モデルではなく連結キー**で、REL の `key=` に現れる。

**要求元は別ノードで描く**: 同じ集約への要求でも、要求元（アクター/上流BC）が異なれば別ノードにする。
読み手が「この要求はどこから来たか」を図で追える（例: 都度購入＝外部サービス / 定期付与＝別経路）。
要求元かどうかはコードで検証する（例: 月初バッチが charge を起こすか SpsCharge 呼出の有無で確認）。

## コア／サブドメインの分類（`kind`）

各BCに `kind=core|supporting|generic` を付ける。**core**=競争力の源泉（最も注力）、**supporting**=コアを
支える固有業務、**generic**=既製・共通で代替可。注力配分とMS分割優先度の根拠になる。

## `.cmap` 文法

```
BC  <id> <名前> [| kind=core|supporting|generic | aggregates=集約名;… | summary=… | repos=… | discuss=…
                 | domain=ドメイン群名 | es=そのBCのESビューアhtmlへの相対パス]
EXT <id> <名前> [| summary=…]
REL <from> <CS|Conformist|ACL|SharedKernel|PL> <to> [| key=連結キー | reason=根拠]
```

- `domain=` / `es=` は横断ハブHTML（下記 `es-render-cmap-html`）が読む描画属性。lint は未知属性を許容する。

- `aggregates=` は ES(`.es`) の集約ラベルを指す。ビューアは各BCが含む **コマンド→集約→イベントの流れ** を
  そこから描く（同じ集約名のまとまりがそのBCの中身）。未登録なら「ESモデル未作成」と表示＝次に作る対象。
- **関係種別**: `CS`(Customer-Supplier 顧客-供給) / `Conformist`(順応) / `ACL`(腐敗防止層) /
  `SharedKernel`(共有カーネル) / `PL`(Published Language 公表言語)。方向は from→to。
- `discuss=` に**導出根拠**（同一性キー/語彙/アクター）と**決めること**を残す（人の裁定はこの後）。

## 文法ゲート `es-cmap-lint`（prevention）

`core/scripts/es-cmap-lint.sh`。挙動テスト `tests/test-es-cmap-lint.sh`（5性質・9アサーション）。

```sh
sh core/scripts/es-cmap-lint.sh map.cmap
```

- **R1** REL の from/to は宣言済み BC/EXT id（**スペース抜け `id|` を reject**＝Mermaid描画崩壊の再発防止）
- **R2** REL の関係種別 ∈ {CS,Conformist,ACL,SharedKernel,PL}
- **R3** BC/EXT 行は id と 名前 を持つ
- **R4**(warn) BC に summary 無し / REL に reason 無し / kind が不正

## 描画と消費

`.cmap` は座標なしテキストの**源泉**で、図は射影（AIは座標を書かない）。`es-render-html.sh` に第3引数として
渡すと「コンテキストマップ」タブが出る。BCクリックで責務・所属リポ（複数プロジェクト横断）・含むES流れ・
上流/下流関係（連結キー・根拠）を表示。詳細は [`event-storming-grammar.md`](event-storming-grammar.md) /
[`es-living-model.ja.md`](es-living-model.ja.md)。

```sh
sh es-render-html.sh asis.es tobe.es domain.cmap > model.html
```

## 横断ハブHTML（`es-render-cmap-html`）— 複数リポ・複数AS-ISの入口

**なぜ**: 複数リポを束ねると複数の AS-IS が同一の TO-BE に収束し、BC別ビューアだけでは TO-BE が
各ページに重複して見える。これは表示でなく「TO-BE の源泉が複数箇所にある」構造の問題。
**だから** TO-BE の全体像は横断の `.cmap` 1つに一本化し、そこから各BCの ES 図へ降りる:

```sh
sh es-cmap-lint.sh all.cmap && sh es-render-cmap-html.sh all.cmap "全体コンテキストマップ" > hub.html
```

- `domain=` で BC をドメイン群（subgraph の枠）にまとめ、`kind=` で色分け
  （core=緑・supporting=青・generic=紫・EXT=灰）。
- `es=` を持つ BC はクリックでその ES ビューアへ遷移。**click 行は属性から機械生成**（手書きしない）。
- `es=` の無い BC は「ESモデル未作成（次に作る対象）」として一覧される＝モデリングの作業キュー。

## 限界

- BCの最終確定（特に core/supporting/generic の裁定、要求元の同一性）は人間・ドメインエキスパートが行う。
  本手順は**客観シグナルで候補を出し、根拠を残す**ところまで。`es-cmap-lint` は文法を保証するが意味は保証しない。
