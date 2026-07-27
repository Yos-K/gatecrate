#!/bin/sh
# tests/test-check-intended-counterexample.sh — core/scripts/check-intended-counterexample.sh の挙動テスト
#
# 文脈: `.als` の `check ... expect 1` は「意図された反例（deliberate gap）」を表す規約
# （templates/spec/models/example.als.example が示す）。しかしその意図が**書かれているか**は
# 誰も検査していない。これは収束ループにとって致命的な穴になる——反例が出たアサートを
# `expect 0` から `expect 1` へ書き換えれば緑にできてしまい、「設計意図」という名目で
# ルール退行を静かに飲み込める（characterization trap の Alloy 版）。
# 本ゲートは `expect N`(N>0) に理由の明記を要求し、無言の格下げを不可能にする。
# ＝ ADR-Review の `none (<reason>)` と同じ思想（禁止ではなく、宣言と理由を強制する）。
#
# 検証する性質:
#   1. 理由付きの意図された反例 -> pass
#   2. 理由なしの expect 1 -> reject（無言の格下げを止める）
#   3. expect 0 は理由不要 -> pass（通常のアサートを縛らない）
#   4. 理由は同一行末コメントでも直前行コメントでもよい
#   5. .als が無い -> exit 0（検査不能を偽失敗にしない）
#   6. 複数モデル・複数違反を全て名指しする
#   7. コメントアウトされた check 行は対象外（テンプレの例示を誤検出しない）
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-intended-counterexample.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

mk() {
  W="$(mktemp -d)"
  git -C "$W" init -q
  mkdir -p "$W/scripts" "$W/docs/domain/models"
  cp "$SCRIPT" "$W/scripts/check-intended-counterexample.sh"
  echo "$W"
}
run() { OUT="$(sh "$1/scripts/check-intended-counterexample.sh" 2>&1)" && RC=0 || RC=$?; }

echo "property 1: an intended counterexample WITH a documented reason passes"
W="$(mk)"
cat > "$W/docs/domain/models/a.als" <<'EOF'
module a
check FromCodeIsInjective for 5 expect 1  // intended: unknown codes fail-closed to one state
EOF
run "$W"
[ "$RC" -eq 0 ] && pass "documented intent -> exit 0" || fail "expected 0, got $RC: $OUT"
rm -rf "$W"

echo "property 2: an expect 1 with NO documented reason is rejected"
W="$(mk)"
cat > "$W/docs/domain/models/a.als" <<'EOF'
module a
check FromCodeIsInjective for 5 expect 1
EOF
run "$W"
[ "$RC" -eq 1 ] && pass "undocumented intent -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'FromCodeIsInjective' && pass "names the assert" || fail "not named: $OUT"
rm -rf "$W"

echo "property 3: expect 0 needs no reason (ordinary asserts stay unconstrained)"
W="$(mk)"
cat > "$W/docs/domain/models/a.als" <<'EOF'
module a
check RoundTripHolds for 5 expect 0
check PlainAssert for 5
EOF
run "$W"
[ "$RC" -eq 0 ] && pass "expect 0 -> exit 0" || fail "expected 0, got $RC: $OUT"
rm -rf "$W"

echo "property 4: the reason may sit on the preceding comment line"
W="$(mk)"
cat > "$W/docs/domain/models/a.als" <<'EOF'
module a
// intended: fail-closed design maps several unknown codes onto one state
check FromCodeIsInjective for 5 expect 1
EOF
run "$W"
[ "$RC" -eq 0 ] && pass "preceding-line reason -> exit 0" || fail "expected 0, got $RC: $OUT"
rm -rf "$W"

echo "property 5: no .als files -> exit 0 (never a false failure)"
W="$(mk)"
run "$W"
[ "$RC" -eq 0 ] && pass "no models -> exit 0" || fail "expected 0, got $RC: $OUT"
rm -rf "$W"

echo "property 6: every offender across models is named (not just the first)"
W="$(mk)"
printf 'module a\ncheck AlphaHolds for 5 expect 1\n' > "$W/docs/domain/models/a.als"
printf 'module b\ncheck BetaHolds for 5 expect 1\n' > "$W/docs/domain/models/b.als"
run "$W"
[ "$RC" -eq 1 ] && pass "multiple offenders -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'AlphaHolds' && pass "names the first" || fail "first missing: $OUT"
printf '%s\n' "$OUT" | grep -q 'BetaHolds' && pass "names the second" || fail "second missing: $OUT"
rm -rf "$W"

echo "property 7: a commented-out check is not scanned (templates show examples in comments)"
W="$(mk)"
cat > "$W/docs/domain/models/a.als" <<'EOF'
module a
// check SomethingThatShouldNotHold for 5 expect 1
EOF
run "$W"
[ "$RC" -eq 0 ] && pass "commented example -> exit 0" || fail "expected 0, got $RC: $OUT"
rm -rf "$W"

echo "---- test-check-intended-counterexample: PASS=$PASS FAIL=$FAIL ----"
[ "$FAIL" -eq 0 ]
