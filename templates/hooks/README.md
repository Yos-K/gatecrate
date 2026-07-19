# gatecrate hooks — spec-test の機械的裏打ち

## adr-review-commit-msg.sh（commit-msg フック）

`check-adr-review.sh --message` への薄い委譲。feat/fix コミットの `ADR-Review:` トレーラ欠落を
**コミット時点**で知らせる（CI の範囲モードが最終防衛線・フックは早期フィードバック層）。
検査ロジックはゲート本体に一本化し、フック側の重複実装ドリフトを避ける。
インストール手順はファイル先頭コメント参照。

cc-sdd 統合（`templates/kiro-steering/gatecrate-spec-test-loop.md`）は steering＝prompt 注入で、
判断層。その**機械保証**を足すのがこの Stop hook。

## spec-test-mutation-gate.sh（Stop hook）

`/kiro:validate-impl` 後に **survivor-strict mutation ゲートを機械実行**し、生存があればエージェントの
停止をブロックしてフィードバックする＝「緑テストだけ」では validate-impl を終えられない。

- **トリガ**: `.kiro/.gatecrate-mutation-pending` が在るときだけ実行（steering が validate-impl 冒頭で
  `touch` して arm する）。無ければ no-op なので無関係な停止では走らない。
- **無限ループ防止＋エスカレーション**: session_id 別カウンタで連続ブロックを上限（既定3）で打ち切る。
  ただし silent に通すのではなく、可視記録 `.kiro/.gatecrate-mutation-escalated`（survivor 付き）を残して停止を許す。
  一次層の CI ゲート `core/scripts/check-mutation-escalation.sh` がその記録を検出し、人が生存を消して記録を
  消すまで PR を fail させる＝即時層（hook）と CI 層の多層防御。`check-mutation-escalation.sh` を CI に配線すること。
- **設定**: `harness.config.sh` の `SPEC_TEST_MUTATION_CMD`（既定 `sh scripts/run-mutation.sh`）/
  `SPEC_TEST_MUTATION_MAX_BLOCKS`（既定3）。

## インストール

1. `cp templates/hooks/spec-test-mutation-gate.sh <consumer>/.claude/hooks/`
2. `settings.json` に `templates/hooks/settings-stop-hook.json` の `hooks.Stop` を追記
   （既存 hooks があればマージ）。
3. `.gitignore` に `.kiro/.gatecrate-mutation-pending` を追加。
4. mutation ツール（mutmut/PITest/cargo-mutants 等）が survivor-strict で動くこと
   （floor 型は `MUTATION_THRESHOLD=100` 等で strict 化・harness-coverage-deepen.yaml 参照）。

## 限界の整理

- steering（prompt）が marker を立てる部分は判断層。だが**立った後のゲートは機械的**——
  hook は exit 2 で停止をブロックするので、エージェントは生存を消すまで終われない。
- 概念確定・意図承認は cc-sdd の人間フェーズ承認が担う（hook は「十分テストされたか」だけを機械化）。
