#!/bin/sh
# tests/test-es-coverage.sh — core/scripts/es-coverage.sh の挙動テスト
#
# 文脈: TO-BE `.es` のノードは実装されるまで evidence を持たない（AS-IS は evidence 必須・TO-BE は
# 実装が進むほど evidence が増える）。es-coverage はこの evidence を唯一の対応台帳として、TO-BE 各ノードを
# 実装済(resolve する evidence あり)/陳腐化(evidence が実コードに解決しない)/未実装(evidence なし)に
# 決定論導出し、TO-BE ギャップ一覧と達成率を出す。本テストはその判定表・対象種別・AS-IS becomes= 突合を
# 回帰固定する。
#
# 検証する性質:
#   1. resolve する evidence を持つノード -> implemented（達成率の分子）
#   2. evidence が実コードに解決しない -> stale として名指し（進捗の裏で腐る実装済を隠さない）
#   3. 対象種別なのに evidence なし -> missing（TO-BE ギャップ）として名指し
#   4. actor/external/hotspot は coverage 対象外（コードにならない種別に evidence を要求しない）
#   5. build/quality/es-coverage.tsv に status 列つきで全対象ノードが載る
#   6. 達成率（implemented/対象数）がレポートに出る
#   7. AS-IS の becomes= が TO-BE に無い id を指す -> モデル不整合として名指し
#   8. どの AS-IS の becomes= からも指されない TO-BE ノード -> 新規能力として報告（情報）
#   9. モデルファイルが無い -> exit 2（黙って空レポートを出さない）
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/es-coverage.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT

# 偽コードベース: OrderService.java は5行（:3 は解決する・:99 は行数超過で解決しない）
mkdir -p "$D/code/src"
printf 'l1\nl2\nplaceOrder\nl4\nl5\n' > "$D/code/src/OrderService.java"

# TO-BE フィクスチャ: implemented / stale / missing / 対象外 を1つずつ
cat > "$D/tobe.es" <<'EOF'
# TO-BE fixture
N act_cust  actor    購入者 | role=起点。
N ext_pay   external 決済GW | role=外部。
N hs_x      hotspot  論点 | role=未決。
N cmd_place command  注文を受け付ける | evidence=OrderService.java:3 | role=実装済のコマンド。
N evt_stale event    古い事実 | evidence=OrderService.java:99 | role=行数超過で解決しない。
N cmd_auth  command  与信を依頼する | role=未実装のコマンド。
N agg_pay   aggregate 決済 | evidence=Nowhere.java:1 | role=ファイル不在で解決しない。
EOF

run_cov() {
  OUT="$(EVIDENCE_CODE_ROOT="$D/code" ES_COVERAGE_OUT="$D/out" sh "$SCRIPT" "$@" 2>&1)" && RC=0 || RC=$?
}

echo "property 1: resolving evidence -> implemented"
run_cov "$D/tobe.es"
[ "$RC" -eq 0 ] && pass "advisory -> exit 0" || fail "expected 0, got $RC: $OUT"
grep -q "cmd_place	command	.*	implemented" "$D/out/es-coverage.tsv" \
  && pass "cmd_place is implemented in TSV" || fail "tsv: $(cat "$D/out/es-coverage.tsv" 2>/dev/null)"

echo "property 2: unresolving evidence -> stale, named"
grep -q "evt_stale	event	.*	stale" "$D/out/es-coverage.tsv" && pass "line-overflow -> stale" \
  || fail "evt_stale not stale: $(cat "$D/out/es-coverage.tsv")"
grep -q "agg_pay	aggregate	.*	stale" "$D/out/es-coverage.tsv" && pass "missing file -> stale" \
  || fail "agg_pay not stale"
printf '%s\n' "$OUT" | grep -q 'evt_stale' && pass "report names the stale node" || fail "stale not named: $OUT"

echo "property 3: required kind without evidence -> missing (the TO-BE gap)"
grep -q "cmd_auth	command	.*	missing" "$D/out/es-coverage.tsv" && pass "cmd_auth is missing" \
  || fail "cmd_auth not missing"
printf '%s\n' "$OUT" | grep -q 'cmd_auth' && pass "gap list names cmd_auth" || fail "gap not named: $OUT"

echo "property 4: actor/external/hotspot are not coverage targets"
if grep -qE '^(act_cust|ext_pay|hs_x)	' "$D/out/es-coverage.tsv"; then
  fail "non-code kinds leaked into coverage targets"
else
  pass "actor/external/hotspot excluded"
fi

echo "property 5+6: TSV has all targets; report shows the attainment ratio"
n=$(wc -l < "$D/out/es-coverage.tsv" | tr -d ' ')
[ "$n" -eq 4 ] && pass "4 target nodes in TSV" || fail "expected 4 rows, got $n"
printf '%s\n' "$OUT" | grep -q '1/4' && pass "attainment 1/4 shown" || fail "no ratio: $OUT"

echo "property 7: AS-IS becomes= pointing to a missing TO-BE id -> named as model inconsistency"
cat > "$D/asis.es" <<'EOF'
N cmd_order command 注文処理 | evidence=OrderService.java:3 | becomes=cmd_place,cmd_ghost | 分離。
N agg_svc   aggregate 手続きサービス | evidence=OrderService.java:3 | becomes=agg_pay | 分割。
N act_old   actor 購入者 | becomes=act_cust | 変わらず。
EOF
run_cov "$D/tobe.es" "$D/asis.es"
[ "$RC" -eq 0 ] && pass "with asis -> exit 0" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'cmd_ghost' && pass "dangling becomes target named" || fail "cmd_ghost not named: $OUT"
# becomes の突合先は TO-BE の「全ノード」——coverage 対象外の種別（actor等）への対応を不整合と誤報しない
# （gatecrate 自身のモデル構築ドッグフーディングで発見した実バグの回帰固定）
printf '%s\n' "$OUT" | sed -n '/モデル不整合/,/^$/p' | grep -q 'act_cust' \
  && fail "becomes to a TO-BE actor wrongly flagged as dangling" \
  || pass "becomes to non-target kinds (actor) is NOT flagged"

echo "property 8: TO-BE node no becomes= points to -> reported as new capability"
printf '%s\n' "$OUT" | grep -q 'cmd_auth' && pass "unmapped TO-BE node reported" || fail "cmd_auth not reported: $OUT"

echo "property 9: missing model file -> exit 2"
run_cov "$D/no-such.es"
[ "$RC" -eq 2 ] && pass "missing model -> exit 2" || fail "expected 2, got $RC: $OUT"

echo "---- test-es-coverage: PASS=$PASS FAIL=$FAIL ----"
[ "$FAIL" -eq 0 ]
