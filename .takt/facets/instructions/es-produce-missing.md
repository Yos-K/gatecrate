# 指示: 欠落していた成果物を作る（手抜きをしない）

前ステップ(audit)が名指しした欠落を、`legacy-domain-extraction` スキルの規律に沿って作れ。**TO-BEを省略しない**。

## 欠落の種別ごと

- **D2 TO-BE無し**: AS-IS（コードの流れ）から、あるべき設計の `*-tobe.es` を起こす。隠れた集約を表出し、状態機械
  (states/transitions)・ポリシーの述語(behaviors)・イベントの型(fields)・イベントの事業分類(biz)を入れる。
  AS-IS の各カードには `becomes=<TO-BE id> | 変化。なぜ: …` を付ける。**cmap だけ作って TO-BE を飛ばすのは不可**。
- **D3 cmap無し**: 集約所有＋アクター＋同一性キー＋語彙で BC を導出し `.cmap` を作る（repos= でリポ対応）。
- **D4 biz=無し**: TO-BE の event を `biz=revenue|value|degrade` で分類し、`measure=`/`capture=`/`compute=` を入れる。
  必要なら因果ループ `.cld` も作る。
- **D5 分析md無し**: `*-refactoring-roadmap.ja.md`（なぜハーネスを積むか＋各Rの消すリスク）と
  `*-persistence-design.ja.md`（整合性 強/結果・RDB/NoSQL・データモデル）を作る。
- **D6 文法違反**: es-lint / es-cmap-lint のエラーを直す。

## 制約（スキルの規律を守る）

- 真のドメインイベントだけ（取得/照会/ロック等の問合せ・技術操作は event にしない＝R10）。
- 1図=1BCスライス（>40ノードに詰めない＝R9）。アクター起点、order は actor→command→aggregate→event。
- 用語は初出で平易化（check-jargon）、AS-IS→TO-BE変化には「なぜ」（R8）、evidence は実在（捏造しない）。
- コードから確定できない点は `discuss=`/hotspot に残す（無理に埋めない）。次の audit で再判定される。
