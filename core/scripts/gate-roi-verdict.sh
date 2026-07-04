#!/bin/sh
# [汎用core] ゲート ROI verdict（axis-1・型別解釈）— スタック非依存
#
# WHY (ROADMAP P4 / docs/harness-roi-evaluation.md / docs/probe-scope-and-gate-classification-decision.md §3 step3):
# collect-gate-history が出す発火 TSV（gate/runs/fires/fire_rate/total_seconds/avg_seconds）を、ゲートの型
# （classify-gate-type）で解釈して axis-1（removal）の verdict を機械化する欠けた結節点。型を見ずに「発火0=無駄」
# とすると最重要の予防層を消す（反事実の罠）。型別に解釈し、機械判定できない条件は人間に flag、決して自動削除しない。
#
# 型別ロジック（roi-evaluation.md の removal は ①高コスト ∧ ②zero-uniqueness ∧ ③発火0/risk-gone の論理積）:
#   prevention      発火0 が正常（罠回避）。removal の③は「premise/risk gone」だが機械判定不能（人間）。→ keep。
#   detection 発火>0 実発火で価値証明。→ keep。
#   detection 発火0  ① のみ機械評価可: 高コストなら removal-candidate（②uniqueness は人間 flag・提案のみ）／
#                    安価なら ① 不成立で固定 keep（cheap layer は発火0でも残す）。
#   advisory        ブロックしないので発火 N/A。価値=「信号が消費されるか」＝人間判断。→ human-judgment。
#   not-a-gate      ROI verdict の対象外。→ skip。
#
# できないこと（意図的）: axis-2（保守負荷＝consolidate/downgrade）・②uniqueness・prevention の risk-gone・
# advisory の consumed? は本 script では判定しない（gatecrate-evaluate skill / 人間の領分）。本 script は
# axis-1 の型別 verdict を提案するだけ。**提案のみ・人間が承認**。安全制約（secrets/forbidden-perms）は metric で
# 自動削除しない（roi-evaluation.md）。
#
# Input  : 発火 TSV を stdin で受ける（collect-gate-history の出力をそのまま）。1列目=ゲート script 名。
# Config : GATE_ROI_DIR（ゲートの在処・既定 core/scripts→scripts）・ROI_HIGH_COST_SECONDS（① 高コスト閾値・既定 60）。
# Usage  : collect-gate-history.sh ... | gate-roi-verdict.sh
set -eu

HIGH_COST="${ROI_HIGH_COST_SECONDS:-60}"
ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd))"
GATE_DIR="${GATE_ROI_DIR:-}"
if [ -z "$GATE_DIR" ]; then
  if [ -d "$ROOT/core/scripts" ]; then GATE_DIR="core/scripts"; else GATE_DIR="scripts"; fi
fi
CLASSIFY="$ROOT/$GATE_DIR/classify-gate-type.sh"

# is_num <s>: true if s is a non-empty run of digits.
is_num() { case "${1:-}" in ""|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# gate_type <gate-col>: resolve the gate file and return its classify verdict, or "unresolved".
gate_type() {
  f="$ROOT/$GATE_DIR/$1"
  [ -f "$f" ] || f="$ROOT/$GATE_DIR/$1.sh"
  [ -f "$f" ] || { echo unresolved; return 0; }
  sh "$CLASSIFY" --one "$f" | awk '{print $1}'
}

echo "Gate ROI verdict (axis-1, type-aware). Proposals only — a human approves every removal/consolidation;"
echo "safety gates (secrets / forbidden-permissions) are never auto-removed. Run with collect-gate-history."
echo ""

TAB="$(printf '\t')"
while IFS="$TAB" read -r gate runs fires fire_rate total avg; do
  [ -n "${gate:-}" ] || continue
  [ "$gate" = "gate" ] && continue          # header row
  type="$(gate_type "$gate")"
  case "$type" in
    not-a-gate)  echo "skip $gate — not-a-gate (harness tooling); outside ROI verdict." ;;
    unresolved)  echo "skip $gate — gate file not found in $GATE_DIR; map the CI job name to a gate script for a type-aware verdict." ;;
    prevention)  echo "keep $gate — prevention; fires=${fires:-?} is healthy (zero is normal); value=liveness (probe). Removal needs a human \"guarded-risk-gone\" call, not mechanical." ;;
    advisory)    echo "human-judgment $gate — advisory (non-blocking); firing N/A. Value = is the signal consumed/acted on? Human decides; never auto-pruned." ;;
    detection)
      if is_num "${fires:-}" && [ "$fires" -gt 0 ]; then
        echo "keep $gate — detection; fired ${fires}× over ${runs:-?} runs — proving value."
      elif ! is_num "${total:-}"; then
        echo "keep $gate — detection; 0 fires but CI cost is NA (cannot evaluate removal ①); pinned keep until cost is known."
      elif [ "$total" -ge "$HIGH_COST" ]; then
        echo "removal-candidate $gate — detection; 0 fires / ${runs:-?} runs AND high CI cost (${total}s >= ${HIGH_COST}s). PROPOSAL pending ② zero-uniqueness (a human confirms; not in firing data) — a human removes via PR; never auto-removed."
      else
        echo "keep $gate — detection; 0 fires but cheap (${total}s < ${HIGH_COST}s) — fails removal condition ① (cost); pinned keep (counterfactual-trap guard)."
      fi ;;
    *)           echo "skip $gate — type '$type' not handled by the axis-1 verdict." ;;
  esac
done

echo ""
echo "Note: axis-2 (maintenance load -> consolidate/downgrade), ② uniqueness, prevention risk-gone, and"
echo "advisory 'is it consumed?' are NOT decided here — they are the gatecrate-evaluate skill / human's call."
