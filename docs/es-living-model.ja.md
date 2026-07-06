# 生きたドメインモデル（ES living model）— gatecrate ループへの組み込み

## このドキュメントは何のためにあるか

**ゴール**: イベントストーミング(ES)モデル（`.es` ＋ `.spec` ＋ HTMLビューア）を、作って終わりにせず
**gatecrate のループの中で育て続ける資産**にし、**人とAIエージェントの両方がドメイン知識の学習に使える**
状態にする。本書はその全体像・構成要素・現状・到達までのロードマップを1枚に整理する（散在防止）。

なぜ「生きた」か: ドメインモデルは一度書くと腐る。gatecrate の原則（規律はプロンプトでなく機械ゲートに置く／
TAKTで収束ループを統率する／証拠駆動）をESモデルにも適用し、変更のたびに健全性を保ち、不足を機械が指摘し、
コード変更に追従させる。Evans「モデルは言語の骨格、言語の変更はモデルの変更」を運用に落とす。

---

## 1. アーキテクチャ — モデルがループのどこに座るか

```
        ┌─────────────── source of truth（機械可読・証拠リンク）───────────────┐
        │  model.es  (型付きノード/エッジ + data:AND/OR/? + behavior:in->out)   │
        │  model.spec(コマンドの入力→処理→出力)                                │
        └──────────────┬───────────────────────────────────────┬─────────────┘
            予防ゲート  │                                        │ 射影(座標を書かない)
        ┌───────────────▼───────────────┐          ┌────────────▼────────────┐
        │ es-lint      文法(型・許可エッジ)│          │ es-render     Mermaid    │
        │ es-lint-info 情報完全性+臭い(R1-7)│          │ es-render-html 学習HTML   │
        └───────────────┬───────────────┘          └────────────┬────────────┘
            育てるループ │ TAKT(WARN→0 / AS-IS→TO-BE)             │ 消費
        ┌───────────────▼───────────────┐          ┌────────────▼────────────┐
        │ legacy-domain-extraction       │          │ 人: HTMLで学習           │
        │  (コード→証拠→.es) + ドリフト検出 │          │ AI: .es/.spec を文脈に    │
        └────────────────────────────────┘          └─────────────────────────┘
```

- **源泉は `.es`/`.spec`**（座標なしテキスト・evidence付き）。図は決定論的射影で、歪まない。
- **2つの予防ゲート**が健全性を機械保証する（下表）。
- **育てるループ**は TAKT で統率（終了条件が機械判定なので自動化可能）。
- **2種類の消費者**：人はHTML、AIは `.es`/`.spec` を構造化ドメイン文脈として読む。

---

## 2. 構成要素と役割

| 要素 | 役割 | 種別 |
|---|---|---|
| `core/scripts/es-lint.sh` | 文法ゲート（型・許可エッジ・集約は不変条件必須・event→event禁止） | prevention・既存 |
| `core/scripts/es-lint-info.sh` | 情報完全性ゲート（R1 イベントpayload / R2 集約fields・states / R3 behavior / R4 制約 / R5 フラグ・コードの臭い / R6 出所未定義 / R7 述語未定義） | prevention・新規 |
| `core/scripts/es-render.sh` | `.es`→Mermaid（GitHub描画用の軽量射影） | tool・既存 |
| `core/scripts/es-render-html.sh` | `.es`(+`.spec`)→自己完結インタラクティブHTML（学習ビューア） | tool・新規 |
| `core/scripts/es-render-cmap-html.sh` | 横断 `.cmap`→全体コンテキストマップのハブHTML（BCクリックで各ES図へ。複数AS-IS→単一TO-BE の重複見えを、横断源泉1つ＋ハブで解消） | tool・新規 |
| `core/scripts/es-coverage.sh` | TO-BE ノードの evidence を集合演算し 実装済/陳腐化/未実装 を導出（TO-BE 達成率・ギャップ一覧・AS-IS `becomes=` 突合） | advisory・新規 |
| `docs/event-storming-grammar.md` | 文法の説明（**新キー未反映=要更新**） | doc |
| 消費側 `*.es` / `*.spec` | 各ドメインのモデル本体（例: `<domain>.es` / `<domain>-tobe.es`） | 成果物 |

### `.es` ミニ言語（kawasima ドメイン記述ミニ言語準拠・4層）

