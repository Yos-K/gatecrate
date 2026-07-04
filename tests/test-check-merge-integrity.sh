#!/bin/sh
# tests/test-check-merge-integrity.sh — core/scripts/check-merge-integrity.sh の挙動テスト
#
# 文脈（auto-merge レース検知）: PR の最終 head がマージコミットの祖先かを純 git で検証する。実 git で
# シナリオを組み立て、決定論に検証する（ネットワーク・gh 非依存）。
#
# 検証する性質:
#   1. 真のマージ(2親)で head がマージの祖先 -> ok(exit 0)
#   2. 旧 head でマージ（最終 head がマージに含まれない）-> FAIL(exit 1)・漏れコミットを列挙
#   3. squash/rebase(親1) -> SKIP(exit 0・誤検知しない)
#   4. 引数不足 -> exit 2
#   5. 解決不能な SHA -> exit 2（黙って pass しない）
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-merge-integrity.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

# 各テストで使う一時 git リポを初期化（user 設定込み・determ）。
new_repo() {
  W="$(mktemp -d)"
  git -C "$W" init -q
  git -C "$W" config user.email t@t.t
  git -C "$W" config user.name t
  git -C "$W" config commit.gpgsign false
  echo "$W"
}
gc() { git -C "$W" "$@"; }
cmt() { echo "$2" > "$W/$1"; gc add "$1"; gc commit -q -m "$2"; gc rev-parse HEAD; }

echo "property 1: true merge (2 parents), head is ancestor -> ok"
W=$(new_repo)
A=$(cmt a.txt A)
gc checkout -q -b feature
B=$(cmt b.txt B)                       # B = PR head
gc checkout -q master 2>/dev/null || gc checkout -q main
M_INFO=$(gc merge --no-ff -q -m "merge feature" feature; gc rev-parse HEAD)
OUT="$(cd "$W" && sh "$SCRIPT" "$B" "$M_INFO" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 0 ] && pass "exit 0 when head contained" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'ok —' && pass "reports ok" || fail "no ok msg: $OUT"
rm -rf "$W"

echo "property 2: merge made at an OLD head, final head missing -> FAIL exit 1"
W=$(new_repo)
A=$(cmt a.txt A)
gc checkout -q -b feature
B=$(cmt b.txt B)                       # merged head
gc checkout -q master 2>/dev/null || gc checkout -q main
gc merge --no-ff -q -m "merge feature@B" feature
M=$(gc rev-parse HEAD)                 # merge commit at parent B
gc checkout -q feature
C=$(cmt c.txt C)                       # C = final head, pushed AFTER the merge fired
OUT="$(cd "$W" && sh "$SCRIPT" "$C" "$M" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 1 ] && pass "exit 1 on race" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'auto-merge race' && pass "reports race" || fail "no race msg: $OUT"
printf '%s\n' "$OUT" | grep -q ' C$' && pass "lists the missing commit C" || fail "missing commit not listed: $OUT"
rm -rf "$W"

echo "property 3: squash/rebase (single parent) -> SKIP exit 0"
W=$(new_repo)
A=$(cmt a.txt A)
B=$(cmt b.txt B)                       # linear, B has a single parent
OUT="$(cd "$W" && sh "$SCRIPT" "$A" "$B" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 0 ] && pass "exit 0 on single-parent (skip)" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -qi 'skipped' && pass "reports skip" || fail "no skip msg: $OUT"
rm -rf "$W"

echo "property 4: missing args -> exit 2"
W=$(new_repo); A=$(cmt a.txt A)
OUT="$(cd "$W" && sh "$SCRIPT" "$A" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 2 ] && pass "exit 2 on missing arg" || fail "expected 2, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -qi 'usage' && pass "prints usage" || fail "no usage: $OUT"
rm -rf "$W"

echo "property 5: unresolvable SHA -> exit 2 (not a silent pass)"
W=$(new_repo); A=$(cmt a.txt A)
OUT="$(cd "$W" && sh "$SCRIPT" "$A" "0000000000000000000000000000000000000000" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 2 ] && pass "exit 2 on unresolvable sha" || fail "expected 2, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -qi 'not a resolvable commit' && pass "reports unresolvable" || fail "no unresolvable msg: $OUT"
rm -rf "$W"

echo ""
echo "check-merge-integrity tests: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
