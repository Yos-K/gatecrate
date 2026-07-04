#!/bin/sh
# tests/test-classify-gate-type.sh — core/scripts/classify-gate-type.sh の挙動テスト
#
# 文脈（ROADMAP P4・docs/probe-scope-and-gate-classification-decision.md §3）: ROI 剪定は
# 「予防型で発火0(正常)」と「検出型で発火0(削除候補)」を発火履歴だけでは区別できない。だから型が要る。
# 型は手貼りラベルでなく構造から導出する: 予防型 = probe の reject-type レジストリ在籍、
# 検出型/その他 = 人間の `# gatecrate-type:` マーカー、どちらでもなければ untyped。
# 意味的に誤分類されたラベルは検出しない（空虚テスト検出と同じ壁・是正は人間 escalation）。
#
# 検証する性質:
#   1. reject-type レジストリ在籍ゲートは prevention と導出される（単一ソース=probe --list-reject-gates）
#   2. 非reject の measure-* ゲートは untyped（導出も上書きも無い＝可視化対象）
#   3. `# gatecrate-type: detection` マーカー付きは detection（人間上書き）
#   4. レジストリ非在籍でも `# gatecrate-type: prevention` 付きは prevention（人間上書き）
#   5. レジストリ在籍はマーカーより優先（構造的事実が一次・上書きは導出不能なゲート向け）
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/classify-gate-type.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

# verdict() — run --one on a gate path, capture stdout+rc into OUT/RC.
verdict() { OUT="$(sh "$SCRIPT" --one "$1" 2>&1)" && RC=0 || RC=$?; }

echo "property 1: a reject-type registry gate is derived as prevention"
verdict "$ROOT/core/scripts/check-conventional-title.sh"
[ "$RC" -eq 0 ] && pass "exit 0" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q '^prevention' && pass "title -> prevention" || fail "not prevention: $OUT"

echo "property 2: a gate with no marker and not in the registry is untyped (surfaced, not guessed)"
# A throwaway fixture, not a real kit gate: once the kit classifies its own gates (markers), no real
# gate stays untyped — so the untyped example must be a fixture to keep this property stable.
U="$(mktemp -d)"
printf '#!/bin/sh\necho hi\nexit 0\n' > "$U/check-unmarked.sh"
verdict "$U/check-unmarked.sh"
printf '%s\n' "$OUT" | grep -q '^untyped' && pass "unmarked non-registry gate -> untyped" || fail "not untyped: $OUT"
rm -rf "$U"

echo "property 3: a gate carrying '# gatecrate-type: detection' is detection (human override)"
D="$(mktemp -d)"
printf '#!/bin/sh\n# gatecrate-type: detection\nexit 0\n' > "$D/check-fake-detect.sh"
verdict "$D/check-fake-detect.sh"
printf '%s\n' "$OUT" | grep -q '^detection' && pass "marker -> detection" || fail "not detection: $OUT"

echo "property 4: a non-registry gate marked '# gatecrate-type: prevention' is prevention (human override)"
printf '#!/bin/sh\n# gatecrate-type: prevention\nexit 0\n' > "$D/check-fake-prevent.sh"
verdict "$D/check-fake-prevent.sh"
printf '%s\n' "$OUT" | grep -q '^prevention' && pass "marker -> prevention" || fail "not prevention: $OUT"

echo "property 5: registry membership wins over a conflicting marker (structure is primary)"
# a copy of a real registry gate that ALSO carries a detection marker must still classify prevention:
# classify derives from structure first and never tries to adjudicate a semantic mislabel.
cp "$ROOT/core/scripts/check-conventional-title.sh" "$D/check-conventional-title.sh"
printf '# gatecrate-type: detection\n' >> "$D/check-conventional-title.sh"
verdict "$D/check-conventional-title.sh"
printf '%s\n' "$OUT" | grep -q '^prevention' && pass "registry beats marker -> prevention" || fail "marker overrode registry: $OUT"

echo "property 6: a gate marked '# gatecrate-type: advisory' is advisory (non-rejecting, not firing-prunable)"
printf '#!/bin/sh\n# gatecrate-type: advisory\nexit 0\n' > "$D/check-fake-advisory.sh"
verdict "$D/check-fake-advisory.sh"
printf '%s\n' "$OUT" | grep -q '^advisory' && pass "marker -> advisory" || fail "not advisory: $OUT"
rm -rf "$D"

