#!/bin/sh
# tests/test-check-interaction-command-traceability.sh —
#   core/scripts/check-interaction-command-traceability.sh の挙動テスト
#
# 文脈（issue #27, consumer実証: localmd-reader PR #18）: ADR と構造テストが在っても、相互作用モデルに
# コマンドが無く挙動テストも無ければ「緑のモデルが実装を守らない」。契約台帳（PSV）の各行について
# state+command → モデル遷移 → 実装 path+locator → 挙動テスト path+locator の連鎖を検査する。
#
# 検証する性質:
#   1. 完全な連鎖を持つ契約 -> pass(exit 0)・env 設定面（INTERACTION_*）でも同判定
#   2. 契約に対応するモデル遷移が無い -> fail
#   3. 実装ファイル欠落／実装 locator ドリフト -> fail
#   4. テストファイル欠落／テスト locator ドリフト -> fail
#   5. 契約の重複（同一 state|command）-> fail
#   6. 実装マーカー "interaction-command: X" が契約に無い -> fail
#   7. 空欄("-")・列過多 -> fail／コメント・ヘッダ行はスキップ
#   8. spec ファイル・source root の欠落 -> setup fail(exit 2)・黙って skip しない
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-interaction-command-traceability.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT HUP INT TERM
mkdir -p "$W/src" "$W/tests"

# 基本フィクスチャ: 遷移表・実装・挙動テスト
printf '%s\n' \
  '# from_state|command|to_state|event' \
  'menu-open|scroll_menu|menu-open|Menu scrolled' \
  'menu-open|close_menu|menu-closed|Menu closed' > "$W/transitions.psv"
printf '%s\n' \
  '// interaction-command: scroll_menu' \
  'void scrollMenu() {}' > "$W/src/Menu.java"
printf '%s\n' \
  'void verticalSwipeReachesLowerMenuActions() {}' > "$W/tests/MenuTest.java"

# mkcontracts <file> <rows...> — ヘッダ付き契約台帳を書く
mkcontracts() {
  f="$1"; shift
  { echo '# state_id|command|implementation|implementation_locator|test|test_locator'
    for row in "$@"; do echo "$row"; done; } > "$f"
}
VALID_ROW="menu-open|scroll_menu|src/Menu.java|scrollMenu|tests/MenuTest.java|verticalSwipeReachesLowerMenuActions"
run() { OUT="$(cd "$W" && sh "$SCRIPT" "$@" 2>&1)" && RC=0 || RC=$?; }

echo "property 1: a contract with a full chain passes (args and env config)"
mkcontracts "$W/c.psv" "$VALID_ROW"
run c.psv transitions.psv src
[ "$RC" -eq 0 ] && pass "valid chain exit 0 (args)" || fail "expected 0, got $RC: $OUT"
OUT="$(cd "$W" && INTERACTION_CONTRACTS=c.psv INTERACTION_TRANSITIONS=transitions.psv \
  INTERACTION_SOURCE_ROOT=src sh "$SCRIPT" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 0 ] && pass "valid chain exit 0 (env config)" || fail "expected 0, got $RC: $OUT"

echo "property 2: a contracted command with no modeled transition fails"
mkcontracts "$W/c.psv" "menu-open|ghost_command|src/Menu.java|scrollMenu|tests/MenuTest.java|verticalSwipeReachesLowerMenuActions"
run c.psv transitions.psv src
[ "$RC" -eq 1 ] && pass "no transition exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'no modeled transition' && pass "names the gap" || fail "no message: $OUT"

echo "property 3: missing implementation file / drifted implementation locator fail"
mkcontracts "$W/c.psv" "menu-open|scroll_menu|src/Ghost.java|scrollMenu|tests/MenuTest.java|verticalSwipeReachesLowerMenuActions"
run c.psv transitions.psv src
[ "$RC" -eq 1 ] && pass "missing impl file exit 1" || fail "expected 1, got $RC: $OUT"
mkcontracts "$W/c.psv" "menu-open|scroll_menu|src/Menu.java|driftedLocator|tests/MenuTest.java|verticalSwipeReachesLowerMenuActions"
run c.psv transitions.psv src
[ "$RC" -eq 1 ] && pass "drifted impl locator exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'implementation locator is absent' && pass "reports the locator" || fail "no locator msg: $OUT"

echo "property 4: missing behavior-test file / drifted test locator fail"
mkcontracts "$W/c.psv" "menu-open|scroll_menu|src/Menu.java|scrollMenu|tests/Ghost.java|verticalSwipeReachesLowerMenuActions"
run c.psv transitions.psv src
[ "$RC" -eq 1 ] && pass "missing test file exit 1" || fail "expected 1, got $RC: $OUT"
mkcontracts "$W/c.psv" "menu-open|scroll_menu|src/Menu.java|scrollMenu|tests/MenuTest.java|driftedTestName"
run c.psv transitions.psv src
[ "$RC" -eq 1 ] && pass "drifted test locator exit 1" || fail "expected 1, got $RC: $OUT"

echo "property 5: a duplicated state|command contract fails"
mkcontracts "$W/c.psv" "$VALID_ROW" "$VALID_ROW"
run c.psv transitions.psv src
[ "$RC" -eq 1 ] && pass "duplicate exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'duplicate' && pass "reports duplicate" || fail "no duplicate msg: $OUT"

echo "property 6: an implementation marker without a contract fails"
mkcontracts "$W/c.psv" "$VALID_ROW"
printf '%s\n' '// interaction-command: unregistered_command' >> "$W/src/Menu.java"
run c.psv transitions.psv src
[ "$RC" -eq 1 ] && pass "unregistered marker exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'unregistered_command' && pass "names the marker" || fail "no marker name: $OUT"
printf '%s\n' \
  '// interaction-command: scroll_menu' \
  'void scrollMenu() {}' > "$W/src/Menu.java"   # 復元

echo "property 7: empty field / too many columns fail; comments and header are skipped"
mkcontracts "$W/c.psv" "menu-open|scroll_menu|-|scrollMenu|tests/MenuTest.java|verticalSwipeReachesLowerMenuActions"
run c.psv transitions.psv src
[ "$RC" -eq 1 ] && pass "empty(-) field exit 1" || fail "expected 1, got $RC: $OUT"
mkcontracts "$W/c.psv" "$VALID_ROW|extra"
run c.psv transitions.psv src
[ "$RC" -eq 1 ] && pass "too many columns exit 1" || fail "expected 1, got $RC: $OUT"
{ echo '# comment'; echo ''; echo 'state_id|command|implementation|implementation_locator|test|test_locator'
  echo "$VALID_ROW"; } > "$W/c.psv"
run c.psv transitions.psv src
[ "$RC" -eq 0 ] && pass "comment/blank/header skipped" || fail "expected 0, got $RC: $OUT"

echo "property 8: missing specs or source root fail explicitly (exit 2)"
run nope.psv transitions.psv src
[ "$RC" -eq 2 ] && pass "missing contracts exit 2" || fail "expected 2, got $RC: $OUT"
mkcontracts "$W/c.psv" "$VALID_ROW"
run c.psv nope.psv src
[ "$RC" -eq 2 ] && pass "missing transitions exit 2" || fail "expected 2, got $RC: $OUT"
run c.psv transitions.psv no-such-dir
[ "$RC" -eq 2 ] && pass "missing source root exit 2" || fail "expected 2, got $RC: $OUT"

echo ""
echo "check-interaction-command-traceability tests: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
