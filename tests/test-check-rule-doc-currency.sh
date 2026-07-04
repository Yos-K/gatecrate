#!/bin/sh
# tests/test-check-rule-doc-currency.sh — core/scripts/check-rule-doc-currency.sh の挙動テスト
#
# 文脈（ドメイン学習ループの「知識が腐らない」保証）: 規則担持ファイルを変えたら対応文書も同じ PR で
# 更新する(または影響なしと宣言する)を機械化するゲート。レーンは設定駆動(TSV)、エンジンは汎用。
# diff/commit を RULE_DOC_CHANGED/RULE_DOC_COMMITS の env seam で差し込み、git 非依存で決定論に検証する。
#
# 検証する性質:
#   1. trigger 発火 + doc 未更新 + トレーラ無し -> FAIL(exit 1) で該当レーンを列挙
#   2. trigger 発火 + doc 更新済み -> ok(exit 0)
#   3. trigger 発火 + 普遍トレーラ Docs-Impact: -> 免除(exit 0)
#   4. trigger 発火 + レーン専用トレーラ(col4) -> 免除(exit 0)
#   5. 複数レーン: 片方だけ未更新 -> その1レーンだけ FAIL に出る
#   6. trigger 非発火(無関係変更) -> ok(exit 0)
#   7. レーン定義ファイル不在 -> skip(exit 0・偽失敗しない)
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-rule-doc-currency.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
TAB="$(printf '\t')"

# lanes <file>: 2レーン定義（glossary=専用トレーラ付き / harness=トレーラ無し）を書く
lanes() {
  {
    printf '# name%strigger%sdoc%sexempt\n' "$TAB" "$TAB" "$TAB"
    printf 'glossary%s^src/domain/.*\\.java$%s^docs/glossary\\.md$%sGlossary-Impact:\n' "$TAB" "$TAB" "$TAB"
    printf 'harness%s^scripts/check-.*\\.sh$%s^docs/harness\\.md$%s\n' "$TAB" "$TAB" "$TAB"
  } > "$1"
}

# run <changed> <commits> : RULE_DOC_CHANGED/COMMITS seam で実行。$OUT/$RC を設定。
LF="$(mktemp)"; lanes "$LF"
run() {
  OUT="$(RULE_DOC_LANES="$LF" RULE_DOC_CHANGED="$1" RULE_DOC_COMMITS="$2" sh "$SCRIPT" 2>&1)" && RC=0 || RC=$?
}

echo "property 1: trigger fires + doc not updated + no trailer -> FAIL"
run "src/domain/Order.java" ""
[ "$RC" -eq 1 ] && pass "exit 1 on missing doc" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'missing doc updates for: glossary' && pass "names glossary lane" || fail "lane not named: $OUT"
printf '%s\n' "$OUT" | grep -q '  - src/domain/Order.java' && pass "lists the rule-bearing file" || fail "file not listed: $OUT"

echo "property 2: trigger fires + matching doc updated -> ok"
run "src/domain/Order.java
docs/glossary.md" ""
[ "$RC" -eq 0 ] && pass "exit 0 when doc updated" || fail "expected 0, got $RC: $OUT"

echo "property 3: universal Docs-Impact: trailer exempts the lane"
run "src/domain/Order.java" "refactor: rename field

Docs-Impact: none (pure rename)"
[ "$RC" -eq 0 ] && pass "exit 0 with Docs-Impact" || fail "expected 0, got $RC: $OUT"

echo "property 4: lane-specific legacy trailer (col4) exempts only via that name"
run "src/domain/Order.java" "tweak

Glossary-Impact: none"
[ "$RC" -eq 0 ] && pass "exit 0 with lane trailer" || fail "expected 0, got $RC: $OUT"
# harness レーンは col4 が空なので Glossary-Impact: では免除されない（trigger 発火時）
run "scripts/check-foo.sh" "x

Glossary-Impact: none"
[ "$RC" -eq 1 ] && pass "lane trailer does NOT cross to a lane without it" || fail "harness wrongly exempted: $OUT"

echo "property 5: multiple lanes fire, only the undocumented one is reported"
run "src/domain/Order.java
scripts/check-foo.sh
docs/glossary.md" ""
[ "$RC" -eq 1 ] && pass "exit 1 (harness still missing)" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'missing doc updates for: harness' && pass "harness reported" || fail "harness missing from report: $OUT"
printf '%s\n' "$OUT" | grep -q 'glossary' && fail "glossary wrongly reported (its doc was updated): $OUT" || pass "satisfied glossary not reported"

echo "property 6: unrelated change (no trigger) -> ok"
run "README.md
src/util/Helper.kt" ""
[ "$RC" -eq 0 ] && pass "exit 0 when no lane triggers" || fail "expected 0, got $RC: $OUT"

echo "property 7: missing lane file -> skip (exit 0), not a false failure"
OUT="$(RULE_DOC_LANES="/no/such/lanes.tsv" RULE_DOC_CHANGED="src/domain/Order.java" sh "$SCRIPT" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 0 ] && pass "exit 0 with no lane file" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -qi 'nothing configured' && pass "reports skip reason" || fail "no skip notice: $OUT"

rm -f "$LF"
echo ""
echo "check-rule-doc-currency tests: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