echo "property 7: harness tooling (not a gate) is reported as not-a-gate, outside ROI classification"
verdict "$ROOT/core/scripts/collect-gate-history.sh"
printf '%s\n' "$OUT" | grep -q '^not-a-gate' && pass "collect-gate-history -> not-a-gate" || fail "not excluded: $OUT"
verdict "$ROOT/core/scripts/probe-gate-liveness.sh"
printf '%s\n' "$OUT" | grep -q '^not-a-gate' && pass "probe -> not-a-gate" || fail "not excluded: $OUT"

# explain() — run --explain on a gate path, capture stdout+rc into OUT/RC.
explain() { OUT="$(sh "$SCRIPT" --explain "$1" 2>&1)" && RC=0 || RC=$?; }

echo "property 8: --explain emits the decidability evidence block + the never-auto-apply note"
explain "$ROOT/core/scripts/check-conventional-title.sh"
[ "$RC" -eq 0 ] && pass "--explain exit 0" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q '^evidence:' && pass "has an evidence block" || fail "no evidence block: $OUT"
printf '%s\n' "$OUT" | grep -q 'firing-history.*needs-gh' && pass "marks firing-history needs-gh (not guessed)" || fail "firing not marked needs-gh: $OUT"
printf '%s\n' "$OUT" | grep -qi 'never auto-applied\|自動適用しない' && pass "states the suggestion is never auto-applied" || fail "no auto-apply guardrail note: $OUT"

echo "property 9: --explain on a registry gate shows reject-registry yes and suggests prevention"
printf '%s\n' "$OUT" | grep -qE 'reject-registry:[[:space:]]*yes' && pass "registry evidence = yes" || fail "registry not yes: $OUT"
printf '%s\n' "$OUT" | grep -q '^suggested: prevention' && pass "suggests prevention" || fail "not prevention: $OUT"

echo "property 10: --explain suggests detection for a blocking, non-registry, non-advisory gate"
E="$(mktemp -d)"
printf '#!/bin/sh\necho bad\nexit 1\n' > "$E/check-blocky.sh"
explain "$E/check-blocky.sh"
printf '%s\n' "$OUT" | grep -qE 'blocks-merge:[[:space:]]*yes' && pass "blocks-merge = yes" || fail "blocks not yes: $OUT"
printf '%s\n' "$OUT" | grep -q '^suggested: detection' && pass "suggests detection" || fail "not detection: $OUT"

echo "property 11: --explain suggests advisory for a gate that self-declares advisory / opts into --strict"
printf '#!/bin/sh\n# advisory by default; --strict to enforce\nexit 0\n' > "$E/check-soft.sh"
explain "$E/check-soft.sh"
printf '%s\n' "$OUT" | grep -q '^suggested: advisory' && pass "suggests advisory" || fail "not advisory: $OUT"
rm -rf "$E"

echo "property 12: the suggestion is presented as an inference ladder (observe -> ... -> conclude)"
F="$(mktemp -d)"
printf '#!/bin/sh\necho bad\nexit 1\n' > "$F/check-laddery.sh"
explain "$F/check-laddery.sh"
printf '%s\n' "$OUT" | grep -qi 'inference ladder' && pass "labels the ladder" || fail "no ladder: $OUT"
printf '%s\n' "$OUT" | grep -qE '^[[:space:]]+observe:' && pass "has an observe rung" || fail "no observe rung: $OUT"
printf '%s\n' "$OUT" | grep -qE '^[[:space:]]+conclude:' && pass "has a conclude rung" || fail "no conclude rung: $OUT"

echo "property 13: the load-bearing assumption is flagged UNVERIFIED and 'check first' names that rung"
printf '%s\n' "$OUT" | grep -qE '^[[:space:]]+assume:.*UNVERIFIED' && pass "assume rung marked UNVERIFIED" || fail "assume not flagged: $OUT"
printf '%s\n' "$OUT" | grep -qi 'check first' && pass "names the rung to check first" || fail "no check-first: $OUT"
rm -rf "$F"

echo "property 14: when there is no inferential leap (registry fact), the ladder collapses (no UNVERIFIED rung)"
explain "$ROOT/core/scripts/check-conventional-title.sh"
printf '%s\n' "$OUT" | grep -qi 'no inferential leap' && pass "states no inferential leap" || fail "no collapse note: $OUT"
printf '%s\n' "$OUT" | grep -q 'UNVERIFIED' && fail "must not invent an UNVERIFIED rung for a structural fact" || pass "no spurious UNVERIFIED rung"

echo ""
echo "classify-gate-type tests: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
