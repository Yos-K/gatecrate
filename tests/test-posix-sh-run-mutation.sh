#!/bin/sh
# tests/test-posix-sh-run-mutation.sh — adapters/posix-sh/scripts/run-mutation.sh の挙動テスト
#
# 文脈: シェルハーネスには「テストの検出力」を測る手段が無く、変異テストは手作業に頼っていた。
# その手作業が信頼できないことは実測で判明している——26体の手動変異のうち**2体は sed が空振りし、
# 「変異が生き残った」という偽の結果**を出した（置換が一致しなかっただけなのに、結果が変わらないため
# テストの穴に見える）。本ランナーの存在理由はその誤りを構造的に潰すことなので、中心的な性質は
# 「**適用されなかった変異を生存に数えない**」である。ここが壊れると結論が逆向きに出る。
#
# 検証する性質:
#   1. テストが捕まえる変異 -> killed・exit 0
#   2. テストが捕まえない変異 -> SURVIVED・exit 1（テストの穴を告発する）
#   3. **適用されなかった変異 -> SKIP。生存に数えない**（偽陰性の防止・本ランナーの要）
#   4. SH_MUTATION_MAX_SURVIVORS の floor を尊重する
#   5. 実行後に対象ファイルが原状復帰する（変異を残さない）
#   6. テストファイル自身は変異させない
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/adapters/posix-sh/scripts/run-mutation.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

# mk <detects_boundary>: 使い捨て消費者リポを作る。引数が yes なら境界値も検証するテストを置く。
mk() {
  W="$(mktemp -d)"
  git -C "$W" init -q
  mkdir -p "$W/scripts" "$W/tests"
  cp "$SCRIPT" "$W/scripts/run-mutation.sh"
  cat > "$W/scripts/check-demo.sh" <<'EOF'
#!/bin/sh
set -eu
n=$(wc -l < "${1:-/dev/null}" | tr -d ' ')
if [ "$n" -gt 3 ]; then echo "too many"; exit 1; fi
echo ok
EOF
  if [ "$1" = "yes" ]; then
    cat > "$W/tests/test-check-demo.sh" <<'EOF'
#!/bin/sh
set -eu
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
printf 'a\nb\nc\n' > "$D/at"; printf 'a\nb\nc\nd\n' > "$D/over"; printf 'a\n' > "$D/small"
sh scripts/check-demo.sh "$D/small" >/dev/null || exit 1
sh scripts/check-demo.sh "$D/at"    >/dev/null || exit 1
sh scripts/check-demo.sh "$D/over"  >/dev/null && exit 1
exit 0
EOF
  else
    cat > "$W/tests/test-check-demo.sh" <<'EOF'
#!/bin/sh
set -eu
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
printf 'a\n' > "$D/small"
sh scripts/check-demo.sh "$D/small" >/dev/null || exit 1
exit 0
EOF
  fi
  echo "$W"
}
run() {
  W="$1"; shift
  OUT="$(cd "$W" && SH_MUTATION_TARGETS="scripts/check-demo.sh" \
        SH_MUTATION_TEST_CMD="sh tests/test-check-demo.sh" "$@" sh scripts/run-mutation.sh 2>&1)" && RC=0 || RC=$?
}

echo "property 1: mutants the tests catch are killed -> exit 0"
W="$(mk yes)"; run "$W"
[ "$RC" -eq 0 ] && pass "all killed -> exit 0" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'killed' && pass "reports killed mutants" || fail "no killed: $OUT"
rm -rf "$W"

echo "property 2: a mutant the tests miss is reported SURVIVED -> exit 1"
W="$(mk no)"; run "$W"
[ "$RC" -eq 1 ] && pass "survivor -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'SURVIVED' && pass "names the survivor" || fail "no survivor line: $OUT"
rm -rf "$W"

echo "property 3: a mutation that did NOT apply is SKIPped, never counted as survived [要]"
# check-demo.sh には `return 1` も `-lt` も無いので、それらの変異は適用されない。
# 適用されない変異を survived に数えると「テストが弱い」と逆の結論が出る（手作業で2度踏んだ罠）。
W="$(mk yes)"; run "$W"
printf '%s\n' "$OUT" | grep -q 'SKIP' && pass "reports SKIP for inapplicable mutators" || fail "no SKIP: $OUT"
printf '%s\n' "$OUT" | grep -q 'survived=0' && pass "SKIPs are not counted as survivors" || fail "miscounted: $OUT"
# SKIP された変異が SURVIVED としても出ていないこと
printf '%s\n' "$OUT" | grep 'SURVIVED' | grep -q '該当箇所なし' && fail "a skipped mutant leaked into SURVIVED: $OUT" || pass "SKIP and SURVIVED stay distinct"
rm -rf "$W"

echo "property 4: SH_MUTATION_MAX_SURVIVORS raises the floor"
W="$(mk no)"; run "$W" env SH_MUTATION_MAX_SURVIVORS=5
[ "$RC" -eq 0 ] && pass "survivors under the floor -> exit 0" || fail "expected 0, got $RC: $OUT"
rm -rf "$W"

echo "property 5: the target file is restored after the run (no mutant left behind)"
W="$(mk yes)"
before="$(cat "$W/scripts/check-demo.sh")"
run "$W"
after="$(cat "$W/scripts/check-demo.sh")"
[ "$before" = "$after" ] && pass "target restored byte-for-byte" || fail "target left mutated"
rm -rf "$W"

echo "property 6: test files themselves are not mutated"
W="$(mk yes)"
tbefore="$(cat "$W/tests/test-check-demo.sh")"
(cd "$W" && SH_MUTATION_TARGETS="scripts/check-demo.sh tests/test-check-demo.sh" \
  SH_MUTATION_TEST_CMD="sh tests/test-check-demo.sh" sh scripts/run-mutation.sh >/dev/null 2>&1) || true
tafter="$(cat "$W/tests/test-check-demo.sh")"
[ "$tbefore" = "$tafter" ] && pass "test file untouched" || fail "the runner mutated a test file"
rm -rf "$W"

echo "---- test-posix-sh-run-mutation: PASS=$PASS FAIL=$FAIL ----"
[ "$FAIL" -eq 0 ]
