#!/bin/sh
# tests/test-check-file-line-limit.sh — core/scripts/check-file-line-limit.sh の挙動テスト
#
# 文脈: このゲートには挙動テストが無く、SCAN_NAMES("*.sh *.md")を未クォートで word-split していたため
# パターンが cwd に対して glob 展開され、find が「ルート直下の実ファイル名」だけを探す＝サブディレクトリの
# ファイルを丸ごと走査漏れする死角があった（set -f で修正）。本テストはその回帰を固定する。
#
# 検証する性質:
#   1. 上限以下のファイルだけ -> pass(exit 0)
#   2. 上限超のファイル -> FAIL(exit 1) で名指し
#   3. **サブディレクトリの上限超ファイルも検出される**（glob 展開バグの回帰テスト）
#   4. 例外リスト記載の上限超ファイルは EXEMPT(pass)
#   5. 複数の name パターン（*.sh と *.md）が両方効く
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-file-line-limit.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

D="$(mktemp -d)"
git -C "$D" init -q
mkdir -p "$D/scripts" "$D/sub/deep"
cp "$SCRIPT" "$D/scripts/check-file-line-limit.sh"
big() { i=0; while [ "$i" -lt "$1" ]; do echo "# line $i"; i=$((i + 1)); done; }
# Root-level files MUST exist so the bug (if present) actually triggers: an unquoted "*.sh"/"*.md"
# glob-expands against the cwd to these root basenames, after which find only looks for THOSE names
# and misses the differently-named subdir files below. With the fix (set -f) the patterns stay literal.
printf '#!/bin/sh\necho ok\n' > "$D/ok.sh"            # small, root -> makes *.sh expand if buggy
printf '# root doc\n' > "$D/root.md"                  # small, root -> makes *.md expand if buggy
big 350 > "$D/sub/deep/over.sh"                       # OVER, subdir, DIFFERENT name (the regression)
big 350 > "$D/sub/deep/over.md"                       # OVER, subdir, DIFFERENT name (.md regression)

# run -> $OUT,$RC ; EXC overrides the exceptions file (empty by default = nothing exempt)
run() { OUT="$(cd "$D" && FILE_LINE_LIMIT=300 FILE_LINE_PATHS=. FILE_LINE_NAMES="*.sh *.md" FILE_LINE_EXCEPTIONS="${1:-/dev/null}" sh scripts/check-file-line-limit.sh 2>&1)" && RC=0 || RC=$?; }

echo "property 1+2+3: a subdir file over the limit is detected (glob-expansion regression)"
run
[ "$RC" -eq 1 ] && pass "over-limit subdir file -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'sub/deep/over.sh' && pass "names the subdir .sh over-limit file" || fail "subdir .sh not flagged (scan blind spot!): $OUT"
printf '%s\n' "$OUT" | grep -q 'sub/deep/over.md' && pass "names the subdir .md over-limit file (multi-pattern)" || fail "subdir .md not flagged: $OUT"

echo "property 4: a file listed in the exceptions file is EXEMPT (pass)"
printf 'sub/deep/over.sh\nsub/deep/over.md\n' > "$D/exc.txt"
run "$D/exc.txt"
[ "$RC" -eq 0 ] && pass "all over-limit files excepted -> exit 0" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'EXEMPT' && pass "reports EXEMPT" || fail "no EXEMPT: $OUT"

echo "property 5: only small files -> pass"
rm -f "$D/sub/deep/over.sh" "$D/sub/deep/over.md"
run
[ "$RC" -eq 0 ] && pass "only small files -> exit 0" || fail "expected 0, got $RC: $OUT"

rm -rf "$D"
echo ""
echo "check-file-line-limit tests: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
