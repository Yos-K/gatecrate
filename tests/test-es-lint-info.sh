#!/bin/sh
# tests/test-es-lint-info.sh — core/scripts/es-lint-info.sh の挙動テスト
#
# 文脈: es-lint は「文法（型・許可エッジ）」を保証するが「情報の中身」は見ない。だがESが分析に耐えるには、
# kawasimaドメイン記述ミニ言語の4層（lexicon/syntax/semantics/pragmatics）を満たす必要がある。これを
# プロンプトに置くとAIは埋め残すので、es-lint-info が機械強制する。本テストは「情報が欠けたモデルを必ず
# 指摘し、フラグ/コードの臭いを警告し、完全なモデルは通す」を回帰固定する。
#
# 検証する性質:
#   1. 情報完全なモデル -> exit 0
#   2. payloadのないイベント -> R1 ERROR(exit 1)
#   3. fields/statesのない集約 -> R2 ERROR(exit 1)
#   4. in/out/decideのないポリシー -> R3 ERROR(exit 1)
#   5. フラグ/コード名 -> R5 warn（exit 0・ブロックしない）
#   6. 定義のない in を読むポリシー -> R6 warn（exit 0）
#   7. 複合decideだが述語未定義 -> R7 warn
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/es-lint-info.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
D="$(mktemp -d)"; trap 'rm -rf "$D"' EXIT
run() { OUT="$(sh "$SCRIPT" "$1" 2>&1)" && RC=0 || RC=$?; }

echo "property 1: an information-complete model passes (exit 0)"
cat > "$D/ok.es" <<'EOF'
N c command やる | in=x | out=A|B | decide="xならA"
N a aggregate 集約X | fields=x:制約あり
N e event 起きた | fields=x:制約あり
EOF
run "$D/ok.es"
[ "$RC" -eq 0 ] && pass "complete -> 0" || fail "expected 0, got $RC: $OUT"

echo "property 2: event without payload -> R1 ERROR(1)"
printf 'N e event 起きた\n' > "$D/nopay.es"
run "$D/nopay.es"
[ "$RC" -eq 1 ] && pass "no payload -> 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'R1' && pass "names R1" || fail "no R1: $OUT"

echo "property 3: aggregate without fields/states -> R2 ERROR(1)"
printf 'N a aggregate 集約 | invariant=なんか\n' > "$D/noagg.es"
run "$D/noagg.es"
[ "$RC" -eq 1 ] && pass "no fields/states -> 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'R2' && pass "names R2" || fail "no R2: $OUT"

echo "property 4: policy without in/out/decide -> R3 ERROR(1)"
printf 'N p policy 判定\n' > "$D/nopol.es"
run "$D/nopol.es"
[ "$RC" -eq 1 ] && pass "no in/out/decide -> 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'R3' && pass "names R3" || fail "no R3: $OUT"

echo "property 5: flag/code name -> R5 warn (does not block, exit 0)"
printf 'N a aggregate 集約 | fields=上限フラグ:有無\n' > "$D/smell.es"
run "$D/smell.es"
[ "$RC" -eq 0 ] && pass "smell is warn -> 0" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'R5' && pass "names R5 smell" || fail "no R5: $OUT"

echo "property 6: policy reading an undefined term -> R6 warn (exit 0)"
printf 'N p policy 判定 | in=未定義語 | out=A|B | decide="x"\n' > "$D/dangle.es"
run "$D/dangle.es"
[ "$RC" -eq 0 ] && pass "dangling reads is warn -> 0" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'R6' && pass "names R6" || fail "no R6: $OUT"

echo "property 7: compound decide without behaviors -> R7 warn"
cat > "$D/r7.es" <<'EOF'
N p policy 判定 | in=x | out=A|B | decide="xかつyならA"
N a aggregate 集約 | fields=x:c; y:c
EOF
run "$D/r7.es"
printf '%s\n' "$OUT" | grep -q 'R7' && pass "names R7" || fail "no R7: $OUT"

echo "property 8: becomes= without a 'なぜ' (reason) -> R8 warn"
printf 'N c command やる | becomes=c2 | 受付に純化\n' > "$D/r8.es"
run "$D/r8.es"
[ "$RC" -eq 0 ] && pass "R8 is warn (does not block)" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'R8' && pass "names R8 for missing reason" || fail "no R8: $OUT"

