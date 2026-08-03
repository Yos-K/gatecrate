#!/bin/sh
# tests/test-posix-sh-run-tests.sh — adapters/posix-sh/scripts/run-tests.sh の挙動テスト
#
# 文脈（PR #64 レビュー指摘）: 本スクリプトは「グロブが1件も一致しなければ失敗」という良い不変条件を
# 持つが、それを固定するアサーションが無かった。この不変条件が守る失敗は実在する——このリポでも
# `test-check-release-version-name.sh` が CI のステップ一覧から静かに落ちていた（テストが蒸発しても
# 緑に見える）。専用テストが無いと、その不変条件自体が次の変更で黙って消える。
#
# 検証する性質:
#   1. 全テストが通る -> exit 0・PASS件数を報告
#   2. 1本でも落ちる -> exit 1・落ちたテスト名と全文を出す
#   3. **グロブが0件 -> exit 1**（無言の蒸発を緑にしない・本スクリプトの要）
#   4. テストディレクトリ自体が無い -> exit 1
#   5. SH_TESTS_DIR / SH_TESTS_GLOB で置き場と名前を上書きできる
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/adapters/posix-sh/scripts/run-tests.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

mk() {
  W="$(mktemp -d)"
  git -C "$W" init -q
  mkdir -p "$W/scripts" "$W/tests"
  cp "$SCRIPT" "$W/scripts/run-tests.sh"
  echo "$W"
}
run() { W="$1"; shift; OUT="$(cd "$W" && "$@" sh scripts/run-tests.sh 2>&1)" && RC=0 || RC=$?; }

echo "property 1: all tests passing -> exit 0 and a PASS count"
W="$(mk)"
printf '#!/bin/sh\nexit 0\n' > "$W/tests/test-a.sh"
printf '#!/bin/sh\nexit 0\n' > "$W/tests/test-b.sh"
run "$W"
[ "$RC" -eq 0 ] && pass "all green -> exit 0" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'PASS=2 FAIL=0' && pass "reports the counts" || fail "no counts: $OUT"
rm -rf "$W"

echo "property 2: one failing test -> exit 1, named, with its output"
W="$(mk)"
printf '#!/bin/sh\nexit 0\n' > "$W/tests/test-a.sh"
printf '#!/bin/sh\necho "boom detail"\nexit 1\n' > "$W/tests/test-b.sh"
run "$W"
[ "$RC" -eq 1 ] && pass "a failure -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'FAIL: tests/test-b.sh' && pass "names the failing test" || fail "not named: $OUT"
printf '%s\n' "$OUT" | grep -q 'boom detail' && pass "dumps its output" || fail "output not dumped: $OUT"
rm -rf "$W"

echo "property 3: zero matching tests -> exit 1 [要: 無言の蒸発を緑にしない]"
# テストが1本も無いのは「全部通った」ではない。リネームやディレクトリ移動でテスト群が
# 静かに消えたとき、緑で通してしまうと二度と気づけない。
W="$(mk)"
run "$W"
[ "$RC" -eq 1 ] && pass "empty glob -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'no test matched' && pass "explains a silent zero is not a pass" || fail "no explanation: $OUT"
rm -rf "$W"

echo "property 3b: files that do not match the glob do not count as tests"
W="$(mk)"
printf '#!/bin/sh\nexit 0\n' > "$W/tests/helper.sh"      # test-*.sh ではない
run "$W"
[ "$RC" -eq 1 ] && pass "non-matching files -> still exit 1" || fail "expected 1, got $RC: $OUT"
rm -rf "$W"

echo "property 4: a missing test directory -> exit 1"
W="$(mk)"
rmdir "$W/tests"
run "$W"
[ "$RC" -eq 1 ] && pass "missing dir -> exit 1" || fail "expected 1, got $RC: $OUT"
rm -rf "$W"

echo "property 5: SH_TESTS_DIR / SH_TESTS_GLOB override the location and the name"
W="$(mk)"
mkdir -p "$W/checks"
printf '#!/bin/sh\nexit 0\n' > "$W/checks/spec-a.sh"
run "$W" env SH_TESTS_DIR=checks SH_TESTS_GLOB='spec-*.sh'
[ "$RC" -eq 0 ] && pass "overrides honoured -> exit 0" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'PASS=1' && pass "runs the overridden set" || fail "wrong set: $OUT"
rm -rf "$W"

echo "---- test-posix-sh-run-tests: PASS=$PASS FAIL=$FAIL ----"
[ "$FAIL" -eq 0 ]
