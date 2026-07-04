#!/bin/sh
# tests/test-mutation-scope.sh — core/scripts/mutation-scope.sh の挙動テスト
#
# 文脈（docs/mutation-strategy.md）: ミューテーションを毎PRで全コード回すと分単位で遅い。A+B 戦略
# （PR=変更分だけ・nightly=フル）の「範囲決定」を全アダプタで1度だけ実装する共通エンジン。実際の
# ミューテーションツールには触れず、決定論的なスコープ計算（mode/base/changed）だけを検証する。
#
# 検証する性質:
#   1. MUTATION_SCOPE 未設定 -> mode は "full"（後方互換）
#   2. MUTATION_SCOPE=diff   -> mode は "diff"
#   3. base は MUTATION_DIFF_BASE を尊重する
#   4. diff モードの changed <glob> は base..HEAD で変更されたマッチファイルだけを出す
#   5. diff モードで該当変更が無ければ changed は空（呼び出し側は SKIP すべき）
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/mutation-scope.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

# fixture repo: base commit with a.rs/b.py, then a branch that changes only a.rs
D="$(mktemp -d)"
git -C "$D" init -q
git -C "$D" config user.email t@t; git -C "$D" config user.name t
printf 'fn a(){}\n' > "$D/a.rs"; printf 'def b(): pass\n' > "$D/b.py"
git -C "$D" add -A; git -C "$D" commit -qm base
git -C "$D" branch -q base-ref
printf 'fn a(){ /* changed */ }\n' > "$D/a.rs"        # change only a.rs
git -C "$D" add -A; git -C "$D" commit -qm change

run() { OUT="$(cd "$D" && "$@" sh "$SCRIPT" "$2" "$3" 2>&1)"; }   # not used; explicit calls below

echo "property 1: MUTATION_SCOPE unset -> mode=full (back-compatible)"
OUT="$(cd "$D" && sh "$SCRIPT" mode 2>&1)"
[ "$OUT" = full ] && pass "default mode full" || fail "expected full, got '$OUT'"

echo "property 2: MUTATION_SCOPE=diff -> mode=diff"
OUT="$(cd "$D" && MUTATION_SCOPE=diff sh "$SCRIPT" mode 2>&1)"
[ "$OUT" = diff ] && pass "diff mode" || fail "expected diff, got '$OUT'"

echo "property 3: base honours MUTATION_DIFF_BASE"
OUT="$(cd "$D" && MUTATION_SCOPE=diff MUTATION_DIFF_BASE=base-ref sh "$SCRIPT" base 2>&1)"
[ "$OUT" = base-ref ] && pass "base respected" || fail "expected base-ref, got '$OUT'"

echo "property 4: changed <glob> lists only changed matching files vs base"
OUT="$(cd "$D" && MUTATION_SCOPE=diff MUTATION_DIFF_BASE=base-ref sh "$SCRIPT" changed '*.rs' 2>&1)"
printf '%s\n' "$OUT" | grep -qx 'a.rs' && pass "lists changed a.rs" || fail "a.rs missing: $OUT"
printf '%s\n' "$OUT" | grep -qx 'b.py' && fail "must not list unchanged b.py" || pass "excludes unchanged b.py"

echo "property 5: changed with no matching change -> empty (caller skips)"
OUT="$(cd "$D" && MUTATION_SCOPE=diff MUTATION_DIFF_BASE=base-ref sh "$SCRIPT" changed '*.go' 2>&1)"
[ -z "$OUT" ] && pass "no matching change -> empty" || fail "expected empty, got '$OUT'"
rm -rf "$D"

echo ""
echo "mutation-scope tests: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