echo "property 8b: becomes= WITH a 'なぜ' -> no R8"
printf 'N c command やる | becomes=c2 | 受付に純化。なぜ: 検証が散在し漏れるため\n' > "$D/r8b.es"
run "$D/r8b.es"
printf '%s\n' "$OUT" | grep -q 'R8' && fail "R8 should not fire when なぜ present: $OUT" || pass "no R8 when reason present"

echo "property 9: an oversized single .es (>40 nodes) -> R9 warn (slice by BC)"
{ i=0; while [ "$i" -lt 45 ]; do printf 'N e%s event 起きた%s | fields=x:制約\n' "$i" "$i"; i=$((i+1)); done; } > "$D/big.es"
run "$D/big.es"
printf '%s\n' "$OUT" | grep -q 'R9' && pass "names R9 for oversized diagram" || fail "no R9: $OUT"
printf 'N e1 event 小さい | fields=x:制約\n' > "$D/small.es"
run "$D/small.es"
printf '%s\n' "$OUT" | grep -q 'R9' && fail "R9 should not fire on small model: $OUT" || pass "no R9 on small model"

echo "property 10: a query/technical step modeled as an event -> R10 warn (not a domain event)"
printf 'N e event 残量が照会された | fields=x:制約\nN e2 event 排他ロックが取得された | fields=x:制約\n' > "$D/nondomain.es"
run "$D/nondomain.es"
printf '%s\n' "$OUT" | grep -q 'R10' && pass "names R10 for query/lock event" || fail "no R10: $OUT"
echo "property 10b: a genuine domain event -> no R10"
printf 'N e event チャージが確定した | fields=x:制約\n' > "$D/domainevt.es"
run "$D/domainevt.es"
printf '%s\n' "$OUT" | grep -q 'R10' && fail "R10 false positive on domain event: $OUT" || pass "no R10 on genuine domain event"

echo "property 11: policy edge when= must correspond to an out= alternative (or 常時) — R11"
cat > "$D/r11.es" <<'EOF'
N pol_a policy 判定する | in=x | out=可|不可 | decide="xなら可" | role=r。
N cmd_a command 実行する | in=x | out=y | role=r。
N pol_b policy 常時判定 | in=x | out=提案 | decide="常に提案" | role=r。
N cmd_b command 提案する | in=x | out=y | role=r。
E pol_a issues cmd_a | when=承認済み
E pol_b issues cmd_b | when=常時（結果を添える）
EOF
run "$D/r11.es"
printf '%s\n' "$OUT" | grep -q 'R11.*pol_a' && pass "R11 fires: when=承認済み is not an out alternative" || fail "no R11 for pol_a: $OUT"
printf '%s\n' "$OUT" | grep -q 'R11.*pol_b' && fail "R11 false positive on 常時: $OUT" || pass "常時 is accepted"
cat > "$D/r11ok.es" <<'EOF'
N pol_c policy 判定する | in=x | out=可|不可 | decide="xなら可" | role=r。
N cmd_c command 実行する | in=x | out=y | role=r。
E pol_c issues cmd_c | when=可（xが揃った）
EOF
run "$D/r11ok.es"
printf '%s\n' "$OUT" | grep -q 'R11' && fail "R11 false positive when when contains an out alt: $OUT" || pass "when containing an out alternative passes"

echo "property 11b: policy edge without when= -> R11 warn (常時なら明記)"
cat > "$D/r11n.es" <<'EOF'
N pol_d policy 判定する | in=x | out=可|不可 | decide="xなら可" | role=r。
N cmd_d command 実行する | in=x | out=y | role=r。
E pol_d issues cmd_d
EOF
run "$D/r11n.es"
printf '%s\n' "$OUT" | grep -q 'R11' && pass "missing when= flagged" || fail "no R11 for missing when: $OUT"

echo "property 12: transition from/first-to must be declared states — R12"
cat > "$D/r12.es" <<'EOF'
N agg_a aggregate 決済 | states=受信|与信済 | transitions=与信する:受信->与信済|与信失敗; 幽霊:未宣言->与信済 | invariant=遷移は定義のみ | role=r。
EOF
run "$D/r12.es"
printf '%s\n' "$OUT" | grep -q 'R12.*未宣言' && pass "R12 fires: undeclared from-state named" || fail "no R12: $OUT"
printf '%s\n' "$OUT" | grep -q 'R12.*与信失敗' && fail "R12 false positive on failure-outcome alternative: $OUT" || pass "to|fail alternative is exempt"

echo "---- es-lint-info: PASS=$PASS FAIL=$FAIL ----"
[ "$FAIL" -eq 0 ]
