#!/bin/sh
# tests/test-es-cmap-lint.sh — core/scripts/es-cmap-lint.sh の挙動テスト
#
# 文脈: .cmap(BC/EXT/REL)も座標なしテキストの源泉で、図はその射影。REL先のBC未定義／関係種別の誤り／
# トークン間のスペース抜け（実害: `bc_x| key=` でMermaidエッジに余分な | が出て描画崩壊）が起きる。
# es-cmap-lint がこれを機械強制する。本テストは「未定義参照・スペース抜け・不正関係種別を必ず reject し、
# 正しいマップは通す」を回帰固定する。
#
# 検証する性質:
#   1. 正しい .cmap -> exit 0
#   2. REL先のスペース抜け `b|` -> R1 ERROR(1) で名指し（描画崩壊バグの再発防止）
#   3. 未定義BC参照 -> R1 ERROR(1)
#   4. 不正な関係種別 -> R2 ERROR(1)
#   5. 名前のないBC -> R3 ERROR(1)
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/es-cmap-lint.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
D="$(mktemp -d)"; trap 'rm -rf "$D"' EXIT
run() { OUT="$(sh "$SCRIPT" "$1" 2>&1)" && RC=0 || RC=$?; }

echo "property 1: a valid context map passes (exit 0)"
cat > "$D/ok.cmap" <<'EOF'
BC a Aコンテキスト | summary=容量
BC b Bコンテキスト | summary=決済
REL a CS b | key=ID | reason=AがBに依頼
EOF
run "$D/ok.cmap"
[ "$RC" -eq 0 ] && pass "valid -> 0" || fail "expected 0, got $RC: $OUT"

echo "property 2: glued token 'b|' (missing space) -> R1 ERROR(1)"
cat > "$D/glue.cmap" <<'EOF'
BC a A | summary=x
BC b B | summary=y
REL a CS b| key=ID | reason=z
EOF
run "$D/glue.cmap"
[ "$RC" -eq 1 ] && pass "glued | -> 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'R1' && pass "names R1 for b|" || fail "no R1: $OUT"

echo "property 3: undefined BC reference -> R1 ERROR(1)"
cat > "$D/undef.cmap" <<'EOF'
BC a A | summary=x
REL a CS nope | reason=z
EOF
run "$D/undef.cmap"
[ "$RC" -eq 1 ] && pass "undefined ref -> 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'R1' && pass "names R1" || fail "no R1: $OUT"

echo "property 4: invalid relationship type -> R2 ERROR(1)"
cat > "$D/badrel.cmap" <<'EOF'
BC a A | summary=x
BC b B | summary=y
REL a Wrong b | reason=z
EOF
run "$D/badrel.cmap"
[ "$RC" -eq 1 ] && pass "bad rel type -> 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'R2' && pass "names R2" || fail "no R2: $OUT"

echo "property 5: BC without a name -> R3 ERROR(1)"
printf 'BC c\n' > "$D/noname.cmap"
run "$D/noname.cmap"
[ "$RC" -eq 1 ] && pass "no name -> 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'R3' && pass "names R3" || fail "no R3: $OUT"

echo "---- es-cmap-lint: PASS=$PASS FAIL=$FAIL ----"
[ "$FAIL" -eq 0 ]
