#!/bin/sh
# tests/test-gate-roi-verdict.sh — core/scripts/gate-roi-verdict.sh の挙動テスト
#
# 文脈（ROADMAP P4 / docs/harness-roi-evaluation.md / decision record §3 step3）: collect-gate-history が
# 出す発火 TSV を、ゲートの型（classify-gate-type）で解釈して axis-1 の verdict を機械化する層。型を見ずに
# 「発火0=無駄」とすると最重要の予防層を消す（反事実の罠）。型別に解釈し、機械判定できない条件（②uniqueness/
# risk-gone/consumed?）は人間に flag し、決して自動削除しない（提案のみ）。
#
# 検証する性質:
#   1. prevention は fires=0 でも keep（反事実の罠回避・removal-candidate にしない）
#   2. detection × fires=0 × 高コスト → removal-candidate（②uniqueness は人間 flag・提案のみ）
#   3. detection × fires=0 × 安価 → keep（removal ①コスト不成立で固定 keep）
#   4. detection × fires>0 → keep（実発火で価値証明）
#   5. advisory → human-judgment（発火 N/A・信号が消費されるか・自動剪定しない）
#   6. not-a-gate 行は skip（ROI verdict の対象外）
#   7. 出力は提案のみ＝「human approves / never auto-removed」を明示
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/gate-roi-verdict.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

# fixture gate dir: classify needs probe as a sibling; gates carry type markers.
# git init so the scripts resolve ROOT to the fixture (toplevel), not the kit repo.
D="$(mktemp -d)"; git -C "$D" init -q; mkdir -p "$D/scripts"
cp "$ROOT/core/scripts/gate-roi-verdict.sh" "$D/scripts/"              # the script under test
cp "$ROOT/core/scripts/classify-gate-type.sh" "$ROOT/core/scripts/probe-gate-liveness.sh" "$D/scripts/"
cp "$ROOT/core/scripts/collect-gate-history.sh" "$D/scripts/"          # a not-a-gate tool
printf '#!/bin/sh\n# gatecrate-type: prevention\nexit 0\n' > "$D/scripts/check-prev.sh"
printf '#!/bin/sh\n# gatecrate-type: detection\nexit 0\n'  > "$D/scripts/check-det-hot.sh"
printf '#!/bin/sh\n# gatecrate-type: detection\nexit 0\n'  > "$D/scripts/check-det-cold-costly.sh"
printf '#!/bin/sh\n# gatecrate-type: detection\nexit 0\n'  > "$D/scripts/check-det-cold-cheap.sh"
printf '#!/bin/sh\n# gatecrate-type: advisory\nexit 0\n'   > "$D/scripts/check-adv.sh"

# fixture firing TSV (collect-gate-history shape): gate runs fires fire_rate total_seconds avg_seconds
TSV="$(printf 'gate\truns\tfires\tfire_rate\ttotal_seconds\tavg_seconds\n'
printf 'check-prev.sh\t30\t0\t0.00\t5\t0.2\n'
printf 'check-det-hot.sh\t30\t8\t0.27\t120\t4.0\n'
printf 'check-det-cold-costly.sh\t30\t0\t0.00\t120\t4.0\n'
printf 'check-det-cold-cheap.sh\t30\t0\t0.00\t3\t0.1\n'
printf 'check-adv.sh\t30\t0\t0.00\t10\t0.3\n'
printf 'collect-gate-history.sh\t30\t0\t0.00\t8\t0.3\n')"

OUT="$(printf '%s\n' "$TSV" | (cd "$D" && GATE_ROI_DIR=scripts ROI_HIGH_COST_SECONDS=60 sh scripts/gate-roi-verdict.sh) 2>&1)" && RC=0 || RC=$?

echo "property 1: a prevention gate with fires=0 is kept (counterfactual trap avoided)"
[ "$RC" -eq 0 ] && pass "exit 0" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -qE '^keep check-prev\.sh' && pass "prevention fires=0 -> keep" || fail "not keep: $OUT"
printf '%s\n' "$OUT" | grep -E '^[a-z-]+ check-prev\.sh' | grep -q 'removal' && fail "prevention wrongly removal" || pass "prevention never removal-candidate"

echo "property 2: detection x fires=0 x high cost -> removal-candidate, with the uniqueness condition left to a human"
printf '%s\n' "$OUT" | grep -qE '^removal-candidate check-det-cold-costly\.sh' && pass "costly cold detection -> removal-candidate" || fail "not removal-candidate: $OUT"
printf '%s\n' "$OUT" | grep -E '^removal-candidate check-det-cold-costly\.sh' | grep -qi 'uniqueness\|human' && pass "flags ② uniqueness to a human" || fail "no human flag: $OUT"

echo "property 3: detection x fires=0 x cheap -> keep (fails removal condition ① cost)"
printf '%s\n' "$OUT" | grep -qE '^keep check-det-cold-cheap\.sh' && pass "cheap cold detection -> keep" || fail "not keep: $OUT"

echo "property 4: detection x fires>0 -> keep (value proven by real firing)"
printf '%s\n' "$OUT" | grep -qE '^keep check-det-hot\.sh' && pass "hot detection -> keep" || fail "not keep: $OUT"

echo "property 5: advisory -> human-judgment (firing N/A, never auto-pruned)"
printf '%s\n' "$OUT" | grep -qE '^human-judgment check-adv\.sh' && pass "advisory -> human-judgment" || fail "not human-judgment: $OUT"

echo "property 6: a not-a-gate tool row is skipped (outside ROI verdict)"
printf '%s\n' "$OUT" | grep -qE '^skip collect-gate-history\.sh' && pass "not-a-gate -> skip" || fail "not skipped: $OUT"

echo "property 7: output is proposals only (human approves; never auto-removed)"
printf '%s\n' "$OUT" | grep -qi 'never auto-removed\|human approves\|提案' && pass "states proposal-only / human approves" || fail "no proposal-only note: $OUT"
rm -rf "$D"

echo ""
echo "gate-roi-verdict tests: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
