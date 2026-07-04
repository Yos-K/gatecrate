# AIエージェントの仕様駆動学習ループ — 使い方

本書は **`harness-spec-test-loop`** の使い方を示す。これは、エージェントがコードのクラスタを探索し、
**コードが示唆するドメインモデルを提案**し、**仕様を文書化**し、**ROI で選んだ手段でテスト**し、
**mutation で十分性を計測**する——仕様担持コードの mutation 生存がゼロになるまで反復するループ。
[`spec-rules.ja.md`](spec-rules.ja.md)（規則ミニ言語）と [`test-selection-roi.ja.md`](test-selection-roi.ja.md)
（リスク形状→手段）と対になる。

```
探索 → モデル提案 → 仕様化 → reflect(ROI技法) → measure(mutation) → 反復
```

| step | persona | 出力 |
|---|---|---|
| explore | coverage-scout | クラスタの構造的事実＋リスク形状 |
| propose-model | domain-modeler | コードが示唆するドメイン概念（仮説／決定） |
| specify | spec-author | ミニ言語の規則 `R-n`＋トレーサビリティ |
| reflect | spec-author | per-規則の ROI 技法＋（コンパイルする）テスト雛形 |
| measure | coverage-deepener | survivor-strict mutation → クリーンまでテスト追加 |

## クイックスタート（コーディングと並行）

feature/refactor で**いま変更したクラスタ**に対し、**同 PR** で回す——仕様 doc とテストがコードと一緒に育つ。
ワークフローは `.claude/skills/gatecrate-evaluate/takt/harness-spec-test-loop.yaml`。消費者側の前提:

- git リポジトリ・`scripts/check-test-compiles.sh` 採用（scaffold-compiles ゲートの土台）；
- `measure` 用の **survivor-strict** mutation ゲート（rust/cargo-mutants は native に strict・floor 型は
  deepen 用に `MUTATION_THRESHOLD=100` 等で strict 化・`harness-coverage-deepen.yaml` 参照）；
- `.takt/config.yaml`: `workflow_command_gates: { custom_scripts: true }`。

対象クラスタを run task で渡して起動。`measure` は変更クラスタにスコープ（mutation ターゲット1つ）して安価に。

## モード — 仮説を規則化する判断者を選ぶ（`SPEC_LOOP_MODE`）

`harness.config.sh` で設定（既定 `expert-gated`）:

```sh
# harness.config.sh
SPEC_LOOP_MODE=autonomous      # バイブコーディング: 別個の人間の意図が無い → エージェントが判断
# SPEC_LOOP_MODE=expert-gated  # ビジネス要件駆動: 人間/オーナーが判断（既定）
```

- **`expert-gated`** — 別個の人間/オーナーが意図を持つ。`propose-model` は仮説で止め、`specify` は規則を
  DRAFT に、`reflect` はテストを skip して人間の分類を待つ。ビジネス要件が仕様を駆動する場合。
- **`autonomous`** — 別個の人間の意図が無い（バイブコーディング）。エージェントが各モデル問題を**機能正しさ/
  良い設計から判断して進める**——規則を canon 化し ACTIVE テストを書く。ビジネスポリシー型の判断（tier/失効/
  猶予期間 等・機能推論では default しか出せないもの）は `DECIDED AUTONOMOUSLY (policy) — chose X because Y;
  an owner may prefer Z` と明示し隠さない。金銭/契約/UX を驚かせうる判断はその項目だけ expert-gated に escalate。
  どちらのモードでも **欠落概念** は surface され、オーナーの学びは保たれる（今動くか後で見直すかの違い）。

実行ごとに run task でモードを上書きもできる。

## cc-sdd（Kiro 流 Spec-Driven Development）との併用

