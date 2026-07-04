#!/bin/sh
# tests/test-check-es-assertions.sh — core/scripts/check-es-assertions.sh の挙動テスト
#
# 文脈: モデルの意味的主張（decide=/invariant=）は文法ゲートでは検証できない（因果逆流が全ゲート green の
# まま存在した実例）。第1層の対策は「主張を実行可能にする」＝ノードに test= 属性でマイクロ検証スクリプトを
# 添付させ、本ゲートが「存在し・実行して exit 0」を機械強制する（1主張=2反映の一般化）。判定はテストの
# exit code＝機械判定可能なものだけ。本テストはその判定表を回帰固定する。
#
# 検証する性質:
#   1. test= が指すスクリプトが exit 0 -> pass（ピン留め成立）
#   2. test= スクリプトが fail -> reject でノードとスクリプトを名指し（主張と実挙動の不一致）
#   3. test= のファイルが無い -> reject（存在しない検証で主張を飾れない）
#   4. test= が1つも無いモデル -> pass（採用は漸進的・ゼロでも塞がない）
#   5. decide= を持つのに test= が無いノード数を「未ピン主張」として報告（作業キューの可視化・非ブロック）
#   6. モデルファイルが無い -> exit 2
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-es-assertions.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT

printf '#!/bin/sh\nexit 0\n' > "$D/ok.sh"
printf '#!/bin/sh\necho "claim does not hold" >&2\nexit 1\n' > "$D/ng.sh"

run_a() { OUT="$(ES_ASSERT_ROOT="$D" sh "$SCRIPT" "$@" 2>&1)" && RC=0 || RC=$?; }

echo "property 1: passing assertion -> pass"
cat > "$D/m1.es" <<'EOF'
N pol_x policy 判定する | in=a | out=b | decide="aならb" | test=ok.sh | role=r。
EOF
run_a "$D/m1.es"
[ "$RC" -eq 0 ] && pass "exit 0" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'pol_x' && pass "pinned node reported" || fail "node not reported: $OUT"

echo "property 2: failing assertion -> reject, node named"
cat > "$D/m2.es" <<'EOF'
N pol_x policy 判定する | in=a | out=b | decide="aならb" | test=ng.sh | role=r。
EOF
run_a "$D/m2.es"
[ "$RC" -eq 1 ] && pass "failing test -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'pol_x' && printf '%s\n' "$OUT" | grep -q 'ng.sh' \
  && pass "names node and script" || fail "not named: $OUT"

echo "property 3: missing assertion file -> reject"
cat > "$D/m3.es" <<'EOF'
N cmd_y command 実行する | in=a | out=b | test=no-such.sh | role=r。
EOF
run_a "$D/m3.es"
[ "$RC" -eq 1 ] && pass "missing file -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'no-such.sh' && pass "names the missing path" || fail "path not named: $OUT"

echo "property 4: zero test= -> pass (incremental adoption)"
cat > "$D/m4.es" <<'EOF'
N pol_z policy 判定する | in=a | out=b | decide="aならb" | role=r。
EOF
run_a "$D/m4.es"
[ "$RC" -eq 0 ] && pass "no assertions -> exit 0" || fail "expected 0, got $RC: $OUT"

echo "property 5: decide= without test= is counted as an unpinned claim (info)"
printf '%s\n' "$OUT" | grep -q '未ピン' && printf '%s\n' "$OUT" | grep -q '1' \
  && pass "unpinned claim count shown" || fail "no unpinned count: $OUT"

echo "property 6: missing model -> exit 2"
run_a "$D/no-such.es"
[ "$RC" -eq 2 ] && pass "missing model -> exit 2" || fail "expected 2, got $RC: $OUT"

echo "---- test-check-es-assertions: PASS=$PASS FAIL=$FAIL ----"
[ "$FAIL" -eq 0 ]
