#!/bin/sh
# tests/test-check-conventional-title.sh — core/scripts/check-conventional-title.sh の挙動テスト
#
# 検証する性質:
#   1. 妥当な Conventional title（引数）-> pass(exit 0)
#   2. 不正な title（引数）-> fail(exit 1)
#   3. stdin 経由でも同じ判定（引数なし）
#   4. scope 付き / breaking(!) の変種を受理する
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-conventional-title.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

arg() { OUT="$(sh "$SCRIPT" "$1" 2>&1)" && RC=0 || RC=$?; }
pipe() { OUT="$(printf '%s' "$1" | sh "$SCRIPT" 2>&1)" && RC=0 || RC=$?; }

echo "property 1: a valid conventional title (arg) passes"
arg "feat: add a thing"
[ "$RC" -eq 0 ] && pass "valid title exit 0" || fail "expected 0, got $RC: $OUT"

echo "property 2: an invalid title (arg) is rejected"
arg "just some words"
[ "$RC" -eq 1 ] && pass "invalid title exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'Invalid Conventional Commits title' && pass "reports the problem" || fail "no message: $OUT"

echo "property 3: stdin path matches the arg path"
pipe "fix: correct a bug"
[ "$RC" -eq 0 ] && pass "valid via stdin exit 0" || fail "expected 0, got $RC: $OUT"
pipe "nope nope"
[ "$RC" -eq 1 ] && pass "invalid via stdin exit 1" || fail "expected 1, got $RC: $OUT"

echo "property 4: scope and breaking-change variants are accepted"
arg "feat(probe): widen coverage"
[ "$RC" -eq 0 ] && pass "scope accepted" || fail "scope rejected: $OUT"
arg "refactor!: drop the old API"
[ "$RC" -eq 0 ] && pass "breaking (!) accepted" || fail "breaking rejected: $OUT"
arg "chore(core/scripts)!: move things"
[ "$RC" -eq 0 ] && pass "scope + breaking accepted" || fail "scope+breaking rejected: $OUT"

echo ""
echo "check-conventional-title tests: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