gatecrate は [cc-sdd](https://github.com/gotalab/cc-sdd)（MIT）と **改変も bundle もせず統合** する——
cc-sdd 自身の拡張点（各 `/kiro:*` コマンドが `.kiro/steering/` を全読みする）を使う。

1. **cc-sdd + steering ファイルを設置**（cc-sdd は vanilla のまま・gatecrate は steering だけ足す）。
   インストーラが一括で行う:

   ```sh
   sh <gatecrate>/install.sh --profile <p> --target . --with-cc-sdd
   ```

   これは `npx cc-sdd@latest --claude-skills --lang ja`（`CC_SDD_AGENT` / `CC_SDD_LANG` /
   `CC_SDD_FLAGS` で上書き可）を実行し、その上に steering を重ねる。手動なら以下と等価:

   ```sh
   npx cc-sdd@latest --claude-skills --lang ja          # cc-sdd 本体を導入
   mkdir -p .kiro/steering
   cp <gatecrate>/templates/kiro-steering/gatecrate-spec-test-loop.md .kiro/steering/
   ```

   これで `/kiro:steering` `validate-gap` `spec-design` `spec-impl` `validate-impl` がこれを読み、各フェーズに
   ループが入る（逆行モデル提案／entity-value-policy／ROI 技法+mutation／discovered 仕様 vs `.kiro/specs` の drift 報告）。

2. **モードは仕様の有無に従う**: cc-sdd 仕様あり → `expert-gated`（`.kiro/specs/` が著された意図・drift と欠落概念は
   cc-sdd 承認フローへ提案で還流）。仕様なし（greenfield/legacy）→ `autonomous`（発見仕様が
   `.kiro/specs/<feature>/requirements.md` のドラフトを bootstrap し、人間が cc-sdd ゲートで確定）。

3. **機械的裏打ち — Stop hook**（「緑テスト」だけでは `validate-impl` を終えられないように）。
   `install.sh --with-cc-sdd` が step 1 で同時に入れる（hook ＋ `.claude/settings.json` ＋
   `.gitignore` マーカー）。手動なら:

   ```sh
   mkdir -p .claude/hooks
   cp <gatecrate>/templates/hooks/spec-test-mutation-gate.sh .claude/hooks/
   # templates/hooks/settings-stop-hook.json の hooks.Stop を settings.json にマージ
   echo '.kiro/.gatecrate-mutation-pending' >> .gitignore
   ```

   その後、ゲートが実際に走ることを確認: `sh scripts/run-mutation.sh` が mutation スコアを出すこと
   （版非互換の runner はクラッシュしてゲートが一度も走らない＝必ず実走で確認、想定で済ませない）。

   steering が `validate-impl` 冒頭で gate を arm（`touch .kiro/.gatecrate-mutation-pending`）し、Stop hook が
   survivor-strict mutation を実行、**生存がある間はエージェントの停止をブロック**（exit 2 で survivor をフィード）。
   session 別カウンタで連続ブロックを上限（`SPEC_TEST_MUTATION_MAX_BLOCKS`・既定3）→ 無限ループしない。
   **上限到達時は silent に通すのでなくエスカレーション**: 可視記録 `.kiro/.gatecrate-mutation-escalated`
   （survivor 付き）を残し、一次層の CI ゲート `check-mutation-escalation.sh` が人が生存を消して記録を消すまで
   PR を fail させる。＝バイパスは多層防御（Stop hook=即時層／CI=一次層）で必ず可視化される。詳細は
   `templates/hooks/README.md`。

## 実例（autonomous）

新規カート価格モジュールでループが形成したドメイン知識:

- **DECISION（機能・canon）**: total は負にならない（0 で下げ止め）・空カート=0。
- **DECIDED AUTONOMOUSLY (policy)**: percent+fixed は加算併用・1カート1クーポン・最低注文額なし
  ——*オーナーは排他/stacking/閾値を望むかも*。
- **欠落概念（オーナーへ）**: `Coupon` は有効期間/コード/利用上限の無い裸の値 → `Coupon`/`Promotion` **エンティティ**が
  在るのでは。
- **エージェントが実装した規則**: 「percent 無防備 → 負の percent は total を**増やす**」から、エージェントが
  **R-5「percent は 0..100」**を判断しガードを実装（canon＋ACTIVE テスト）。
- **ROI 技法**: R-1（total ∈ [0, subtotal] の全入力不変条件）→ **PBT**；小空間の規則 → 例示。
- **measure**: clamp `max(0, …)` を除去すると素朴な例示テストは緑のまま（生存）、ROI 選定の PBT が撃墜
  ——緑テストが未検証だった規則をループが機械的に捕捉。

## 設定リファレンス

| 変数（harness.config.sh） | 既定 | 意味 |
|---|---|---|
| `SPEC_LOOP_MODE` | `expert-gated` | `autonomous` \| `expert-gated`（モード参照） |
| `SPEC_TEST_MUTATION_CMD` | `sh scripts/run-mutation.sh` | Stop hook が回す survivor-strict mutation コマンド |
| `SPEC_TEST_MUTATION_MAX_BLOCKS` | `3` | force-through 前の連続ブロック上限 |

## 正直な限界

- エージェントが発見できるのは**コードが含意する仕様のみ**。在るべきだがどこにも無い規則は不可視（mutation でも
  見えない）。ループはオーナー/ドメインエキスパートを**置き換えず土台を固める**。
- steering は **prompt 注入（判断層）**。**機械保証**はゲートスクリプトが担う：survivor-strict mutation（Stop hook）・
  `check-test-compiles`・traceability。概念確定と意図承認は人間（cc-sdd のフェーズゲート）が担う。
