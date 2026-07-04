#!/bin/sh
# tests/test-check-model-refuted.sh — core/scripts/check-model-refuted.sh の挙動テスト
#
# 文脈: モデルの意味的正しさ（因果の向き・evidence が主張を裏付けるか）は文法ゲートでは保証されない
# （因果逆流が全ゲート green のまま存在した実例。捕まえたのは敵対的レビュー）。第3層の対策は「判断は
# ゲート化できないが、独立した refute 工程を経たこと・その鮮度はゲート化できる」——反証記録に model-hash
# （git blob hash）を残させ、モデルが変わったのに記録が古ければ reject する（rule-doc-currency と同型）。
#
# 検証する性質:
#   1. 反証記録が存在し model-hash が現在のモデルと一致 -> pass
#   2. 反証記録が無い -> reject（refute 工程を経ていないモデルは出荷させない）
#   3. model-hash がモデルの現内容と不一致 -> reject（レビュー後にモデルが変わった＝鮮度切れ）で両hashを提示
#   4. 記録に model-hash: 行が無い -> reject（何を レビューしたのか特定できない記録は無効）
#   5. 記録の既定パスは <model>.refutation.md（MODEL_REFUTATION_FILE で上書き可）
#   6. モデルファイルが無い -> exit 2
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-model-refuted.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT

printf 'N e1 event 起きた | fields=x:制約 | role=r。\n' > "$D/m.es"
H="$(git hash-object "$D/m.es")"

mkrec() { printf 'model-hash: %s\n\n## 指摘\n- なし\n\n## 反証を試みたが正しかった項目\n- e1 の evidence\n' "$1" > "$2"; }

run_r() { OUT="$(sh "$SCRIPT" "$@" 2>&1)" && RC=0 || RC=$?; }

echo "property 1: record exists + hash matches -> pass"
mkrec "$H" "$D/m.refutation.md"
run_r "$D/m.es"
[ "$RC" -eq 0 ] && pass "fresh refutation -> exit 0" || fail "expected 0, got $RC: $OUT"

echo "property 3: model changed after review -> reject with both hashes"
printf 'N e2 event 増えた | fields=y:制約 | role=r。\n' >> "$D/m.es"
run_r "$D/m.es"
[ "$RC" -eq 1 ] && pass "stale hash -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q "$H" && pass "recorded hash shown" || fail "recorded hash not shown: $OUT"

echo "property 2: no record -> reject"
rm "$D/m.refutation.md"
run_r "$D/m.es"
[ "$RC" -eq 1 ] && pass "missing record -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'refutation' && pass "explains what is missing" || fail "no guidance: $OUT"

echo "property 4: record without model-hash -> reject"
printf '## 指摘\n- なし\n' > "$D/m.refutation.md"
run_r "$D/m.es"
[ "$RC" -eq 1 ] && pass "hash-less record -> exit 1" || fail "expected 1, got $RC: $OUT"

echo "property 5: MODEL_REFUTATION_FILE overrides the default path"
H2="$(git hash-object "$D/m.es")"
mkrec "$H2" "$D/elsewhere.md"
OUT="$(MODEL_REFUTATION_FILE="$D/elsewhere.md" sh "$SCRIPT" "$D/m.es" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 0 ] && pass "override path works" || fail "expected 0, got $RC: $OUT"

echo "property 6: missing model -> exit 2"
run_r "$D/no-such.es"
[ "$RC" -eq 2 ] && pass "missing model -> exit 2" || fail "expected 2, got $RC: $OUT"

echo "---- test-check-model-refuted: PASS=$PASS FAIL=$FAIL ----"
[ "$FAIL" -eq 0 ]
