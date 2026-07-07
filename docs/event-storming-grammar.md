# イベントストーミング文法ゲート（es-lint / es-render）

本書は、AIエージェントが**イベントストーミングを苦手とする根本原因**と、それを gatecrate の
**機械ゲート**で解いた仕組みを説明する。読者は「なぜ `.es` という形式があり、なぜ AI に座標を
書かせないのか」を理解し、`core/scripts/es-lint.sh` と `core/scripts/es-render.sh` を使えるようになる。

## なぜ機械ゲートが要るのか（因果）

**なぜ問題か**: AIエージェントはイベントストーミングで次を繰り返す——根拠なくイベントを発明する／
「ルール」を「集約」と誤ラベルする（例: "ファイル読込検証" を集約に）／イベントをイベントへ直結する
（event→event）／不確実性を `要レビュー` で平滑化する／drawio で座標を書かされ図が歪む。

**なぜ直らないか**: これらの文法・規律を**プロンプト（判断層）**に注意書きとして置く限り、AIは破る。
実際、手描き図で「集約の誤り」と「イベント連結」が同時に混入した。

**だからどうするか**: 文法を**機械ゲート（スクリプト）**へ剥がす。AIの責務は「型付きノードと型付き
エッジ」を書くことだけにし、「集約か否か」「連結してよいか」「どこに配置するか」の判断を、人間にも
AIにも依存させない。これは survivor-strict mutation が仕様網羅を機械保証するのと同じ原則を、
イベントストーミングへ適用したもの。

## `.es` 形式 — source of truth は座標なしテキスト

図（Mermaid / drawio）は **source of truth ではない**。一次成果物は型付きテキスト `.es` で、図はその
**決定論的な射影**にすぎない。これにより、AIは座標を一切書かず、図の歪みは構造的に発生しない。

```
# nodes
N <id> <type> <ラベル> [| invariant=...] [| evidence=path:line]
# edges
E <from> <relation> <to>
```

- **type**: `actor` `command` `aggregate` `event` `errorevent` `policy` `readmodel` `external` `hotspot`
- **relation**: `issues` `handles` `emits` `triggers` `feeds` `marks`
- **集約には `invariant=` 必須** — 不変条件が言えないなら、それは集約ではなくルール/仕様（型を見直す）。
- **イベントには `evidence=path:line` 必須** — 無ければ仮説として `hotspot` 化し、オーナーに諮る。
- **hotspot** — 未決定論点のマーカー。`marks` で任意に接続し、文法検証の対象外（疑問符として図に残す）。

## 文法（許可されるエッジ）

```
actor    --issues-->   command        policy    --issues-->   command
command  --handles-->  aggregate      aggregate --emits-->    event
aggregate --emits-->   errorevent     external  --emits-->    event
event    --triggers--> policy         event     --feeds-->    readmodel
```

これ以外のエッジは `es-lint` が **reject** する。特にAIが犯しがちな違反:

| 違反 | 意味 | 正しい形 |
|---|---|---|
| `event → event` | イベントがイベントを直接呼ぶ | 間に `policy → command → aggregate` を挟む |
| `command → event` | 集約をスキップして emit | `command → aggregate → event` |
| `aggregate → aggregate` | 集約間の直接連結 | イベント/ポリシー経由にする |
| 不変条件なし `aggregate` | ルールを集約と誤ラベル | `invariant=` を付けるか型を変える |

## es-lint — 文法を機械強制する予防ゲート

```sh
sh core/scripts/es-lint.sh model.es     # 違反があれば名指しして exit 1
```

`# gatecrate-type: prevention`。検出: 文法違反トリプル・不変条件なし集約・1イベントの複数集約emit・
未宣言ノード参照。warn（非ブロック）: 孤児コマンド・証拠リンクなしイベント。挙動テストは
`tests/test-es-lint.sh`（7性質・12アサーション）。

## es-render — 座標なしで Mermaid 生成

```sh
sh core/scripts/es-render.sh model.es > model.mmd   # AIは座標を書かない
```

