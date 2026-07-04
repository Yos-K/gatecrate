#!/bin/sh
# tests/test-measure-modularity.sh — core/scripts/measure-modularity.sh の挙動テスト
#
# 文脈: measure-coupling.sh は strength(import数)×volatility の2次元で Balanced Coupling を縮約実装して
# いた（distance 未実装は docs/code-quality-metrics.md が明記していた既知の欠落）。measure-modularity.sh は
# distance(パッケージ木距離)と strength の質的レベル(contract<model<functional<intrusive、判断層が
# modularity-strength.tsv で分類)を加え、バランス式 BALANCE = (STRENGTH XOR DISTANCE) OR NOT VOLATILITY の
# 違反エッジを RED 判定する。本テストはその判定表とシーム経路を回帰固定する。
#
# 検証する性質:
#   1. 強い(intrusive)×遠い×変動 -> RED（バランス違反の最悪形。modularity-red.tsv に載る）
#   2. 強い×近い×変動 -> RED でない（強い結合は近くなら均衡 = XOR）
#   3. 弱い(contract)×遠い×変動 -> RED でない（遠い結合は弱ければ均衡 = XOR）
#   4. 強い×遠い×安定 -> RED でない（変動しなければ許容 = OR NOT VOLATILITY）
#   5. 弱い×近い×変動 -> YELLOW（統合候補のシグナル。RED ではない＝ゲートは塞がない）
#   6. 未分類エッジは既定レベル(model)で評価され、未分類として報告される（判断層への作業キュー）
#   7. --strict は RED があれば exit 1（advisory 既定は常に exit 0）
#   8. 分類TSVに不正なレベル語 -> setup error（憶測で続行しない）
#   9. エッジ0件 -> pass（評価対象なしを明示）
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/measure-modularity.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT

# 共通フィクスチャ: 内部パッケージ4種のエッジ（1行 = src_pkg \t dst_pkg \t src_file）
#   near: com.ex.order.core -> com.ex.order.api   (兄弟パッケージ、距離2)
#   far : com.ex.order.core -> com.ex.billing.gw  (別ツリー、距離4)
# volatility: billing.gw と order.api は変動大(12)、com.ex.stable は安定(0=未記載)
printf 'com.ex.billing.gw\t12\ncom.ex.order.api\t12\n' > "$D/vol.tsv"

# run <edges> <strength_tsv or ""> [--strict]: シーム経由で実行
run_m() {
  edges="$1"; st="$2"; shift 2
  OUT="$(cd "$D" && MODULARITY_EDGES_FILE="$edges" MODULARITY_VOLATILITY_FILE="$D/vol.tsv" \
        MODULARITY_STRENGTH_FILE="${st:-$D/no-such-strength.tsv}" \
        MODULARITY_OUT_DIR="$D/out" sh "$SCRIPT" "$@" 2>&1)" && RC=0 || RC=$?
}

echo "property 1: strong x distant x volatile -> RED"
printf 'com.ex.order.core\tcom.ex.billing.gw\tsrc/A.java\n' > "$D/e1"
printf 'com.ex.order.core\tcom.ex.billing.gw\tintrusive\tinternal state poked (src/A.java:42)\n' > "$D/s1"
run_m "$D/e1" "$D/s1"
[ "$RC" -eq 0 ] && pass "advisory default -> exit 0" || fail "expected 0, got $RC: $OUT"
grep -q 'com.ex.order.core	com.ex.billing.gw' "$D/out/modularity-red.tsv" \
  && pass "edge lands in modularity-red.tsv" || fail "red tsv missing edge: $(cat "$D/out/modularity-red.tsv" 2>/dev/null)"
printf '%s\n' "$OUT" | grep -q 'RED' && pass "report shows RED" || fail "no RED in report: $OUT"

