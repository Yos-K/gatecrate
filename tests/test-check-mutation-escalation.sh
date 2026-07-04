#!/bin/sh
# tests/test-check-mutation-escalation.sh — core/scripts/check-mutation-escalation.sh の挙動テスト
#
# 文脈: Stop hook が MAX_BLOCKS で force-pass すると .kiro/.gatecrate-mutation-escalated を残す。
# 本ゲート(一次層)はそれを検出して PR を fail させ、生存を消すまで進ませない（多層防御）。
#
# 検証する性質:
#   1. 記録が無い -> pass(exit 0)
#   2. 記録が在る -> fail(exit 1) かつ記録内容を表示
#   3. 記録を消した後 -> 再び pass(exit 0)
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-mutation-escalation.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

D="$(mktemp -d)"
git -C "$D" init -q
mkdir -p "$D/scripts"
cp "$SCRIPT" "$D/scripts/check-mutation-escalation.sh"

run() { OUT="$(cd "$D" && sh scripts/check-mutation-escalation.sh 2>&1)" && RC=0 || RC=$?; }

echo "property 1: no escalation record -> pass"
run
[ "$RC" -eq 0 ] && pass "clean exit 0" || fail "expected 0, got $RC: $OUT"

echo "property 2: an escalation record -> fail and is surfaced"
mkdir -p "$D/.kiro"
printf 'gatecrate mutation escalation\n--- last survivors ---\n[Survived] Foo\n' > "$D/.kiro/.gatecrate-mutation-escalated"
run
[ "$RC" -eq 1 ] && pass "escalation exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'unresolved mutation escalation' && pass "reports the escalation" || fail "no escalation msg: $OUT"
printf '%s\n' "$OUT" | grep -q 'Survived' && pass "surfaces the survivor record" || fail "record not shown: $OUT"

echo "property 3: after deleting the record -> pass again"
rm -f "$D/.kiro/.gatecrate-mutation-escalated"
run
[ "$RC" -eq 0 ] && pass "cleared exit 0" || fail "expected 0, got $RC: $OUT"

rm -rf "$D"
echo ""
echo "check-mutation-escalation tests: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
