#!/bin/sh
# tests/test-check-gate-tests.sh — core/scripts/check-gate-tests.sh の挙動テスト
#
# 検証する性質:
#   1. ゲートに対応テストが在れば pass(exit 0)
#   2. ゲートに対応テストが無ければ fail(exit 1) で名指し
#   3. 命名ゆれ test-<X>.sh（check- を除いた名）も対応テストとして認める
#   4. tests ディレクトリが無ければ skip(exit 0・advisory)
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-gate-tests.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

D="$(mktemp -d)"; git -C "$D" init -q
mkdir -p "$D/scripts" "$D/tests"
cp "$SCRIPT" "$D/scripts/check-gate-tests.sh"
printf '#!/bin/sh\nexit 0\n' > "$D/scripts/check-foo.sh"   # a gate under test
# GATE_TESTS_LIST seam restricts the audit to our fixture gate
run() { OUT="$(cd "$D" && GATE_TESTS_GATE_DIR=scripts GATE_TESTS_LIST="check-foo" sh scripts/check-gate-tests.sh 2>&1)" && RC=0 || RC=$?; }

echo "property 1: gate with a matching test -> pass"
printf '#!/bin/sh\nexit 0\n' > "$D/tests/test-check-foo.sh"
run
[ "$RC" -eq 0 ] && pass "test present exit 0" || fail "expected 0, got $RC: $OUT"

echo "property 2: gate with NO test -> fail and is named"
rm -f "$D/tests/test-check-foo.sh"
run
[ "$RC" -eq 1 ] && pass "no test exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'check-foo' && pass "names the untested gate" || fail "no name: $OUT"

echo "property 3: the check-stripped test name (test-foo.sh) is accepted"
printf '#!/bin/sh\nexit 0\n' > "$D/tests/test-foo.sh"
run
[ "$RC" -eq 0 ] && pass "stripped-name test accepted" || fail "expected 0, got $RC: $OUT"

echo "property 4: no tests directory -> skip (pass)"
rm -rf "$D/tests"
run
[ "$RC" -eq 0 ] && pass "no tests dir -> skip exit 0" || fail "expected 0, got $RC: $OUT"

rm -rf "$D"
echo ""
echo "check-gate-tests tests: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