echo "property 2: strong x NEAR x volatile -> not RED (XOR)"
printf 'com.ex.order.core\tcom.ex.order.api\tsrc/B.java\n' > "$D/e2"
printf 'com.ex.order.core\tcom.ex.order.api\tintrusive\tsame subsystem (src/B.java:10)\n' > "$D/s2"
run_m "$D/e2" "$D/s2"
[ -s "$D/out/modularity-red.tsv" ] && fail "near edge wrongly RED: $(cat "$D/out/modularity-red.tsv")" \
  || pass "strong-near-volatile is balanced"

echo "property 3: WEAK x distant x volatile -> not RED (XOR)"
printf 'com.ex.order.core\tcom.ex.billing.gw\tsrc/C.java\n' > "$D/e3"
printf 'com.ex.order.core\tcom.ex.billing.gw\tcontract\tpublished API only (src/C.java:5)\n' > "$D/s3"
run_m "$D/e3" "$D/s3"
[ -s "$D/out/modularity-red.tsv" ] && fail "contract edge wrongly RED: $(cat "$D/out/modularity-red.tsv")" \
  || pass "weak-distant-volatile is balanced"

echo "property 4: strong x distant x STABLE -> not RED (OR NOT VOLATILITY)"
printf 'com.ex.order.core\tcom.ex.stable.util\tsrc/D.java\n' > "$D/e4"
printf 'com.ex.order.core\tcom.ex.stable.util\tintrusive\tlegacy util reach-in (src/D.java:7)\n' > "$D/s4"
run_m "$D/e4" "$D/s4"
[ -s "$D/out/modularity-red.tsv" ] && fail "stable edge wrongly RED: $(cat "$D/out/modularity-red.tsv")" \
  || pass "strong-distant-stable is tolerated"

echo "property 5: weak x near x volatile -> YELLOW (merge candidate), not RED"
printf 'com.ex.order.core\tcom.ex.order.api\tsrc/E.java\n' > "$D/e5"
printf 'com.ex.order.core\tcom.ex.order.api\tcontract\tevent contract only (src/E.java:3)\n' > "$D/s5"
run_m "$D/e5" "$D/s5"
[ -s "$D/out/modularity-red.tsv" ] && fail "yellow edge wrongly RED" || pass "not RED"
printf '%s\n' "$OUT" | grep -q 'YELLOW' && pass "report shows YELLOW merge-candidate signal" \
  || fail "no YELLOW in report: $OUT"

echo "property 6: unclassified edge -> default level, reported as work queue for the judgment layer"
printf 'com.ex.order.core\tcom.ex.billing.gw\tsrc/F.java\n' > "$D/e6"
run_m "$D/e6" ""
[ "$RC" -eq 0 ] && pass "runs without a strength tsv" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -qi 'unclassified' && pass "names unclassified edges" \
  || fail "unclassified not surfaced: $OUT"

echo "property 7: --strict exits 1 when a RED edge exists"
printf 'com.ex.order.core\tcom.ex.billing.gw\tintrusive\treach-in (src/A.java:42)\n' > "$D/s7"
run_m "$D/e1" "$D/s7" --strict
[ "$RC" -eq 1 ] && pass "--strict with RED -> exit 1" || fail "expected 1, got $RC: $OUT"
run_m "$D/e3" "$D/s3" --strict
[ "$RC" -eq 0 ] && pass "--strict with no RED -> exit 0" || fail "expected 0, got $RC: $OUT"

echo "property 8: invalid strength level word -> setup error (no silent continue)"
printf 'com.ex.order.core\tcom.ex.billing.gw\tvery-strong\toops\n' > "$D/s8"
run_m "$D/e1" "$D/s8"
[ "$RC" -eq 2 ] && pass "invalid level -> exit 2" || fail "expected 2, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'very-strong' && pass "names the offending level" || fail "level not named: $OUT"

echo "property 9: zero edges -> pass and say so"
: > "$D/e9"
run_m "$D/e9" ""
[ "$RC" -eq 0 ] && pass "zero edges -> exit 0" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -qi 'no .*edge' && pass "explains nothing to assess" || fail "no explanation: $OUT"

echo "---- test-measure-modularity: PASS=$PASS FAIL=$FAIL ----"
[ "$FAIL" -eq 0 ]
