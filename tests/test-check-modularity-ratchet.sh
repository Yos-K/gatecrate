#!/bin/sh
# tests/test-check-modularity-ratchet.sh — core/scripts/check-modularity-ratchet.sh の挙動テスト
#
# 文脈: レガシーに絶対 floor（RED=0）を入れると初日に必ず落ち、ゲートごと外される（diff-coverage と同じ轍）。
# 本ゲートは既知のバランス違反エッジを modularity-baseline.tsv（コミット済み・レビューで正当化された負債台帳）
# に凍結し、「ベースラインに無い新規の RED エッジ」だけを reject する ratchet。本テストは「新規悪化は名指しで
# 止まる・既知負債は通る・負債が解消されたら台帳の削除を促す」を回帰固定する。
#
# 検証する性質:
#   1. ベースラインに無い RED エッジ -> FAIL(exit 1) でエッジを名指し
#   2. RED エッジが全てベースライン済み -> pass(exit 0)
#   3. RED エッジ0件 -> pass
#   4. ベースライン未作成（ファイル無し）= 空ベースラインとして扱う（greenfield は RED 即 reject）
#   5. --emit-baseline が現在の RED をベースラインへ書き出し、直後のゲートは通る（brownfield 初期化）
#   6. ベースラインの陳腐化エントリ（もう RED でない）-> pass しつつ削除を促す NOTE
#   7. RED 集合ファイルが無い（計測未実行）-> setup error(exit 2)（黙って pass しない）
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-modularity-ratchet.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT

# RED 集合フィクスチャ（measure-modularity.sh の modularity-red.tsv と同形:
#   src \t dst \t imports \t level \t dist \t vol \t load）
printf 'com.ex.order.core\tcom.ex.billing.gw\t3\tintrusive\t4\t12\t192\n' > "$D/red-one.tsv"
: > "$D/red-none.tsv"

# run <red_file> <baseline_file> [args...]
run_g() {
  red="$1"; base="$2"; shift 2
  OUT="$(MODULARITY_RED_FILE="$red" MODULARITY_BASELINE_FILE="$base" sh "$SCRIPT" "$@" 2>&1)" && RC=0 || RC=$?
}

echo "property 1: new RED edge not in baseline -> reject and name it"
: > "$D/base-empty.tsv"
run_g "$D/red-one.tsv" "$D/base-empty.tsv"
[ "$RC" -eq 1 ] && pass "new violation -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'com.ex.order.core' && printf '%s\n' "$OUT" | grep -q 'com.ex.billing.gw' \
  && pass "names the offending edge" || fail "edge not named: $OUT"

echo "property 2: RED edge already in baseline (known debt) -> pass"
printf 'com.ex.order.core\tcom.ex.billing.gw\n' > "$D/base-known.tsv"
run_g "$D/red-one.tsv" "$D/base-known.tsv"
[ "$RC" -eq 0 ] && pass "known debt -> exit 0" || fail "expected 0, got $RC: $OUT"

echo "property 3: no RED edges -> pass"
run_g "$D/red-none.tsv" "$D/base-empty.tsv"
[ "$RC" -eq 0 ] && pass "no violations -> exit 0" || fail "expected 0, got $RC: $OUT"

echo "property 4: missing baseline file behaves as empty (greenfield rejects immediately)"
run_g "$D/red-one.tsv" "$D/no-such-baseline.tsv"
[ "$RC" -eq 1 ] && pass "no baseline + RED -> exit 1" || fail "expected 1, got $RC: $OUT"
run_g "$D/red-none.tsv" "$D/no-such-baseline.tsv"
[ "$RC" -eq 0 ] && pass "no baseline + no RED -> exit 0" || fail "expected 0, got $RC: $OUT"

echo "property 5: --emit-baseline freezes current REDs, then the gate passes (brownfield bootstrap)"
run_g "$D/red-one.tsv" "$D/base-boot.tsv" --emit-baseline
[ "$RC" -eq 0 ] && pass "--emit-baseline -> exit 0" || fail "expected 0, got $RC: $OUT"
grep -q 'com.ex.order.core	com.ex.billing.gw' "$D/base-boot.tsv" \
  && pass "baseline contains the edge key" || fail "baseline missing edge: $(cat "$D/base-boot.tsv" 2>/dev/null)"
run_g "$D/red-one.tsv" "$D/base-boot.tsv"
[ "$RC" -eq 0 ] && pass "gate passes right after bootstrap" || fail "expected 0, got $RC: $OUT"

echo "property 6: stale baseline entry (debt repaid) -> pass with a removal NOTE"
printf 'com.ex.order.core\tcom.ex.billing.gw\ncom.ex.gone\tcom.ex.away\n' > "$D/base-stale.tsv"
run_g "$D/red-one.tsv" "$D/base-stale.tsv"
[ "$RC" -eq 0 ] && pass "stale entry does not block" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'com.ex.gone' && pass "NOTE names the repaid entry for removal" \
  || fail "stale entry not surfaced: $OUT"

echo "property 7: RED set file missing -> setup error, never a silent pass"
run_g "$D/no-such-red.tsv" "$D/base-empty.tsv"
[ "$RC" -eq 2 ] && pass "missing measurement -> exit 2" || fail "expected 2, got $RC: $OUT"

echo "---- test-check-modularity-ratchet: PASS=$PASS FAIL=$FAIL ----"
[ "$FAIL" -eq 0 ]