`.es` を Mermaid flowchart へ決定論変換する**非ゲートツール**。色・形・レイアウトは `classDef` と
Mermaid 自動配置に委ねる。GitHub 上の ```mermaid ブロックでそのまま描画される。画像化は mermaid-cli:

```sh
mmdc -i model.mmd -o model.png -p pptr.json -b white -s 2
#   pptr.json: {"executablePath":"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome","args":["--no-sandbox"]}
```

## パイプライン全体と関連文書

```
harvest(証拠) → classify(CRUD除外) → refute(敵対) → model(.es) → es-lint(文法) → es-render(描画)
```

`es-lint` / `es-render` は**道具**であり、harvest→classify→refute→model の**オーケストレーション
（どう回すか）は消費プロジェクト側のスキルが担う**（gatecrate は汎用ゲートの供給に純化する）。
ESで確定した規則は [`docs/spec-rules.ja.md`](spec-rules.ja.md) のミニ言語 `R-n` へ、テストと mutation は
[`docs/spec-driven-loop.ja.md`](spec-driven-loop.ja.md) のループへ接続する。

## 情報層 — kawasima ドメイン記述ミニ言語の拡張キー

文法（型・エッジ）だけでは「イベントが何を運ぶか／集約が何で構成されるか／ポリシーが何を見て判定するか」が
書けない。[kawasima ドメイン記述ミニ言語](https://scrapbox.io/kawasima/%E3%83%89%E3%83%A1%E3%82%A4%E3%83%B3%E8%A8%98%E8%BF%B0%E3%83%9F%E3%83%8B%E8%A8%80%E8%AA%9E)
の4層（lexicon=名前 / syntax=AND・OR・? / semantics=behaviorの入出力と不変条件 / pragmatics=BC）を
`N` 行の `| key=値` で表す。**用語集と言語の差は semantics=behavior**（同名でも使われ方が定義されて初めて言語）。

| キー | 対象型 | 意味（4層）|
|---|---|---|
| `fields=名:制約; 名?; 名:[a\|b\|c]` | aggregate / event / readmodel | syntax: AND合成・`?`任意・`[..]`OR分岐。**イベントも型付きpayloadを持つ** |
| `states=s1 // 意味\|s2 // 意味` | aggregate | syntax+semantics: OR状態集合（フラグ/コードはこれに昇格）。**各状態に「// ドメイン上の意味」必須**（「受信」だけでは意味不明。R14）|
| `transitions=名:from->to\|fail // 意味` | aggregate | semantics: 状態遷移＋**動詞のドメイン上の意味**（オーソリする＝支払い枠を確保する。R13で必須化）|
| `in=a;b` / `out=X\|Y` / `decide="..."` | command / policy | semantics: behavior（入力→出力OR・判定）|
| `behaviors=名: in -> out // 定義` | policy | semantics: decide内の述語（「期限内」等）の定義。**未定義の述語はNG** |
| `role=` / `note=` / `discuss=` | 任意 | 学習補助: カード固有の役割 / 実装評価 / ホットスポットの論点（何を決めるか）|
| `when=出力` | エッジ `E` | policy→command が**どの出力でつながるか**（`E p issues c \| when=受付`）|
| `biz=revenue\|value\|degrade` | event | 事業インパクト分類: 収益発生 / 価値提供 / UX毀損（`;`で複数可）|
| `measure=…` | event | オブザーバビリティ(何を): 計測指標（成功率/レイテンシ/発生率/件数・額）|
| `capture=…` | event | オブザーバビリティ(どう取得): 計測点・出力ログ/スパン・相関ID（省略時はクラス別の既定を表示）|
| `compute=…` | event | オブザーバビリティ(どう計算): 指標の算出式（rate=count/count、histogram p50/p99 等）|
| `is=kind\|role\|phase\|relator` | 任意node | 存在論カテゴリ: 種(それ自体で存在)/役割(担い手が別に居る)/相(states=が担当)/関係子(当事者を結ぶ実体)。R15で整合検査 |
| `kind-of=<上位ラベル>` / `role-of=<担い手>` / `alias=a,b` | 任意node | is-a(下位は上位の不変条件を引き継ぐ・R16で未解決/循環検査) / 役割の担い手 / 別名(用語集・クロスリンクに合流) |
| `becomes=<TO-BE id>[,id] \| 変化。なぜ: 理由` | AS-IS node | AS-IS→TO-BE 変化の対応づけ。**「なぜ」必須**（R8で検出）。カードに「TO-BEでの変化」＋ジャンプ、逆向きに「AS-ISからの由来」を表示 |

**命名規約**: コマンド=現在形動詞（〜する）/ イベント=過去形（〜した）/ ポリシー=条件・判定 / 集約=名詞 / 値=制約付き。
**マジックナンバー規約**: 数字を裸で残さず「数字=意味」併記（例 `02=契約済`・`0=SM`・固定`CPS11`・`prefix 3000-`）。

## 情報完全性ゲート — `es-lint-info`（prevention）

`es-lint`（文法）の上位層。情報が欠けたモデルを reject し、フラグ/コードの臭いを警告する（`core/scripts/es-lint-info.sh`）。
挙動テスト `tests/test-es-lint-info.sh`（7性質・12アサーション）。

```sh
sh core/scripts/es-lint.sh m.es && sh core/scripts/es-lint-info.sh m.es
```

- **R1** event/errorevent/readmodel は `fields`（payload）必須　**R2** aggregate は `fields` か `states` 必須
- **R3** policy は `in`/`out`/`decide` 必須、command は `in`/`out` 推奨（behavior=semantics）
- **R4**(warn) field に制約（`:型`）推奨　**R5**(warn) フラグ/コード/status 名 → OR状態・状態遷移へ昇格を促す
- **R6**(warn) policy の `in` がどの fields/states にも解決しない（出所未定義）
- **R7**(warn) 複合 `decide`（∧/かつ）なのに `behaviors` で述語未定義（用語が宙に浮く）

未充足の warn は**TAKTで回す収束ループのワークリスト**（WARN→0 に近づける）。

## 学習ビューア — `es-render-html`

