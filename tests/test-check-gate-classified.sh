#!/bin/sh
# tests/test-check-gate-classified.sh — core/scripts/check-gate-classified.sh の挙動テスト
#
# 文脈（ROADMAP P4 / docs/probe-scope-and-gate-classification-decision.md §3 step2）: ROI 剪定は
# ゲートの型を要する。型の無い（untyped）ゲートは「分類し忘れ」で剪定ロジックが適用できない。本メタゲートは
# untyped を機械検出して止め、失敗時に --explain の判断材料を載せる。意味的誤分類は検出しない（§3.2/§1）。
#
# 検証する性質:
#   1. untyped ゲートが在れば fail(exit 1) で名指し
#   2. 失敗メッセージに classify --explain の判断材料（証拠 / 推論のはしご）が載る
#   3. 全ゲートが分類済み（prevention/detection/advisory）または not-a-gate なら pass(exit 0)
#   4. ハーネスのツール（not-a-gate）は untyped 扱いされず失敗の原因にならない
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

# Build a throwaway gate dir with the meta-gate + its deps (classify needs probe as a sibling).
D="$(mktemp -d)"; git -C "$D" init -q; mkdir -p "$D/scripts"
cp "$ROOT/core/scripts/check-gate-classified.sh" "$D/scripts/"
cp "$ROOT/core/scripts/classify-gate-type.sh"    "$D/scripts/"
cp "$ROOT/core/scripts/probe-gate-liveness.sh"   "$D/scripts/"
cp "$ROOT/core/scripts/collect-gate-history.sh"  "$D/scripts/"   # a not-a-gate tool (must not trip the meta-gate)
# a classified gate (advisory marker) and an unclassified one (no marker, not in the registry)
printf '#!/bin/sh\n# gatecrate-type: advisory\nexit 0\n' > "$D/scripts/check-bar.sh"
printf '#!/bin/sh\necho bad\nexit 1\n'                   > "$D/scripts/check-foo.sh"
run() { OUT="$(cd "$D" && GATE_CLASSIFIED_DIR=scripts sh scripts/check-gate-classified.sh 2>&1)" && RC=0 || RC=$?; }

echo "property 1: an untyped gate makes the meta-gate fail and is named"
run
[ "$RC" -eq 1 ] && pass "untyped present -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'check-foo' && pass "names the unclassified gate" || fail "no name: $OUT"

echo "property 2: the failure embeds the --explain decidability evidence (the inference ladder)"
printf '%s\n' "$OUT" | grep -qi 'inference ladder' && pass "embeds the ladder" || fail "no ladder: $OUT"

echo "property 4: a not-a-gate tool present in the dir does NOT get reported as untyped"
# (the tool name legitimately appears in an --explain 'firing-history: needs-gh (collect-gate-history)'
# line; what must be absent is its OWN --explain header 'gate: collect-gate-history.sh' = being flagged.)
printf '%s\n' "$OUT" | grep -q '^gate: collect-gate-history' && fail "tool wrongly surfaced" || pass "tool not flagged"

echo "property 3: once every gate is classified, the meta-gate passes"
printf '# gatecrate-type: detection\n' >> "$D/scripts/check-foo.sh"   # classify the last untyped gate
run
[ "$RC" -eq 0 ] && pass "all classified -> exit 0" || fail "expected 0, got $RC: $OUT"
rm -rf "$D"

echo ""
echo "check-gate-classified tests: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
