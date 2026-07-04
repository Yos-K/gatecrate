#!/bin/sh
# tests/test-collect-gate-history.sh — core/scripts/collect-gate-history.sh の集計層テスト
#
# 文脈（ROADMAP P4・ROI手順①②）: 二階ループの剪定判断は「各ゲートが何回実行され／何回発火し／
# CI秒をいくら使ったか」という実績データを前提にする。fetch 層は gh 依存・非決定論なので、
# テスト対象は決定論な集計層（--aggregate, stdin TSV → ゲート別レポート）に限定する。
#
# 検証する性質:
#   1. 検出型ゲート（成功/失敗が混在）は runs/fires/fire_rate を正しく数える
#   2. 予防型ゲート（全成功）は fires=0・fire_rate=0.000（発火ゼロが正常）
#   3. skipped/cancelled/null は実行（runs 分母）に数えない＝passに見せない
#   4. seconds=NA は秒平均から除外するが行自体は計上する
#   5. 出力はヘッダ付き・ゲート名でソート済み
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/collect-gate-history.sh"
PASS=0
FAIL=0

fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

# agg <<EOF ... EOF を sh "$SCRIPT" --aggregate に流し、結果を $OUT に格納する。
# row <gate> -> $OUT から該当ゲート行を $ROW に格納（ヘッダ除く）。
agg() { OUT="$(printf '%s' "$1" | sh "$SCRIPT" --aggregate)"; }
row() { ROW="$(printf '%s\n' "$OUT" | awk -F '\t' -v g="$1" '$1==g {print; exit}')"; }
col() { printf '%s' "$ROW" | cut -f "$1"; }

# 入力 TSV: <gate>\t<conclusion>\t<seconds|NA>
INPUT='detect-tests	success	10
detect-tests	failure	12
detect-tests	success	8
detect-tests	failure	NA
prevent-secrets	success	1
prevent-secrets	success	1
prevent-secrets	skipped	0
flaky-only-skipped	skipped	0
flaky-only-skipped	cancelled	0'

agg "$INPUT"

# ---- 性質5: ヘッダがあり、ゲート名でソートされている ----
echo "property 5: header present and rows sorted by gate"
printf '%s\n' "$OUT" | head -1 | grep -q '^gate	runs	fires	fire_rate	total_seconds	avg_seconds$' \
  && pass "header row present" || fail "missing/incorrect header: $(printf '%s' "$OUT" | head -1)"
gates="$(printf '%s\n' "$OUT" | tail -n +2 | cut -f1)"
sorted="$(printf '%s\n' "$gates" | sort)"
[ "$gates" = "$sorted" ] && pass "gates sorted" || fail "gates not sorted: $gates"

# ---- 性質1: 検出型ゲートの runs/fires/fire_rate ----
echo "property 1: detection gate counts runs/fires/fire_rate"
row detect-tests
[ "$(col 2)" = "4" ] && pass "detect-tests runs=4" || fail "runs expected 4, got $(col 2)"
[ "$(col 3)" = "2" ] && pass "detect-tests fires=2" || fail "fires expected 2, got $(col 3)"
[ "$(col 4)" = "0.500" ] && pass "detect-tests fire_rate=0.500" || fail "rate expected 0.500, got $(col 4)"

# ---- 性質4: NA は秒平均から除外（3件の数値秒 10/12/8 → 30, avg=10.0）----
echo "property 4: NA seconds excluded from average, row still counted"
[ "$(col 5)" = "30.0" ] && pass "total_seconds=30.0 (NA excluded)" || fail "total expected 30.0, got $(col 5)"
[ "$(col 6)" = "10.0" ] && pass "avg_seconds=10.0 (over 3 numeric)" || fail "avg expected 10.0, got $(col 6)"

# ---- 性質2: 予防型ゲートは全成功 → fires=0, rate=0.000 ----
echo "property 2: prevention gate all-success -> fires=0"
row prevent-secrets
[ "$(col 2)" = "2" ] && pass "prevent-secrets runs=2 (skipped excluded)" || fail "runs expected 2, got $(col 2)"
[ "$(col 3)" = "0" ] && pass "prevent-secrets fires=0" || fail "fires expected 0, got $(col 3)"
[ "$(col 4)" = "0.000" ] && pass "prevent-secrets fire_rate=0.000" || fail "rate expected 0.000, got $(col 4)"

# ---- 性質3: skipped/cancelled のみのゲートは runs=0（pass に見せない）----
echo "property 3: skipped/cancelled-only gate has runs=0, not counted as pass"
row flaky-only-skipped
[ -n "$ROW" ] && pass "skipped-only gate still listed" || fail "skipped-only gate missing from report"
[ "$(col 2)" = "0" ] && pass "flaky-only-skipped runs=0" || fail "runs expected 0, got $(col 2)"
[ "$(col 3)" = "0" ] && pass "flaky-only-skipped fires=0" || fail "fires expected 0, got $(col 3)"

# ---- 性質4: 既定モードは fetch 失敗を伝播する（偽の空成功にしない）----
# fetch | aggregate のパイプ status は aggregate(0) になり fetch 失敗が隠れる回帰を防ぐ。
# 偽の gh（常に exit 1）を PATH 先頭に置き、fetch を決定論的に失敗させる。
echo "property 4: default mode propagates a fetch failure (not a false empty-success)"
GHFAKE="$(mktemp -d)"
printf '#!/bin/sh\nexit 1\n' > "$GHFAKE/gh"; chmod +x "$GHFAKE/gh"
OUT="$(PATH="$GHFAKE:$PATH" sh "$SCRIPT" 2>&1)" && RC=0 || RC=$?
[ "$RC" -ne 0 ] && pass "default mode exits non-zero on fetch failure" || fail "expected non-zero, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -qiE 'fetch failed|UNCONFIRMED' && pass "reports fetch failure" || fail "no failure notice: $OUT"
printf '%s\n' "$OUT" | grep -q '^gate	runs	fires' && fail "emitted the success header despite fetch failure" || pass "no bare header on fetch failure"
rm -rf "$GHFAKE"