`.es`(+任意の `.spec`/`.cmap`) を自己完結インタラクティブHTMLへ決定論射影する（`core/scripts/es-render-html.sh`）。
**AS-IS（コードの流れ）/ TO-BE（隠れた集約を表出）/ コンテキストマップ / 用語集 / ビジネス分析 / 分析レポート** のタブ切替、
ノードクリックで図を強調＋詳細表示（fields/states/behaviorの視覚化・述語定義・役割・論点）、用語のクロスリンク（定義元へ）。
人はブラウザで、AIは `.es`/`.spec` を機械可読なユビキタス言語として読む。詳細は [`es-living-model.ja.md`](es-living-model.ja.md)。
**完成品の見本**: [`templates/es-living-model-sample/`](../templates/es-living-model-sample/) の `sample-es.html`（ドメイン中立の例で6タブを実演）。

**`.spec`（箱の内側）の使い分け**: `.spec` の `in/step/out` は**コマンド/プロセス**の「入力→処理→出力」を書くもの。
**集約は「構造として持つ値」**なので `.es` の `fields=`（同一性キー・属性）/`states=`/`transitions=`/`invariant=` で表す。
集約の構成を `.spec` の `in`（入力）として書かない（集約は入力を受ける手続きでなく、値と不変条件を持つ実体）。

**用語集タブ（射影）**: `.es` の node（label＋type）＋`fields`/`invariant`/`states`/`behaviors`/`role` から、種別ごとの
**ユビキタス言語の用語集を決定論射影**する。手書きの用語集は持たない（モデル更新で常に最新・ドリフトしない）。
**統合方針**: ドメイン知識の源泉は `.es`/`.spec`/`.cmap`（学習サイクルでの更新対象はこれ一本）。用語集・
events/commands/aggregates/policies.md 等の読み物は**この源泉からの射影**として扱い、二重管理しない。

**分析レポートタブ**（任意・`.md` を引数で渡す）: リファクタリング＋ハーネス ロードマップ・永続化設計などの分析
ドキュメント（markdown）を、追加CDN依存なしで**決定論的にHTML射影**して表示（見出し・表・箇条書き・コード・
太字に対応）。設計判断と図を1枚のビューアに同居させ、人のレビュー導線にする。複数 `.md` を渡すと連結表示。

**ビジネス分析タブ**（`biz=`/`measure=`/`capture=`/`compute=` と任意の `.cld` から導出）: イベントを
収益発生/価値提供/UX毀損 に分類し、(1)**オブザーバビリティ表**（指標・取得方法・計算方法。`capture`/`compute`
省略時はクラス別の既定を表示）、(2)**システム思考の因果ループ図**（後述 `.cld`。強化ループRとバランスループB）、
(3)**施策分析**——ESのエッジを遡って収益/価値イベントの**ファネル上流（増やすと↑）**と**漏れ＝UX毀損分岐
（減らすと↑）**を自動抽出し施策レバーを示す。

**因果ループ図 `.cld`**（任意・第4引数）: `V <id> <変数>` / `L <from> <to> <+|->`（＋同方向・－逆方向）/
`LOOP <id> <R|B> <vars> <説明>`。事業ダイナミクス（成長エンジン＝R、過負荷/リカバリ＝B）を表す。ESフロー
（機械的処理順）とは別レイヤ。Mermaid射影＋R/B凡例で「どの変数を動かすと成長するか/何が抑制するか」を読める。

**ビジネス分析フロー（`.cld` は初版で止めず「調整案」まで必ず作る）**: 因果はコードから導けない業務仮説なので、
初版を出して終わりにせず、次の**4観点で調整案 v2 を必ず作成**してからレビューに出す（人/オーナー裁可はその後）:
1. **粒度**: 曖昧な変数を分割・統合（例: 失敗の波及を「対応コスト/改善投資余力」に分解）。
2. **リンク/符号**: 抜けた因果や符号(＋/−)を補正（例: `latency→satis(−)` ＝遅さは失敗を経ずとも満足を直接損なう）。
3. **ループの過不足**: 実感に合う強化R/バランスBを足す（例: コスト圧迫B3・UX劣化離脱B4）。
4. **計測対応**: 各変数を実測指標（`measure=`/SLI）へ紐づけ、施策の効果を検証可能にする。
調整案は「何を・なぜ変えたか」を `.cld` 冒頭コメントに残す。これにより図が「議論の入口」になる。

## コンテキストマップ — `.cmap`

ESから境界づけられたコンテキストを導出し、BC間関係を描く別文法。文法・BC導出法（**アクター＋同一性キー＋語彙**で
判定。同名でも立場で必要情報が違えば別BC）は [`context-map-grammar.ja.md`](context-map-grammar.ja.md) を参照。

## 限界

- `es-lint` が保証するのは**文法**であって**意味的正しさ**ではない。集約境界が業務的に妥当か、
  ホットスポットをどう裁定するかは**人間が決める**（cc-sdd の expert-gated フェーズ）。
- AIが発見できるのは**コードが含意する仕様のみ**。在るべきだがどこにも無い規則（時間軸・有効期限等）は
  不可視。パイプラインはオーナー/ドメインエキスパートを置き換えず土台を固める。
