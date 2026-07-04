#!/bin/sh
# tests/test-spec-test-mutation-gate.sh — templates/hooks/spec-test-mutation-gate.sh の挙動テスト
#
# Stop hook（mutation の機械的裏打ち）の判定を固定する。とくに #3 の修正——エスカレーション記録を
# `git add -f` で force-stage し、消費者が .kiro/ を gitignore していても CI に伝播する——を回帰として守る。
#
# 検証する性質:
#   1. arm されていない（pending マーカー無し）-> no-op(exit 0)
#   2. arm + ゲート失敗・cap 未満 -> 停止をブロック(exit 2)・pending 残る
#   3. arm + ゲート失敗・cap 到達 -> escalation 記録を書き force-stage し exit 0（.kiro/ が ignored でも staged）
#   4. arm + ゲート成功 -> pending クリア・exit 0
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HOOK="$ROOT/templates/hooks/spec-test-mutation-gate.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

# newrepo <mutation-exit>: throwaway repo with the hook + a run-mutation.sh that exits <mutation-exit>.
newrepo() {
  D="$(mktemp -d)"; git -C "$D" init -q
  git -C "$D" config user.email p@p; git -C "$D" config user.name p
  mkdir -p "$D/.kiro" "$D/scripts" "$D/.claude/hooks"
  printf '.kiro/\n' > "$D/.gitignore"   # consumer ignores .kiro/ — the hard case for #3
  cp "$HOOK" "$D/.claude/hooks/spec-test-mutation-gate.sh"
  printf '#!/bin/sh\necho "[Survived] X"\nexit %s\n' "$1" > "$D/scripts/run-mutation.sh"
}
fire() { OUT="$(cd "$D" && printf '%s' '{"session_id":"s"}' | env "$@" sh .claude/hooks/spec-test-mutation-gate.sh 2>&1)" && RC=0 || RC=$?; }

echo "property 1: not armed -> no-op (exit 0)"
newrepo 1; fire
[ "$RC" -eq 0 ] && pass "no marker -> exit 0" || fail "expected 0, got $RC: $OUT"
rm -rf "$D"

echo "property 2: armed + failing gate, under the cap -> block (exit 2), marker stays"
newrepo 1; touch "$D/.kiro/.gatecrate-mutation-pending"
fire SPEC_TEST_MUTATION_MAX_BLOCKS=3
[ "$RC" -eq 2 ] && pass "under cap -> exit 2" || fail "expected 2, got $RC: $OUT"
[ -f "$D/.kiro/.gatecrate-mutation-pending" ] && pass "pending marker stays (re-prompt)" || fail "pending cleared early"
rm -rf "$D"

echo "property 3: at the cap -> escalation record written AND force-staged (survives .kiro/ ignore)"
newrepo 1; touch "$D/.kiro/.gatecrate-mutation-pending"
fire SPEC_TEST_MUTATION_MAX_BLOCKS=1
[ "$RC" -eq 0 ] && pass "cap -> exit 0 (loop can't hang)" || fail "expected 0, got $RC: $OUT"
[ -f "$D/.kiro/.gatecrate-mutation-escalated" ] && pass "escalation record written" || fail "no escalation record"
( cd "$D" && git diff --cached --name-only | grep -q '\.gatecrate-mutation-escalated' ) \
  && pass "record is force-staged despite .kiro/ being gitignored (reaches CI)" \
  || fail "record NOT staged — would be invisible to CI (the #3 bug)"
[ -f "$D/.kiro/.gatecrate-mutation-pending" ] && fail "pending not cleared at cap" || pass "pending cleared at cap"
rm -rf "$D"

echo "property 4: armed + passing gate -> clears the arm, exit 0"
newrepo 0; touch "$D/.kiro/.gatecrate-mutation-pending"
fire SPEC_TEST_MUTATION_MAX_BLOCKS=3
[ "$RC" -eq 0 ] && pass "clean -> exit 0" || fail "expected 0, got $RC: $OUT"
[ -f "$D/.kiro/.gatecrate-mutation-pending" ] && fail "pending not cleared on pass" || pass "pending cleared on pass"
rm -rf "$D"

echo ""
echo "spec-test-mutation-gate (Stop hook) tests: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