# ---- 性質6: --group-map が step名を論理ゲートに束ね、未マップは生のまま残す ----
# 文脈（Issue #56）: 既定の集計は CIステップ名でグルーピングされるため、本物の品質ゲートと
# セットアップ手順（Checkout/Set up Java 等）が混ざり ROI 判断のシグナルが薄まる。マップで
# step名を論理ゲート（mutation/gradle-build/docs-currency/pr-title）に relabel して数えられること、
# かつ未マップ step は生の行として保持され（隠れず）、漸進的にマップを育てられることを検証する。
echo "property 6: --group-map relabels steps into logical gates; unmapped kept raw"
MAPFILE="$(mktemp)"
# グロブ(*)・先頭一致・FIRST match・# コメント・空行・CRLF を1ファイルで踏む
printf '%s\n' \
  '# logical gate map (step_pattern<TAB>logical_gate)' \
  '' \
  'Run mutation tests	mutation' \
  'Build Gradle debug variants*	gradle-build' \
  'Check documentation currency*	docs-currency' \
  'Validate pull request title	pr-title' > "$MAPFILE"
printf 'extra column	cobertura	ignored\r\n' >> "$MAPFILE"   # 3列目無視・CRLF許容

# 同一論理ゲートに複数の生 step が落ちる（mutation x2: 1成功+1失敗）、
# グロブ先頭一致（gradle-build）、未マップ（Checkout/Set up Java）、3列+CRLF（extra column）を含む入力
GINPUT='Run mutation tests	failure	120
Run mutation tests	success	95
Build Gradle debug variants and release bundle	success	40
Check documentation currency (glossary + rule docs)	success	3
Validate pull request title	success	1
Checkout	success	2
Set up Java	success	5
extra column	failure	9'
GOUT="$(printf '%s' "$GINPUT" | sh "$SCRIPT" --aggregate --group-map "$MAPFILE")"
grow() { GROW="$(printf '%s\n' "$GOUT" | awk -F '\t' -v g="$1" '$1==g {print; exit}')"; }
gcol() { printf '%s' "$GROW" | cut -f "$1"; }

grow mutation
[ "$(gcol 2)" = "2" ] && pass "mutation runs=2 (2 raw steps merged)" || fail "mutation runs expected 2, got $(gcol 2)"
[ "$(gcol 3)" = "1" ] && pass "mutation fires=1" || fail "mutation fires expected 1, got $(gcol 3)"
[ "$(gcol 4)" = "0.500" ] && pass "mutation fire_rate=0.500" || fail "mutation rate expected 0.500, got $(gcol 4)"
[ "$(gcol 5)" = "215.0" ] && pass "mutation total_seconds=215.0" || fail "mutation total expected 215.0, got $(gcol 5)"

grow gradle-build
[ -n "$GROW" ] && pass "glob prefix '*' matched gradle-build" || fail "gradle-build row missing (glob prefix failed)"
[ "$(gcol 2)" = "1" ] && pass "gradle-build runs=1" || fail "gradle-build runs expected 1, got $(gcol 2)"

grow docs-currency
[ -n "$GROW" ] && pass "docs-currency relabeled via glob" || fail "docs-currency row missing"

grow pr-title
[ -n "$GROW" ] && pass "pr-title relabeled via exact match" || fail "pr-title row missing"

# 3列目無視＋CRLF: "extra column" は cobertura に束ねられる
grow cobertura
[ -n "$GROW" ] && pass "extra map columns ignored, CRLF tolerated (cobertura)" || fail "cobertura row missing"

# 未マップ step は生の名前のまま残る（隠れない）
grow Checkout
[ -n "$GROW" ] && pass "unmapped step 'Checkout' kept as raw row" || fail "unmapped 'Checkout' vanished"
grow "Set up Java"
[ -n "$GROW" ] && pass "unmapped step 'Set up Java' kept as raw row" || fail "unmapped 'Set up Java' vanished"

# 生の step 名はもう論理ゲート集約後の出力に現れない（relabel が効いている）
printf '%s\n' "$GOUT" | grep -q '^Run mutation tests	' && fail "raw 'Run mutation tests' leaked despite mapping" || pass "raw mutation step name absorbed into logical gate"
rm -f "$MAPFILE"

# ---- 性質6b: --group-map 無指定なら既定の step名グルーピングは不変（後方互換）----
echo "property 6b: without --group-map, step-level behavior is unchanged"
agg "$INPUT"
row detect-tests
[ "$(col 2)" = "4" ] && pass "default mode unchanged (detect-tests runs=4)" || fail "default changed: runs=$(col 2)"

# ---- 性質6c: 読めない --group-map は非0で明示失敗（黙って無視しない）----
echo "property 6c: unreadable --group-map fails loudly"
GOUT2="$(printf 'x	success	1\n' | sh "$SCRIPT" --aggregate --group-map /no/such/map 2>&1)" && GRC=0 || GRC=$?
[ "$GRC" -ne 0 ] && pass "unreadable map exits non-zero" || fail "expected non-zero for missing map, got $GRC"
printf '%s\n' "$GOUT2" | grep -qi 'group-map' && pass "names the bad map flag" || fail "no group-map notice: $GOUT2"

echo ""
echo "collect-gate-history tests: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
