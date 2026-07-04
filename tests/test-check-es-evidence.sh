#!/bin/sh
# tests/test-check-es-evidence.sh — core/scripts/check-es-evidence.sh の挙動テスト
#
# 文脈: 生きたモデルの .es は evidence=path:line でコードに紐づく。コードが動くと参照が腐り(ドリフト)、
# AIは捏造 evidence を書く。本ゲートはファイル参照が実在するかを機械検証する。本テストは「実在する参照は
# 通し、捏造/ドリフトした参照を reject し、拡張子なしの仮説 evidence はスキップする」を回帰固定する。
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-es-evidence.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
D="$(mktemp -d)"; trap 'rm -rf "$D"' EXIT
run() { OUT="$(EVIDENCE_CODE_ROOT="$2" sh "$SCRIPT" "$1" 2>&1)" && RC=0 || RC=$?; }

# 疑似コード根
mkdir -p "$D/code/src"
printf 'class Foo {}\n' > "$D/code/src/Foo.java"

echo "property 1: evidence files that exist -> exit 0"
cat > "$D/ok.es" <<'EOF'
N a aggregate 集約 | invariant=x | evidence=Foo.java:12
N e event 起きた | evidence=Foo.java:30,44
EOF
run "$D/ok.es" "$D/code"
[ "$RC" -eq 0 ] && pass "resolvable evidence -> 0" || fail "expected 0, got $RC: $OUT"

echo "property 2: a fabricated file reference -> exit 1 and is named"
cat > "$D/bad.es" <<'EOF'
N a aggregate 集約 | invariant=x | evidence=Nonexistent.java:9
EOF
run "$D/bad.es" "$D/code"
[ "$RC" -eq 1 ] && pass "drift/fabrication -> 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'Nonexistent.java' && pass "names the missing file" || fail "not named: $OUT"

echo "property 3: extension-less hypothesis evidence is skipped (not failed)"
cat > "$D/hyp.es" <<'EOF'
N e event 仮説 | evidence=設計(TOBE)
N e2 event 別仮説 | evidence=AS-IS:ChargeRequestValidated
EOF
run "$D/hyp.es" "$D/code"
[ "$RC" -eq 0 ] && pass "hypothesis evidence skipped -> 0" || fail "expected 0, got $RC: $OUT"

echo "---- check-es-evidence: PASS=$PASS FAIL=$FAIL ----"
[ "$FAIL" -eq 0 ]
