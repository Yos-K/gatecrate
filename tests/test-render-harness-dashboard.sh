#!/bin/sh
# tests/test-render-harness-dashboard.sh — core/scripts/render-harness-dashboard.sh の挙動テスト
#
# 文脈: 導入したゲート/ツールの状態を GitHub 上で一目で見るダッシュボード。既存のデータ源
# （classify-gate-type=型・probe-gate-liveness=生存・gate-roi-verdict=ROI判定）を1枚の markdown 表に描画し、
# CI が $GITHUB_STEP_SUMMARY に流す。本テストは描画の構造（表ヘッダ・各ゲート行・型・not-a-gate 除外）を検証する。
#
# 検証する性質:
#   1. markdown の見出しと表ヘッダ（Gate/Type/Liveness/Verdict）を出す
#   2. 分類対象ゲートを1行ずつ、型つきで出す（prevention/detection/advisory）
#   3. not-a-gate（ハーネスのツール）は表の本体に出さない（除外 or 別記）
#   4. exit 0（ダッシュボードは描画ツール＝失敗しない）
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/render-harness-dashboard.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

# fixture gate dir: render needs classify (+ probe sibling); gates carry type markers
D="$(mktemp -d)"; git -C "$D" init -q; mkdir -p "$D/scripts"
cp "$ROOT/core/scripts/render-harness-dashboard.sh" "$D/scripts/"
cp "$ROOT/core/scripts/classify-gate-type.sh" "$ROOT/core/scripts/probe-gate-liveness.sh" "$D/scripts/"
cp "$ROOT/core/scripts/collect-gate-history.sh" "$D/scripts/"   # a not-a-gate tool (must be excluded from the body)
printf '#!/bin/sh\n# gatecrate-type: prevention\nexit 0\n' > "$D/scripts/check-alpha.sh"
printf '#!/bin/sh\n# gatecrate-type: advisory\nexit 0\n'   > "$D/scripts/check-beta.sh"

OUT="$(cd "$D" && DASHBOARD_DIR=scripts sh scripts/render-harness-dashboard.sh 2>&1)" && RC=0 || RC=$?

echo "property 4: render exits 0"
[ "$RC" -eq 0 ] && pass "exit 0" || fail "expected 0, got $RC: $OUT"

echo "property 1: emits a markdown heading and a table header"
printf '%s\n' "$OUT" | grep -qE '^#+ .*[Dd]ashboard' && pass "has a heading" || fail "no heading: $OUT"
printf '%s\n' "$OUT" | grep -qiE '\| *Gate *\|.*Type.*\|.*Liveness.*\|.*Verdict' && pass "has the table header" || fail "no table header: $OUT"

echo "property 1b: has a Next action column that turns non-final states into concrete guidance"
printf '%s\n' "$OUT" | grep -qiE '\|.*Next action.*\|' && pass "has a Next action column" || fail "no Next action column: $OUT"
printf '%s\n' "$OUT" | grep -qE 'synthetic reject injector|confirm the signal is consumed|classify —|collect firing history' && pass "gives a concrete next action for a non-final state" || fail "no next-action guidance: $OUT"

echo "property 2: each classified gate is a row with its type"
printf '%s\n' "$OUT" | grep -E 'check-alpha\.sh' | grep -q 'prevention' && pass "alpha row -> prevention" || fail "alpha/prevention missing: $OUT"
printf '%s\n' "$OUT" | grep -E 'check-beta\.sh' | grep -q 'advisory' && pass "beta row -> advisory" || fail "beta/advisory missing: $OUT"

echo "property 3: a not-a-gate tool is not rendered as a gate row in the table body"
# a table-body row starts with '|' and names the gate (possibly in backticks); the footer summary
# line begins with '_', so it never false-matches. The tool must appear in NO table row.
printf '%s\n' "$OUT" | grep -E '^\|.*collect-gate-history' && fail "tool wrongly in table body" || pass "not-a-gate excluded from body"

echo "property 7: shows numbers + a mermaid graph (GitHub renders mermaid inline)"
printf '%s\n' "$OUT" | grep -q '```mermaid' && pass "has a mermaid graph block" || fail "no mermaid: $OUT"
printf '%s\n' "$OUT" | grep -qi 'title Gate types' && pass "type-distribution pie titled" || fail "no type pie: $OUT"
printf '%s\n' "$OUT" | grep -qE '[0-9]+ gates' && pass "shows a gate count" || fail "no gate count: $OUT"

echo "property 8: includes a mermaid flowchart of how gates are judged (a diagram)"
printf '%s\n' "$OUT" | grep -q 'flowchart' && pass "has a flowchart diagram" || fail "no flowchart: $OUT"
printf '%s\n' "$OUT" | grep -qi 'How gates are judged' && pass "has the judging legend" || fail "no legend heading: $OUT"

