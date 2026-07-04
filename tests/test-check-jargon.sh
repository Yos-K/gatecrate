#!/bin/sh
# tests/test-check-jargon.sh — core/scripts/check-jargon.sh の挙動テスト
#
# 文脈: CLAUDE.md Documentation Writing Rule §1「記号の単独使用禁止・初出で日本語併記」。Tx-ID/p50/SLI 等を
# 裸で使うとレビューが「これ何?」に費やされる。本ゲートは「用語を使うなら説明(gloss)も同ファイルに在る」を強制。
# 本テストは「説明済みなら通し、裸利用を reject し名指しし、JARGON_EXTRA で語を足せる」を回帰固定する。
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-jargon.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
D="$(mktemp -d)"; trap 'rm -rf "$D"' EXIT
run() { OUT="$(sh "$SCRIPT" "$1" 2>&1)" && RC=0 || RC=$?; }

echo "property 1: jargon explained on first use -> exit 0"
printf '取引ID(取引を一意に識別する番号)で突合する。Tx-ID は要求と確定を結ぶ。\n' > "$D/ok.md"
run "$D/ok.md"
[ "$RC" -eq 0 ] && pass "glossed jargon -> 0" || fail "expected 0, got $RC: $OUT"

echo "property 2: bare jargon (no gloss) -> exit 1 and named"
printf 'Tx-ID で突合する。\n' > "$D/bad.md"
run "$D/bad.md"
[ "$RC" -eq 1 ] && pass "bare jargon -> 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'Tx-ID' && pass "names the bare term" || fail "not named: $OUT"
printf '%s\n' "$OUT" | grep -q '取引ID' && pass "suggests a gloss" || fail "no suggestion: $OUT"

echo "property 3: a term not used at all is not flagged"
printf 'ふつうの日本語の文章。\n' > "$D/clean.md"
run "$D/clean.md"
[ "$RC" -eq 0 ] && pass "no jargon -> 0" || fail "expected 0, got $RC: $OUT"

echo "property 4: multiple bare terms are all reported"
printf 'p50 と SLI を見る。\n' > "$D/multi.md"
run "$D/multi.md"
[ "$RC" -eq 1 ] && pass "multiple -> 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'p50' && printf '%s\n' "$OUT" | grep -q 'SLI' && pass "reports both p50 and SLI" || fail "missing one: $OUT"

echo "property 5: JARGON_EXTRA extends the map"
printf 'RTO を超えた。\n' > "$D/extra.md"
OUT="$(JARGON_EXTRA='RTO~目標復旧時間~目標復旧時間(RTO)' sh "$SCRIPT" "$D/extra.md" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 1 ] && pass "extra term flagged -> 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'RTO' && pass "names the extra term" || fail "extra not named: $OUT"

echo "---- check-jargon: PASS=$PASS FAIL=$FAIL ----"
[ "$FAIL" -eq 0 ]
