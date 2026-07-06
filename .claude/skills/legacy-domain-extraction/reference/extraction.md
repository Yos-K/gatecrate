# reference/extraction — 抽出フェーズの詳細手順（Phase 1-5, 7-9）

本ファイルは legacy-domain-extraction スキルの**手順詳細**。各 Phase の実行時に読む（SKILL.md は規律と索引）。

### Phase 1 — クラスタ選定（mutation が効く＝ルールが宿る場所を選ぶ）

分岐密度が高く・フレームワーク依存が薄く・隔離コンパイル可能な**業務ロジック**を選ぶ。命名 `*Validator`/`*Calculator`/
`*Judge`/`*Rule`/`*Eligibility`/`*Spec`、計算/判定の匂い（金額・割引・率・期間・区分）。スコアリング例:

```sh
for f in $(grep -rl 'class .*\(Validator\|Calculator\|Judge\|Rule\)' --include='*.java' <area>); do
  br=$(grep -cE '\bif\b|\bswitch\b|&&|\|\|' "$f"); loc=$(wc -l <"$f")
  fw=$(grep -cE '^import (org\.springframework|software\.amazon|jakarta\.|javax\.)' "$f")
  [ "$br" -ge 12 ] && [ "$fw" -le 2 ] && echo "$br $loc $f"
done | sort -rn | head
```

避ける: 文字列カタログ/i18n（不変条件が薄く mutation 低信号）、純 IO/パーサ（ドメインでない）。

### Phase 2 — 隔離（コンパイル可能にする）

被検クラスタ＋直接依存だけを切り出す。**呼び出し元はスタブ**（enum/型は最小再現）、**leaf 述語は実装を忠実に取り込む**
（自分の推測でスタブすると挙動を誤って固定する）。外部 jar は版を固定してローカルに置く。`javac` で通るまで。

### Phase 3 — characterize（挙動を pin）

golden-master（approval）で現挙動を固定する。雛形は `gatecrate templates/characterization/`（Java/Kotlin・依存ゼロ）。
**開発者の初手レベル**（valid + 代表的 invalid）で十分。薄いほど Phase 4 の生存が増え、より多くのルールが surface する。

### Phase 4 — mutation で未固定ルールを炙り出し → 収束

PIT 等を被検クラスタに当てる（survivor-strict）。**生存ミュータント = テストが固定していないルール**。各生存について:

1. **分類**: その行はどんな業務ルールをエンコードしているか。**意図 vs 欠陥**（プロダクト判断）。
   観測挙動を自動正典化しない——欠陥なら hotspot 化してオーナーに諮る。
2. **specify**: ルールをミニ言語で記述（`invariant/policy` + evidence）。
3. **reflect**: そのミュータントを殺すテストを追加。再 mutation。
4. 生存が収束（strength≈100% または残りが等価ミュータント）まで反復。

> 例: 長さチェックの `> max` で ConditionalsBoundaryMutator が生存 → 「境界 inclusive（ちょうど max は有効）」という
> 未固定ルールを、コードを読まずに特定。境界テスト追加で kill。

### Phase 5 — 用語と不変条件の回収（call graph を辿る）

**重要な構造的事実**: 被検クラスタが「汎用メカニクス」（検証の効き方・計算手順）で、**ドメイン固有の値**
（どの用語が何桁・どの固定値・どの範囲か）は**呼び出し元が引数で注入**していることが多い。よって:

- 被検クラスタ単体 = メカニクスのルール（Phase 4 で固定）。
- **呼び出し元（caller）の宣言的配線を辿る** = 用語別の不変条件（`validateX(TERM, getter, LEN, ...)` → 「TERM は LEN 桁」）。
  これは宣言的なので読み取れる。定数は解決して**実値**にする（推測禁止）。
- 用語の定義は enum/フィールドのコメント・命名から。
- **用語の取りうる値**も回収する（3分類）:
  - **Enum（列挙可能）**: 固定値集合（`validateFixedValues` の許可値・区分・結果コード等）→ **全値を列挙**（定数を解決）。
  - **config 駆動（開いた集合）**: 値が設定・外部から来る（prefix マッチ・マスタ参照等）→ **「設定が source」と明記**しコードからは列挙不能と記す。
  - **値域が広い**: 形式＋長さで規定（ID・電話番号・メアド等）→ **代表例を提示**（形式が分かる例値）。

### Phase 7（任意）— 形式モデル化

**順序・状態・多重度の不変条件**（例: 「エイリアスは1件以下」「繰越状態の遷移」「ペアの整合」）があれば Alloy で
`assert` 化し有界探索する（`alloy-spec-model-generator` スキル / `check-domain-model.sh`）。単純な値制約は形式化しない
（test-selection-roi の model-code gap 参照——モデル化は順序/並行/複雑状態機械にだけ払う）。

### Phase 8（任意）— 探索的テストの要否

順序依存・状態を持つクラスタなら **stateful PBT**（操作列を参照モデルと実装に適用し毎ステップ一致検証）を検討。
判断は `docs/test-selection-roi.md` の Q1-Q4。値の入力空間の穴は通常の PBT で足りる。

## 限界とスケール

- 「どこまで文書化できるか」は**対象の選び方に強く依存**。単一クラスタはメカニクス止まり。実ドメインは call graph を
  辿って初めて出る。**境界（外部 IF・caller）に近づくほど hotspot 密度が上がる**（値の意味・意図判断が増える）。
- 摩擦: mutation の隔離実行は依存解決が要る（レポータの推移依存等で躓きやすい）。ローカル不安定なら CI を権威ゲートに
  （gatecrate-setup Phase 7 と同じ方針）。

## Phase 9（任意）— 収束サブループを TAKT で自動化

Phase 4 の「characterize→mutate→survivor 分類→reflect→再 mutate」は終了条件が機械判定（strength=100% / 残り等価）なので
[TAKT](https://github.com/nrslib/takt) で統率できる（`gatecrate-setup` Phase 9 と同型）。persona＝本スキルが「survivor→
テスト追加 / 意図vs欠陥」の判断を供給し、command ゲートが mutation を実行して exit code を差し戻す。**TAKT はループ統率のみ・
判断は本スキル**。判断が主の Phase 1-2,5-8 は本スキル（エージェント）が担う。

