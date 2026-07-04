#!/bin/sh
# tests/test-check-posix-portability.sh — core/scripts/check-posix-portability.sh の挙動テスト
#
# 文脈: 出荷スクリプトを POSIX sh に保てば bash/zsh/fish(exec)/dash/Windows Git Bash で同じく動く。
# 本ゲートは (1) 非 #!/bin/sh shebang と (2) shellcheck SC3xxx(bashism) を検出する。
#
# 検証する性質:
#   1. クリーンな #!/bin/sh スクリプト -> pass(exit 0)
#   2. bash shebang(#!/bin/bash) -> fail(exit 1・NON-POSIX shebang)
#   3. bashism([[ ]])を含む #!/bin/sh -> fail(SC3xxx)  ※shellcheck 必要
#   4. POSIX_CHECK_PATHS でスコープを上書きできる
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-posix-portability.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

D="$(mktemp -d)"
# clean POSIX script
printf '#!/bin/sh\necho hello\n' > "$D/clean.sh"
# bash shebang
printf '#!/bin/bash\necho hi\n' > "$D/bashshebang.sh"
# POSIX shebang but a bashism ([[ ]] is undefined in POSIX sh -> SC3010)
printf '#!/bin/sh\nif [[ x = x ]]; then echo y; fi\n' > "$D/bashism.sh"
# #!/bin/sh WITH arguments (non-portable: shebang arg handling differs across platforms)
printf '#!/bin/sh -e\necho hi\n' > "$D/shebangargs.sh"
# predictable PID-suffixed /tmp path (symlink/collision risk -> must use mktemp). The path is built
# via %s so THIS test file does not itself contain the contiguous /tmp+PID literal (which the gate
# would otherwise flag when it scans the test sources). The generated fixture file does contain it.
printf '#!/bin/sh\necho x > %s.$$\n' /tmp/evil > "$D/predtmp.sh"
# a comment that only MENTIONS a PID-suffixed /tmp path must NOT be flagged (comment-line exclusion)
printf '#!/bin/sh\n# never write to %s.$$ — use mktemp\necho ok\n' /tmp/foo > "$D/tmpcomment.sh"

# run <files...> -> $OUT, $RC  (POSIX_CHECK_PATHS scopes the check to the given files)
run() { OUT="$(POSIX_CHECK_PATHS="$*" sh "$SCRIPT" 2>&1)" && RC=0 || RC=$?; }

echo "property 1: a clean #!/bin/sh script passes"
run "$D/clean.sh"
[ "$RC" -eq 0 ] && pass "clean script exit 0" || fail "expected 0, got $RC: $OUT"

echo "property 2: a bash shebang is rejected"
run "$D/bashshebang.sh"
[ "$RC" -eq 1 ] && pass "bash shebang exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'NON-POSIX shebang' && pass "reports non-posix shebang" || fail "no shebang msg: $OUT"

echo "property 3: a bashism ([[ ]]) is rejected (needs shellcheck)"
if command -v shellcheck >/dev/null 2>&1; then
  run "$D/bashism.sh"
  [ "$RC" -eq 1 ] && pass "bashism exit 1" || fail "expected 1, got $RC: $OUT"
  printf '%s\n' "$OUT" | grep -qE 'SC3[0-9]{3}|bashism' && pass "reports the bashism (SC3xxx)" || fail "no SC3xxx: $OUT"
else
  pass "shellcheck absent — skipped bashism check (shebang check still ran)"
fi

echo "property 4: POSIX_CHECK_PATHS scopes the check (clean only -> pass)"
run "$D/clean.sh"
[ "$RC" -eq 0 ] && pass "scoped to clean file passes" || fail "expected 0, got $RC: $OUT"

echo "property 5: a shebang WITH arguments (#!/bin/sh -e) is rejected (exact match only)"
run "$D/shebangargs.sh"
[ "$RC" -eq 1 ] && pass "shebang-with-args exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'NON-POSIX shebang' && pass "rejects shebang arguments" || fail "no shebang msg: $OUT"

echo "property 6: a predictable PID-suffixed /tmp path is rejected (use mktemp)"
run "$D/predtmp.sh"
[ "$RC" -eq 1 ] && pass "predictable /tmp path exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'Predictable temp path' && pass "reports the predictable temp path" || fail "no predictable-temp msg: $OUT"

echo "property 7: a comment merely mentioning a PID-suffixed /tmp path is NOT flagged"
run "$D/tmpcomment.sh"
[ "$RC" -eq 0 ] && pass "comment mention not flagged (exit 0)" || fail "expected 0, got $RC: $OUT"

rm -rf "$D"
echo ""
echo "check-posix-portability tests: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
