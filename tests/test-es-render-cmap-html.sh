#!/bin/sh
# tests/test-es-render-cmap-html.sh — core/scripts/es-render-cmap-html.sh の挙動テスト
#
# 文脈: 複数リポを束ねて ES モデリングすると、複数の AS-IS が同一の TO-BE に収束し、BC別ビューアだけでは
# TO-BE が重複して見える。本レンダラは横断の `.cmap` を源泉として「TO-BE 全体コンテキストマップ1枚」を
# 決定論射影し、各BCノードのクリックでそのBCの ES ビューアへ遷移させる（click 行は es= 属性から機械生成・
# AI が座標も click も手書きしない）。本テストはその射影規則を回帰固定する。
#
# 検証する性質:
#   1. domain= を持つ BC は subgraph（ドメイン群）の中に描かれる
#   2. es= を持つ BC には click 行が生成される（href は es= の値）
#   3. es= の無い BC は click されず「ESモデル未作成」として一覧される（次に作る対象の可視化）
#   4. EXT は外部システムとして ext クラスで描かれる
#   5. REL は関係種別（+連結キー）のラベル付きエッジになる
#   6. kind=core の BC は core クラス（注力の可視化）
#   7. 決定論: 同一入力からは同一出力（座標・時刻・乱数を含まない）
#   8. ファイルが無い -> exit 2
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/es-render-cmap-html.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT

cat > "$D/map.cmap" <<'EOF'
# 横断ハブ fixture
BC bc_order 注文BC | kind=core | domain=受注 | es=order/order-es.html | summary=中核。
BC bc_pay   決済BC | kind=generic | domain=決済 | es=pay/pay-es.html | summary=汎用決済。
BC bc_inv   在庫BC | kind=supporting | summary=ESモデル未作成のBC。
EXT ext_gw  決済ゲートウェイ | summary=外部。
REL bc_order CS bc_pay | key=注文ID | reason=注文確定が決済を起こす。
REL bc_pay   ACL ext_gw | reason=腐敗防止層。
EOF

run_r() { OUT="$(sh "$SCRIPT" "$@" 2>&1)" && RC=0 || RC=$?; }

echo "property 1: domain= groups the BC into a subgraph"
run_r "$D/map.cmap"
[ "$RC" -eq 0 ] && pass "render -> exit 0" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'subgraph .*受注' && pass "subgraph 受注 exists" || fail "no subgraph: $OUT"

echo "property 2: es= generates a click line with its href"
printf '%s\n' "$OUT" | grep -q 'click bc_order "order/order-es.html"' \
  && pass "click line for bc_order" || fail "no click line: $OUT"

echo "property 3: BC without es= is not clickable and is listed as model-missing"
printf '%s\n' "$OUT" | grep -q 'click bc_inv' && fail "bc_inv wrongly clickable" || pass "bc_inv has no click"
printf '%s\n' "$OUT" | grep -q 'ESモデル未作成' && printf '%s\n' "$OUT" | grep -q 'bc_inv\|在庫BC' \
  && pass "bc_inv listed as next-to-model" || fail "missing-model list absent: $OUT"

echo "property 4: EXT is drawn with the ext class"
printf '%s\n' "$OUT" | grep -q 'ext_gw.*:::ext' && pass "ext class applied" || fail "no ext class: $OUT"

echo "property 5: REL becomes a labeled edge (type + key)"
printf '%s\n' "$OUT" | grep -q 'bc_order.*CS.*注文ID.*bc_pay' && pass "CS edge with key" || fail "no CS edge: $OUT"
printf '%s\n' "$OUT" | grep -q 'bc_pay.*ACL.*ext_gw' && pass "ACL edge" || fail "no ACL edge: $OUT"

echo "property 6: kind=core gets the core class"
printf '%s\n' "$OUT" | grep -q 'bc_order.*:::core' && pass "core class applied" || fail "no core class: $OUT"

echo "property 7: deterministic output"
OUT2="$(sh "$SCRIPT" "$D/map.cmap" 2>&1)"
[ "$OUT" = "$OUT2" ] && pass "same input -> identical output" || fail "output differs between runs"

echo "property 8: missing file -> exit 2"
run_r "$D/no-such.cmap"
[ "$RC" -eq 2 ] && pass "missing cmap -> exit 2" || fail "expected 2, got $RC: $OUT"

echo "---- test-es-render-cmap-html: PASS=$PASS FAIL=$FAIL ----"
[ "$FAIL" -eq 0 ]
