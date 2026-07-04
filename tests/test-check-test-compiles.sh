#!/bin/sh
# tests/test-check-test-compiles.sh — core/scripts/check-test-compiles.sh の挙動テスト
#
# 文脈: ignored テストもビルドされるため、pending scaffold が非コンパイルだとビルドが赤になる。
# 本スクリプトはスタックを検出し build-no-run を実行する。検出ロジック（決定論）を --print で、
# 実行/フォールバック/override を run モードで検証する（ツールチェーン非依存）。
#
# 検証する性質:
#   1. Cargo.toml -> rust / `cargo test --no-run`
#   2. go.mod -> go / `go test ... -run=__nomatch__`
#   3. tsconfig.json -> typescript / `tsc --noEmit`
#   4. pyproject.toml -> python / `compileall`
#   5. 認識スタック無し -> exit 0（検査不能の通知・偽失敗しない）
#   6. TEST_COMPILE_CMD override が autodetect より優先し、実際に実行される（false なら非0）
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-test-compiles.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

# mk <marker-file>: a temp consumer git repo with the script vendored and the marker present.
mk() {
  W="$(mktemp -d)"
  git -C "$W" init -q
  mkdir -p "$W/scripts"
  cp "$SCRIPT" "$W/scripts/check-test-compiles.sh"
  [ -n "$1" ] && : > "$W/$1"
  echo "$W"
}
prt() { OUT="$(cd "$1" && sh scripts/check-test-compiles.sh --print 2>&1)"; }
run() { OUT="$(cd "$1" && sh scripts/check-test-compiles.sh 2>&1)" && RC=0 || RC=$?; }

echo "property 1: Cargo.toml -> rust / cargo test --no-run"
W=$(mk Cargo.toml); prt "$W"
printf '%s\n' "$OUT" | grep -q '^stack: rust$' && pass "rust detected" || fail "not rust: $OUT"
printf '%s\n' "$OUT" | grep -q 'cargo test --no-run' && pass "cargo --no-run cmd" || fail "wrong cmd: $OUT"
rm -rf "$W"

echo "property 2: go.mod -> go / go test -run=__nomatch__"
W=$(mk go.mod); prt "$W"
printf '%s\n' "$OUT" | grep -q '^stack: go$' && pass "go detected" || fail "not go: $OUT"
printf '%s\n' "$OUT" | grep -q 'run=__nomatch__' && pass "go no-run cmd" || fail "wrong cmd: $OUT"
rm -rf "$W"

echo "property 3: tsconfig.json -> typescript / tsc --noEmit"
W=$(mk tsconfig.json); prt "$W"
printf '%s\n' "$OUT" | grep -q '^stack: typescript$' && pass "ts detected" || fail "not ts: $OUT"
printf '%s\n' "$OUT" | grep -q 'tsc --noEmit' && pass "tsc noEmit cmd" || fail "wrong cmd: $OUT"
rm -rf "$W"

echo "property 4: pyproject.toml -> python / directory compileall with -x exclude (no file list)"
W=$(mk pyproject.toml); prt "$W"
printf '%s\n' "$OUT" | grep -q '^stack: python$' && pass "python detected" || fail "not python: $OUT"
printf '%s\n' "$OUT" | grep -q 'compileall' && pass "compileall cmd" || fail "wrong cmd: $OUT"
printf '%s\n' "$OUT" | grep -q -- '-x' && pass "directory mode with -x exclude (no shell-parsed paths)" || fail "no -x: $OUT"
rm -rf "$W"

echo "property 5: no recognized stack -> exit 0 (cannot check, no false failure)"
W=$(mk ""); run "$W"
[ "$RC" -eq 0 ] && pass "exit 0 when unknown stack" || fail "expected exit 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'no rust/go/ts/python build detected' && pass "reports cannot-check" || fail "no notice: $OUT"
rm -rf "$W"

echo "property 6: TEST_COMPILE_CMD overrides autodetect and is actually run"
W=$(mk Cargo.toml)   # has Cargo.toml, but override must win
printf 'TEST_COMPILE_CMD="false"\n' > "$W/harness.config.sh"
prt "$W"
printf '%s\n' "$OUT" | grep -q '^stack: config$' && pass "override takes precedence over rust" || fail "override ignored: $OUT"
run "$W"
[ "$RC" -ne 0 ] && pass "override 'false' runs and fails (cmd executed)" || fail "override not executed (rc=$RC): $OUT"
printf 'TEST_COMPILE_CMD="true"\n' > "$W/harness.config.sh"
run "$W"
[ "$RC" -eq 0 ] && pass "override 'true' passes" || fail "expected exit 0, got $RC: $OUT"
rm -rf "$W"

echo ""
echo "check-test-compiles tests: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