echo "property 5: DASHBOARD_GENERATED_AT, when set, adds a 'Generated:' line (for the committed snapshot); unset adds none"
G="$(cd "$D" && DASHBOARD_DIR=scripts DASHBOARD_GENERATED_AT='2026-06-20 09:00Z' sh scripts/render-harness-dashboard.sh 2>&1)"
printf '%s\n' "$G" | grep -q 'Generated: 2026-06-20 09:00Z' && pass "stamps the generated time" || fail "no Generated line: $G"
printf '%s\n' "$OUT" | grep -q 'Generated:' && fail "must not stamp when env unset" || pass "no Generated line when unset"

echo "property 6: --snapshot prepends a standalone title (for the committed, repo-visible file)"
S="$(cd "$D" && DASHBOARD_DIR=scripts sh scripts/render-harness-dashboard.sh --snapshot 2>&1)"
printf '%s\n' "$S" | grep -qE '^# .*harness status' && pass "snapshot has a top-level title" || fail "no snapshot title: $S"
printf '%s\n' "$OUT" | grep -qE '^# .*harness status' && fail "default mode must not add the standalone title" || pass "default mode is section-only"

echo "property 9: --counts prints a dated TSV row of the type/liveness counts (for history)"
C="$(cd "$D" && DASHBOARD_DIR=scripts DASHBOARD_DATE=2026-06-20 sh scripts/render-harness-dashboard.sh --counts 2>&1)"
# fixture has check-alpha=prevention, check-beta=advisory -> prev=1, det=0, adv=1, unt=0
printf '%s\n' "$C" | grep -qE '^2026-06-20	1	0	1	0	' && pass "counts row: date + per-type counts" || fail "bad counts row: $C"

echo "property 10: with >=2 dated history rows, a mermaid xychart trend is drawn"
H="$D/hist.tsv"
printf '2026-06-18\t12\t1\t3\t0\t9\t0\n2026-06-19\t13\t1\t4\t0\t10\t0\n' > "$H"
T="$(cd "$D" && DASHBOARD_DIR=scripts DASHBOARD_HISTORY="$H" sh scripts/render-harness-dashboard.sh 2>&1)"
printf '%s\n' "$T" | grep -q 'xychart-beta' && pass "draws an xychart trend" || fail "no xychart: $T"
printf '%s\n' "$T" | grep -qi 'over time' && pass "trend titled" || fail "no trend title: $T"

echo "property 11: with <2 history rows, no chart — an honest 'accruing' note instead"
printf '2026-06-19\t13\t1\t4\t0\t10\t0\n' > "$H"
T1="$(cd "$D" && DASHBOARD_DIR=scripts DASHBOARD_HISTORY="$H" sh scripts/render-harness-dashboard.sh 2>&1)"
printf '%s\n' "$T1" | grep -q 'xychart-beta' && fail "must not draw a chart from 1 point" || pass "no chart with <2 points"
printf '%s\n' "$T1" | grep -qi 'accruing' && pass "shows an accruing note" || fail "no accruing note: $T1"

echo "property 12: with a firing TSV, a CI-cost bar chart is drawn (top gates by seconds)"
FT="$D/firing.tsv"
printf 'gate\truns\tfires\tfire_rate\ttotal_seconds\tavg_seconds\n' > "$FT"
printf 'shellcheck\t30\t0\t0.00\t150\t5.0\n' >> "$FT"
printf 'mutation\t30\t4\t0.13\t600\t20.0\n' >> "$FT"
printf 'secrets\t30\t0\t0.00\t10\t0.3\n' >> "$FT"
B="$(cd "$D" && DASHBOARD_DIR=scripts DASHBOARD_FIRING_TSV="$FT" sh scripts/render-harness-dashboard.sh 2>&1)"
printf '%s\n' "$B" | grep -q 'title "CI cost' && pass "CI-cost chart titled" || fail "no CI cost chart title: $B"
printf '%s\n' "$B" | grep -qE '^    bar ' && pass "uses a mermaid bar series" || fail "no bar series: $B"
printf '%s\n' "$B" | grep -q 'mutation' && pass "names the costliest gate (mutation)" || fail "costliest gate missing: $B"

echo "property 13: a fires bar appears when the TSV has fires>0"
printf '%s\n' "$B" | grep -qi 'fires by gate\|fired' && pass "shows a fires chart" || fail "no fires chart: $B"

echo "property 14: without a firing TSV, no CI-cost section"
printf '%s\n' "$OUT" | grep -qi 'CI cost' && fail "cost section drawn without firing data" || pass "no cost section when no firing TSV"
rm -rf "$D"

echo ""
echo "render-harness-dashboard tests: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