- **lexicon(名前)**: ノードのラベル。命名規約＝コマンド:現在形動詞 / イベント:過去形 / ポリシー:条件判定 / 集約:名詞。
- **syntax(構成)**: `fields=`(AND合成・`?`任意・`[a|b]`OR分岐) / `states=`(OR状態) / `transitions=`(状態遷移)。
- **semantics(意味)**: `behaviors=`(述語定義 in->out // 計算ルール) / `decide=`(判定式) / `invariant=`。**用語集と言語の差はここ**。
- **pragmatics(文脈)**: BC（context-map）。
- **学習補助**: `role=`(カード固有の役割) / `note=`(実装評価・助言)。`when=`(ポリシー→コマンドのガード)。
- **マジックナンバーは「数字=意味」併記**（例 `02=契約済`・`0=SM`・固定`CPS11`）。

### HTMLビューアの学習機能（実装済み）

AS-IS/TO-BEタブ切替・ズーム/パン・幅可変・ノードクリックで図を強調＋中央寄せ・用語クロスリンク（定義元へ
ジャンプ）・data/states/behaviorの視覚化・述語定義・役割/実装助言・ポリシーのwhenガード表示。

### TO-BE 達成の計測（es-coverage・実装済み）

**なぜ**: 「TO-BE にどれだけ近づいたか」を LLM の達成度判断で出すとゲームされ、コミット間で揺れる。
**だから** TO-BE の evidence リンクだけを座標系にし、決定論で導出する:
TO-BE ノードは実装されるまで evidence を持たない → 実装したら evidence= を付ける →
`es-coverage.sh tobe.es [asis.es]` が **implemented**（evidence が実コードに解決）/
**stale**（解決しない=ドリフト。達成率の裏で腐る実装済を隠さない）/ **missing**（未実装ギャップ）に
分類し、達成率と一覧を出す。対象はコードになる種別のみ（actor/external/hotspot は要求しない）。
status を `.es` に書き戻さない（導出値の二重管理禁止）。AS-IS を併せて渡すと `becomes=` の
宙づり（TO-BE に無い id）とどの AS-IS からも来ない新規能力も報告する。

---

### 意味的正しさの4層（実装済み）

文法・evidence 実在・coverage は機械が保証するが、**意味的正しさ（因果の向き・evidence が主張を
「裏付ける」か）はその保証外**——実害: 因果が逆流したモデルが全ゲート green のまま存在した。
意味は直接判定できないので、4層で「意味的誤りが生き残れない構造」を作る:

| 層 | 何を機械化するか | 部品 |
|---|---|---|
| 1. 主張の実行可能化 | decide=/invariant= をマイクロ検証（`test=` 属性）に翻訳させ「存在し・exit 0」を強制（1主張=2反映） | `check-es-assertions.sh`（prevention） |
| 2. 三角測量 | 独立に書かれた2表現の一致（policy の out= ↔ エッジ when=、states= ↔ transitions）を検査 | `es-lint-info.sh` R11/R12（warn） |
| 3. refute 工程の強制 | 判断はゲート化できないが「独立レビューを経たこと・鮮度」は機械化できる——反証記録の model-hash（git blob hash）が現内容と一致しなければ reject | `check-model-refuted.sh`（prevention） |
| 4. レビュアへの probe | 文法を通過する意味違反（evidence差替/decide入替/when入替）を決定論注入し、refute 工程が名指しできるか（ALIVE/DEAD）を測る＝レビュー工程への mutation testing | `probe-semantic-liveness.sh`（tool） |

第4層が第3層の質を担保する（「捕まえないレビュアは壊れていても見えない」＝probe-gate-liveness の
相似形）。定期運用は TAKT ワークフロー `semantic-review-probe`（gatecrate-evaluate skill 同梱・
inject→refute→verify を ALIVE まで統率・DEAD 継続はレビュー手順の改訂として人間へ ABORT）。残余（BC の core/supporting 裁定・意図 vs 欠陥）は機械化せず、記録（discuss=）と鮮度だけを守る。

---

## 3. 現状（done / gap）

**done**: 2ゲート稼働（サンプルTO-BEモデルで ERROR=0）／HTMLビューア（上記機能）／サンプル2モデル
（AS-IS=コードの流れ・TO-BE=隠れた集約を表出）／ミニ言語の主要キー実装。

**gap（ゴールまでの不足）**:
1. **キット衛生**: `es-lint-info.sh`/`es-render-html.sh` の behavior テスト（`tests/test-es-*.sh`）が無い。`es-render-html.sh` に `gatecrate-type` 無し。→ gatecrate自身のゲートに乗らない。
2. **文法ドキュメント未更新**: `event-storming-grammar.md` が新キー（fields/states/behaviors/in/out/decide/role/note/when）と4層・命名規約・臭いを反映していない。
3. **CI未配線**: `.es` 変更時に es-lint/es-lint-info を回す・HTMLを再生成する・evidence の file:line が生きているか（ドリフト）を検査する、が無い。
4. **TAKT未セットアップ**: `.takt` が空。情報完全化(WARN→0)・AS-IS→TO-BE の収束ループが手動。
5. **AI消費の規約**: エージェントがドメイン作業前に該当 `.es`/`.spec` を読む運用規約が未定義。
6. **横展開**: 1ドメインのみ。他BCへの展開が未着手。

---

## 4. ロードマップ（ゴール到達まで）

| Phase | 目的 | 主タスク | 完了条件 |
|---|---|---|---|
| **P1 固める** | キットを gatecrate 市民にする | es-lint-info/es-render-html に behavior テスト追加・type宣言・文法doc更新（300行超なら分割） | 既存hygieneゲート緑・新ゲート型分類済 |
| **P2 CIに載せる** | 変更ごとに健全性保証 | CIで `.es`→es-lint→es-lint-info、HTML再生成、evidenceドリフト検査 | PRで `.es` 変更が自動検査される |
| **P3 育てるループ** | モデルを自走で成長 | 情報完全化(WARN→0)と AS-IS→TO-BE を TAKT 統率（persona=AI/人, gate=es-lint-info）。legacy-domain-extraction→`.es` 接続 | 1ドメインで WARN→0 を TAKT で収束 |
| **P4 学習に使う** | 人＋AIの学習資産化 | 人: HTMLオンボーディング。AI: ドメイン作業前に `.es`/`.spec` を文脈ロードする規約・skill | エージェントが `.es` を読んで作業する |
| **P5 横展開** | 他ドメインへ | 各BCを1`.es`に。context-map と接続 | 主要BCがモデル化される |

**推奨着手順**: P1（土台）→ P2 → P3。P4/P5は P1-3 が整えば乗せやすい。

---

## 5. 人とAIの使い方（ゴール状態）

- **人**: `*-es.html` をブラウザで開き、AS-IS/TO-BEを比較し、用語をクリックして定義・実装助言を学ぶ。
  新メンバーのオンボーディングと設計レビューの共通言語になる。
- **AIエージェント**: ドメイン作業の前に該当 `.es`/`.spec` を読み込み、**ユビキタス言語の骨格**として用いる
  （用語・不変条件・状態遷移・判定述語が機械可読）。作業で得た気付き（新ルール・hotspot）は `.es` に書き戻し、
  ゲートで検証して成長させる。これが「人とAIが同じモデルで学び、同じモデルを育てる」ループ。

## P2 CIレシピ（消費側 — `.es`/`.cmap` 変更ごとに健全性を保証）

消費プロジェクトの CI に以下を入れると、モデルが壊れたまま育つのを止められる。gatecrate 自身の CI は
キット（ゲート＋テスト）を検証し、消費側 CI は**実モデル**にゲートを当てる、という二段構え。

```yaml
# .github/workflows/es-model.yml（抜粋）
- name: ES model gates  # 文法→情報完全性→evidenceドリフト
  run: |
    for m in docs/model/*.es; do
      sh core/scripts/es-lint.sh "$m"            # 文法（必須・ブロック）
      sh core/scripts/es-lint-info.sh "$m"       # 情報完全性 R1-R7（ERRORでブロック・WARNは可視化）
      EVIDENCE_CODE_ROOT=. sh core/scripts/check-es-evidence.sh "$m"  # evidence実在（ドリフト/捏造を弾く）
    done
    for c in docs/model/*.cmap; do sh core/scripts/es-cmap-lint.sh "$c"; done
- name: regenerate living HTML  # 図を常に最新に（成果物として公開してもよい）
  run: sh core/scripts/es-render-html.sh docs/model/x.es docs/model/x-tobe.es docs/model/x.cmap > docs/model/x.html
```

- **evidenceドリフト**: `EVIDENCE_CODE_ROOT` は .es の evidence が指すコード根。1つの .es が複数リポに
  またがるなら、その全リポを含む根（例: 親ディレクトリ）を指す。解決しなければ「ドリフト/捏造」として PR をブロック。
- **HTML再生成**: CIで生成し artifact / Pages へ公開すれば、人は常に最新の図で学べる。
- **日次ドリフトcron（推奨）**: [`templates/workflows/es-evidence-drift.yml`](../templates/workflows/) をコピーすると、
  **cronが毎朝モデルとコードの乖離を検査し、壊れたら issue を起票**（緑復帰で自動クローズ）。実行の置き場を
  ローカルPCからクラウドへ移し、人が起動しなくてもループが回る。gatecrate 自身も同型を dogfood 運用
  （`.github/workflows/es-drift.yml`）。
- WARN（情報完全性 R4-R7・cmap R4）は**TAKTで回す育成ループ**（P3）のワークリストとして残す。

## P3 TAKT育成ループ（情報完全化を自走で収束）

P2 のゲート（exit code）を**権威**に、TAKT がモデルを「情報完全 + evidence ドリフトなし」へ収束させる
育成ループ。判断（何を payload/fields/behaviors に書くか）は `es-analyst` persona が供給し、TAKT はループ統率のみ。

- 構成（`.takt/`）: workflow `es-converge`（`lint → fill` を繰り返し、全ゲート ERROR=0 かつ
  情報完全性 WARN=0 で COMPLETE）/ persona `es-analyst`（証拠駆動・捏造禁止・命名/マジックナンバー規約）/
  instructions `es-lint-check`・`es-fill-gaps`・`es-loop-monitor`。停滞は `loop_monitors` が検出して ABORT し
  「人間/オーナー判断が要る残課題」を出す（無理に正典化しない）。
- 終了条件は**機械判定**（ゲートの exit code）なので自走できる。

```sh
takt workflow doctor es-converge                                   # 定義検証
takt -w es-converge -t "docs/model/x.es (code root: path/to/code)" # 育成ループ実行
#   lint(ゲート実行→不足列挙) → fill(実コードから補う) → … → ERROR=0/WARN=0 で COMPLETE
```

`fill` が埋められない不足は `discuss=`/hotspot として残る＝**人とAIが同じモデルを育て、確定できない論点は
人間に差し戻す**ループ。これで「作って終わり」でなく、コード変更に追従して**生き続けるモデル**になる。

## P4 学習運用の規約（人＋AIが同じモデルで学び、育てる）

ゴールの「学習に活用」を運用規則に落とす。消費プロジェクトは以下を自分の `AGENTS.md`/`CLAUDE.md` に入れる。

**モデルの置き場（規約）**: 1ドメイン1セット。
```
docs/model/<domain>.es          # AS-IS（コードの流れ・evidence=file:line）
docs/model/<domain>-tobe.es     # TO-BE（隠れた集約を表出・あるべき設計）
docs/model/<domain>.spec        # コマンドの入力→処理→出力（任意）
docs/model/<domain>.cmap        # コンテキストマップ（BC・関係）
docs/model/<domain>.html        # CIで再生成する学習ビューア（射影・編集しない）
```

**AIエージェントの規則**:
1. **着手前に読む**: ドメイン X に触れる前に `docs/model/X.es`(+`.cmap`) を読み、ユビキタス言語の骨格
   （用語・不変条件・状態遷移・判定述語・BC境界）を文脈にする。コードから再発見する前にモデルを参照する。
2. **書き戻す**: 作業で得た新ルール・hotspot は `.es` に追記し、ゲート（es-lint / es-lint-info /
   check-es-evidence）で検証。確定できない論点は `discuss=`/hotspot で人間に差し戻す（捏造しない）。
3. **収束は TAKT に委ねてよい**: 情報の埋め残しは `es-converge` ループ（P3）で WARN→0 へ。

**人の規則**: `X.html` を開き、コンテキストマップで全体像→BCの含むES流れ→ノードの定義・実装助言、の順に学ぶ。
新メンバーのオンボーディングと設計レビューの共通言語にする。図は `.es`/`.cmap` の射影なので、議論は源泉(.es)を直す。

## P5 横展開（他ドメインを `.es` 化する）

ツールキットが固まったので、他ドメイン（各BC）へ同じパイプラインを適用する。新ドメイン1本の手順:

```
harvest(証拠) → classify(CRUD除外) → refute → model(.es) → es-lint/es-lint-info/check-es-evidence
            → es-render-html(描画) → cmap(BC導出: アクター+同一性+語彙)
```

- レガシーは `legacy-domain-extraction` skill（characterization→mutation→.es）で AS-IS を起こす。
- 既に1ドメインのスライス（AS-IS/TO-BE/.spec/.cmap）を範例として持つ。これに倣い、
  未モデル化BC（cmapで「ESモデル未作成」と出る箇所）を順に埋める。
- 各ドメインの `.cmap` を統合すれば、組織全体のコンテキストマップへ育つ。

## 参照
- 文法ゲート: `docs/event-storming-grammar.md`（要更新）
- ドメイン抽出: `legacy-domain-extraction` skill
- TAKT: `gatecrate-setup` skill Phase 9
- サンプル: `<model-dir>/<domain>*.es` / `<domain>-es.html`
