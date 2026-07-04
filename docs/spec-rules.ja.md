# テストとモデル検査を駆動する「ルール」を文書化する

テストもモデル検査も、検証している対象は同じ——1つの**ルール**（不変条件 or ポリシー）。ルールが
誰かの頭の中にしか無いと、テストとモデルは乖離し、発見した挙動は再導出され（あるいはバグが仕様として固定され）る。
本書は、**ルールを一度だけ書き下し**、それを単一ソースとしてテストと——リスクが要求すれば——モデル検査の
両方を駆動するための規約。English: [spec-rules.md](./spec-rules.md)（正文書）。

これは [test-selection-roi.ja.md](./test-selection-roi.ja.md) の「ドメイン知識深化ループ」の **specify**
ステップ: 探索→分類(意図/欠陥)→**ルールを仕様化**→テスト+モデルへ反映→コード修正。Broaden
([design/expansion-loop.md](./design/expansion-loop.md)) は*どの技法*かを提案し、本書はその技法が検証する
*ルール*をどう記録するかを定める。

## ルールの置き場所

消費者リポの領域ごとに1ファイル: `docs/spec/<area>.md`。各ルールに安定した ID（`R-<n>`）を付け、
テストとモデル assert の両方が参照できるようにする。

手書きせず出荷テンプレから始める: `templates/spec/`（索引＋`area.md` 雛形・順序/状態規則の Alloy assert 用
`models/example.als.example` 付き）と `rule-doc-lanes.tsv.example`（`templates/` 配下でなくリポルートに
ある。規則とコードのドリフトを防ぐ rule-doc-currency ゲートのレーン定義）。仕様駆動ループを採用する場合、gatecrate-setup スキル（Phase 6.5）が
配線する。「提案→intent/defect 分類→裁可」の richer なワークフロー（DR-ID 記録）は
[proposed-rule-format.md](./proposed-rule-format.md) を参照。`spec-author` TAKT persona
（`templates/takt/personas/`）が specify→reflect を自動化する。

## ミニ言語（ツールに依存せず自分で持つ）

ルールは、言語非依存の小さな記法で1行：

| 形 | 意味 | 例 |
|---|---|---|
| `R-1 invariant "..."` | 常に成り立つべき条件 | `R-1 invariant "active は tabs の要素、または none"` |
| `R-2 policy "..." when <Event>` | イベントの自動的帰結 | `R-2 policy "close は直前のタブを再アクティブ化" when TabClosed` |
| `R-3 error <Name> "..."` | 名前付きの失敗/禁止状態 | `R-3 error DuplicateTab "同じタブIDを二度開けない"` |

説明はコードでなくドメイン語で。テストとモデルが参照するのは ID。

## 1ルール = 2反映

維持するルールは**両層**に反映し、モデルがコードより先行してドリフトしないようにする：

| 反映先 | 層 | 役割 |
|---|---|---|
| 実装**テスト**（例 / PBT / ステートフルPBT） | 実装 | 実コードへの拒否シグナル。CI で毎 PR 発火 |
| モデル**assert**（Alloy / TLA+） | 設計 | 状態空間の全探索:「どの操作順でも R-n を壊さないか」 |

**モデル反映はいつ要るか？** 全ルールにではない。test-selection-roi に従う:**順序/状態・並行**のルールは
モデル assert に値する（全探索が割に合う）／純粋な**入力空間の不変条件**はテストだけでよい（モデルは
model-code gap を足すだけで益が無い）。つまり: 全ルール→テスト／順序・並行ルール→加えてモデル assert。

## トレーサビリティ

ルール→テスト→モデルへ飛べるよう、鎖を読める形で残す：

```
R-1  invariant "active は tabs の要素、または none"
  ├ test:   tabset_active_is_always_a_member   (ステートフルPBT, src/state.rs)
  └ assert: ActiveIsMember                      (Alloy, spec/tabset.als)
```

ルールの隣に記録する（`R-1 → test:… / assert:…`）。反映の無いルールは仕様でなく TODO／ルールIDの無い
テスト・assert は根無し草——IDを与える。

## 意図vs欠陥ゲート（唯一の人間ステップ）

コードの**現在の挙動**から導いたルールは、canonize する前に人間が**意図か欠陥か**を分類せねばならない。
観測されたが誤った挙動にテストを書くと、バグが仕様として固定される（characterization の罠）。だから新発見の
ルールは**候補**（`R-? (draft・意図/欠陥分類待ち)`）として始まり、人間が本ルールへ昇格——または挙動を欠陥として
修正に回す——してから反映を CI に固定する。

**pending の反映は「未マージ」でなく SKIP すること。** 自動検出パス配下の scaffold テストは、CI 配線の有無に
関わらずアダプタの広域コマンド（`cargo test`・`pytest`・`go test ./...`・`vitest`）が走らせる——だから人間ゲート前に
スタブが PR を赤にする／緑スタブが現挙動を仕様として固定する。pending テストは言語の skip（Rust `#[ignore]`・
pytest `@pytest.mark.skip`・Go `t.Skip`・vitest `it.skip`）でルールを引用して scaffold し、承認時に人間が skip を外す。
Alloy assert は手動実行なので元々 CI 外。**さらに scaffold は「コンパイルも通る」こと**——ignored テストもビルドはされる
（`cargo test`/`go test` は skip 前に全テストファイルをコンパイルする）ので、コンパイル不能なスタブは失敗テストと同様に
ビルドを赤化する。本体は最小でコンパイルの通る形に（`todo!()`、またはビルド確認済みのアサーション）。

## ループの中での位置

```
コードを実装
  → Broaden がリスク形状を検出し技法を提案
    → ここで RULE を書く（ミニ言語・ID・人間分類まで draft）
      → 1ルール=2反映: テストを scaffold（順序/並行ならモデル assert も）
        → 人間が意図/欠陥を分類・承認、反映が CI で緑になる
  → コードが育つほどルールが溜まり、テストとモデルが一緒に育つ
```

ルールが単一ソースで、テストとモデルはその2つの影。これが、実装が進むにつれ*両方*が一緒に育つことを可能にする
——テストスイートとモデルが乖離していくのでなく。
