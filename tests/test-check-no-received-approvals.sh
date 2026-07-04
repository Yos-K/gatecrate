#!/bin/sh
# tests/test-check-no-received-approvals.sh — core/scripts/check-no-received-approvals.sh の挙動テスト
#
# 文脈: characterization（golden-master）テストは現挙動を <name>.approved.txt に固定する。比較に失敗すると
# <name>.received.txt（実測スナップショット）を書く。received は「まだ人間がレビュー＝承認していない挙動」で、
# これがコミットされると「未承認の挙動を仕様として紛れ込ませた」穴になる（characterization の罠の入口）。本ゲートは
# 「tracked な *.received.* が在れば reject」して、リポに入るのは必ず承認済み approved だけ、を機械強制する。
#
# 検証する性質:
#   1. tracked な *.received.txt が在る -> FAIL(exit 1) で名指し
#   2. *.approved.txt だけ（received 無し）-> pass(exit 0)
#   3. approval が全く無いクリーンなリポ -> pass(exit 0)
#   4. untracked（コミットされていない）received は穴でない -> pass(exit 0)
#   5. 複数の received を全て名指しする
#   6. パターンは RECEIVED_APPROVAL_GLOB で可変（*.received.png のみ対象なら .received.txt は通す）
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-no-received-approvals.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT

# new_repo <name>: 空の git リポを作って path を echo する
new_repo() {
  r="$D/$1"; mkdir -p "$r/src/test/resources/approved"
  git -C "$r" init -q && git -C "$r" config user.email t@t && git -C "$r" config user.name t
  echo "$r"
}
run_in() { OUT="$(cd "$1" && RECEIVED_APPROVAL_GLOB="${2:-}" sh "$SCRIPT" 2>&1)" && RC=0 || RC=$?; }

echo "property 1: a committed *.received.txt is rejected and named"
R="$(new_repo r1)"
echo data > "$R/src/test/resources/approved/Parser.received.txt"
git -C "$R" add -A && git -C "$R" commit -qm init
run_in "$R"
[ "$RC" -eq 1 ] && pass "received committed -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'Parser.received.txt' && pass "names the received file" || fail "not named: $OUT"

echo "property 2: only *.approved.txt (no received) passes"
R="$(new_repo r2)"
echo data > "$R/src/test/resources/approved/Parser.approved.txt"
git -C "$R" add -A && git -C "$R" commit -qm init
run_in "$R"
[ "$RC" -eq 0 ] && pass "approved only -> exit 0" || fail "expected 0, got $RC: $OUT"

echo "property 3: a clean repo with no approvals passes"
R="$(new_repo r3)"
echo hi > "$R/README.md"
git -C "$R" add -A && git -C "$R" commit -qm init
run_in "$R"
[ "$RC" -eq 0 ] && pass "no approvals -> exit 0" || fail "expected 0, got $RC: $OUT"

echo "property 4: an untracked received file is not a hole (pass)"
R="$(new_repo r4)"
echo hi > "$R/README.md"; git -C "$R" add -A && git -C "$R" commit -qm init
echo data > "$R/src/test/resources/approved/Parser.received.txt"   # not git add'ed
run_in "$R"
[ "$RC" -eq 0 ] && pass "untracked received -> exit 0" || fail "expected 0, got $RC: $OUT"

echo "property 5: every received file is named when multiple exist"
R="$(new_repo r5)"
echo a > "$R/src/test/resources/approved/A.received.txt"
echo b > "$R/src/test/resources/approved/B.received.txt"
git -C "$R" add -A && git -C "$R" commit -qm init
run_in "$R"
[ "$RC" -eq 1 ] && pass "multiple received -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'A.received.txt' && printf '%s\n' "$OUT" | grep -q 'B.received.txt' \
  && pass "names both" || fail "not all named: $OUT"

echo "property 6: the pattern is configurable (png-only ignores received.txt)"
R="$(new_repo r6)"
echo data > "$R/src/test/resources/approved/Parser.received.txt"
git -C "$R" add -A && git -C "$R" commit -qm init
run_in "$R" '*.received.png'
[ "$RC" -eq 0 ] && pass "png-only pattern ignores .received.txt -> exit 0" || fail "expected 0, got $RC: $OUT"
# そして .received.png はちゃんと拾う
cp "$R/src/test/resources/approved/Parser.received.txt" "$R/src/test/resources/approved/Img.received.png"
git -C "$R" add -A && git -C "$R" commit -qm png
run_in "$R" '*.received.png'
[ "$RC" -eq 1 ] && pass "png-only pattern catches .received.png -> exit 1" || fail "expected 1, got $RC: $OUT"

echo "---- test-check-no-received-approvals: PASS=$PASS FAIL=$FAIL ----"
[ "$FAIL" -eq 0 ]
