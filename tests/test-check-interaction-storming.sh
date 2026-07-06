#!/bin/sh
# tests/test-check-interaction-storming.sh — core/scripts/check-interaction-storming.sh の挙動テスト
#
# 文脈: 「ダイアログに閉じる手段がない」等、操作の流れが完結しない欠陥を、UI探索でなく**蒸留された状態表の
# 整合性**で機械検出する（探索はゲートにしない）。本テストは「揃った表は通し、escape欠落・available外コマンド・
# evidence不在を行番号つきで reject する」を回帰固定する（consumer実証: localmd-reader）。
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-interaction-storming.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
D="$(mktemp -d)"; trap 'rm -rf "$D"' EXIT
run() { OUT="$(sh "$SCRIPT" "$1" 2>&1)" && RC=0 || RC=$?; }

# evidence 用の実在ファイル
touch "$D/Main.java" "$D/session.md"
HDR="# flow_id|state_id|event|available_commands|completion_command|escape_command|recovery_command|evidence"

echo "property 1: a complete flow table passes (exit 0)"
cat > "$D/ok.psv" <<EOF
$HDR
recent|dialog|Dialog shown|open,close,clear|open|close|clear|$D/Main.java,$D/session.md
EOF
run "$D/ok.psv"
[ "$RC" -eq 0 ] && pass "complete table -> 0" || fail "expected 0, got $RC: $OUT"

echo "property 2: missing escape (dash) -> exit 1, named with line number"
cat > "$D/noesc.psv" <<EOF
$HDR
recent|dialog|Dialog shown|open,clear|open|-|clear|$D/Main.java
EOF
run "$D/noesc.psv"
[ "$RC" -eq 1 ] && pass "missing escape -> 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'line 2' && pass "reports the line number" || fail "no line number: $OUT"
printf '%s\n' "$OUT" | grep -q 'escape' && pass "names the missing field" || fail "field not named: $OUT"

echo "property 3: completion command not in available_commands -> exit 1"
cat > "$D/notavail.psv" <<EOF
$HDR
recent|dialog|Dialog shown|close,clear|open|close|clear|$D/Main.java
EOF
run "$D/notavail.psv"
[ "$RC" -eq 1 ] && pass "unavailable command -> 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'available_commands' && pass "explains availability" || fail "no availability msg: $OUT"

echo "property 4: nonexistent evidence path -> exit 1"
cat > "$D/noev.psv" <<EOF
$HDR
recent|dialog|Dialog shown|open,close,clear|open|close|clear|$D/Nope.java
EOF
run "$D/noev.psv"
[ "$RC" -eq 1 ] && pass "missing evidence -> 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'Nope.java' && pass "names the missing path" || fail "path not named: $OUT"

echo "property 5: comments/header are skipped; unspecified spec fails clearly"
OUT="$(INTERACTION_FLOWS= sh "$SCRIPT" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 2 ] && pass "no spec -> exit 2 (usage error)" || fail "expected 2, got $RC: $OUT"

echo "---- check-interaction-storming: PASS=$PASS FAIL=$FAIL ----"
[ "$FAIL" -eq 0 ]
