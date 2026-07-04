#!/bin/sh
# tests/test-check-es-deliverables.sh — core/scripts/check-es-deliverables.sh の挙動テスト
#
# 文脈: 「TO-BEを作らずcmapだけ」等の手抜き(成果物欠落)はスキルの自己レビューでは抜ける。完成＝6タブの源泉が
# 揃うこと、で機械判定できる。本テストは「揃えば通し、欠けたものを名指しで reject する」を回帰固定する。
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-es-deliverables.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
run() { OUT="$(sh "$SCRIPT" "$1" 2>&1)" && RC=0 || RC=$?; }

# 完成した一式を作るヘルパ
mkfull() {
  d="$1"
  cat > "$d/x.es" <<'EOF'
N u actor 利用者
N c command 開く
N a aggregate 集約 | invariant=x | evidence=x:1
N e event 開かれた | evidence=x:1
E u issues c
E c handles a
E a emits e
EOF
  cat > "$d/x-tobe.es" <<'EOF'
N u actor 利用者
N c command 開く
N a aggregate 集約 | invariant=x | evidence=x:1
N e event 開かれた | fields=id:数値 | biz=value
E u issues c
E c handles a
E a emits e
EOF
  printf 'BC b A | summary=a\n' > "$d/x.cmap"
  printf '# roadmap\n' > "$d/x-refactoring-roadmap.ja.md"
  printf '# persistence\n' > "$d/x-persistence-design.ja.md"
}

echo "property 1: a complete deliverable set passes (exit 0)"
D="$(mktemp -d)"; mkfull "$D"
run "$D"
[ "$RC" -eq 0 ] && pass "complete set -> 0" || fail "expected 0, got $RC: $OUT"
rm -rf "$D"

echo "property 2: missing TO-BE -> exit 1 and names D2"
D="$(mktemp -d)"; mkfull "$D"; rm "$D/x-tobe.es"
run "$D"
[ "$RC" -eq 1 ] && pass "missing TO-BE -> 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'D2' && pass "names D2 (TO-BE)" || fail "no D2: $OUT"
rm -rf "$D"

echo "property 3: missing context map -> D3"
D="$(mktemp -d)"; mkfull "$D"; rm "$D/x.cmap"
run "$D"
printf '%s\n' "$OUT" | grep -q 'D3' && pass "names D3 (cmap)" || fail "no D3: $OUT"
rm -rf "$D"

echo "property 4: TO-BE without biz= -> D4 (business analysis source missing)"
D="$(mktemp -d)"; mkfull "$D"
sed 's/ | biz=value//' "$D/x-tobe.es" > "$D/x-tobe.es.tmp" && mv "$D/x-tobe.es.tmp" "$D/x-tobe.es"
run "$D"
printf '%s\n' "$OUT" | grep -q 'D4' && pass "names D4 (biz)" || fail "no D4: $OUT"
rm -rf "$D"

echo "property 5: missing analysis report md -> D5"
D="$(mktemp -d)"; mkfull "$D"; rm "$D/x-persistence-design.ja.md"
run "$D"
printf '%s\n' "$OUT" | grep -q 'D5' && pass "names D5 (analysis md)" || fail "no D5: $OUT"
rm -rf "$D"

echo "---- check-es-deliverables: PASS=$PASS FAIL=$FAIL ----"
[ "$FAIL" -eq 0 ]
