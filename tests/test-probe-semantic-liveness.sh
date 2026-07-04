#!/bin/sh
# tests/test-probe-semantic-liveness.sh — core/scripts/probe-semantic-liveness.sh の挙動テスト
#
# 文脈: 意味的正しさの最後の砦は refute 工程（第3層が存在と鮮度を強制）だが、「捕まえないレビュアは
# 壊れていても見えない」——probe-gate-liveness が予防ゲートに合成違反を注入するのと同じ死角。第4層は
# **文法ゲートを通過する意味違反**（evidence差替・decide入替・when入替）を決定論注入し、refute 工程が
# それを名指しできるか（ALIVE/DEAD）を機械検証する＝レビュー工程への mutation testing。
#
# 検証する性質:
#   1. retarget-evidence: 先頭2つの evidence 値が入れ替わった変異モデルを出力し、--planted が両 id を列挙
#   2. 変異モデルは es-lint を通過する（文法非可視＝意味違反である、という本質の回帰固定）
#   3. swap-decide: 先頭2 policy/command の decide 値が入れ替わる
#   4. swap-when: 先頭2エッジの when 値が入れ替わる（変異後も es-lint 通過）
#   5. --verify: 検出リストに planted id が有れば ALIVE(exit 0)・無ければ DEAD(exit 1)
#   6. 注入対象が2つ未満 -> exit 2（setup error。偽の ALIVE/DEAD を出さない）
#   7. 決定論: 同一入力から同一変異（座標・乱数・時刻を含まない）
#   8. --list が注入 kind 一覧を出す
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/probe-semantic-liveness.sh"
ESLINT="$ROOT/core/scripts/es-lint.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT

cat > "$D/m.es" <<'EOF'
N act_u   actor    利用者 | role=起点。
N cmd_a   command  受け付ける | in=x | out=受理 | decide="xが正なら受理" | evidence=src/A.java:10 | role=r。
N agg_a   aggregate 注文 | fields=id:一意 | invariant=明細1件以上 | evidence=src/B.java:20 | role=r。
N evt_a   event    受理された | fields=id:一意 | evidence=src/C.java:30 | role=r。
N pol_p   policy   可否を判定 | in=id | out=可|不可 | decide="idが有効なら可" | role=r。
N cmd_b   command  実行する | in=id | out=済 | decide="常に実行" | role=r。
N evt_b   event    実行された | fields=id:一意 | evidence=src/D.java:40 | role=r。
N pol_q   policy   補償を判定 | in=id | out=補償|不要 | decide="失敗なら補償" | role=r。
N cmd_c   command  補償する | in=id | out=済 | role=r。
E act_u  issues  cmd_a
E cmd_a  handles agg_a
E agg_a  emits   evt_a
E evt_a  triggers pol_p
E pol_p  issues  cmd_b | when=可
E cmd_b  handles agg_a
E agg_a  emits   evt_b
E evt_b  triggers pol_q
E pol_q  issues  cmd_c | when=補償
E cmd_c  handles agg_a
EOF

echo "property 8: --list enumerates kinds"
OUT="$(sh "$SCRIPT" --list)"
for k in retarget-evidence swap-decide swap-when; do
  printf '%s\n' "$OUT" | grep -q "$k" && pass "kind $k listed" || fail "kind $k missing: $OUT"
done

echo "property 1: retarget-evidence swaps the first two evidence values; --planted names both nodes"
sh "$SCRIPT" --inject retarget-evidence "$D/m.es" > "$D/mut1.es"
grep -q 'cmd_a.*src/B.java:20' "$D/mut1.es" && grep -q 'agg_a.*src/A.java:10' "$D/mut1.es" \
  && pass "evidence values swapped" || fail "not swapped: $(grep evidence "$D/mut1.es")"
P="$(sh "$SCRIPT" --planted retarget-evidence "$D/m.es")"
printf '%s\n' "$P" | grep -q 'cmd_a' && printf '%s\n' "$P" | grep -q 'agg_a' \
  && pass "planted ids listed" || fail "planted wrong: $P"

echo "property 2: the mutant still passes es-lint (grammar-invisible)"
sh "$ESLINT" "$D/mut1.es" >/dev/null 2>&1 && pass "mutant passes grammar" || fail "mutant caught by grammar (should be semantic-only)"

echo "property 3: swap-decide swaps the first two decide values"
sh "$SCRIPT" --inject swap-decide "$D/m.es" > "$D/mut2.es"
grep -q 'cmd_a.*decide="idが有効なら可"' "$D/mut2.es" && grep -q 'pol_p.*decide="xが正なら受理"' "$D/mut2.es" \
  && pass "decide values swapped" || fail "not swapped: $(grep decide "$D/mut2.es" | head -2)"

echo "property 4: swap-when swaps the first two when values; mutant passes grammar"
sh "$SCRIPT" --inject swap-when "$D/m.es" > "$D/mut3.es"
grep -q 'pol_p.*when=補償' "$D/mut3.es" && grep -q 'pol_q.*when=可' "$D/mut3.es" \
  && pass "when values swapped" || fail "not swapped: $(grep when "$D/mut3.es")"
sh "$ESLINT" "$D/mut3.es" >/dev/null 2>&1 && pass "when-mutant passes grammar" || fail "when-mutant caught by grammar"

echo "property 5: --verify — detection list with a planted id -> ALIVE / without -> DEAD"
printf 'cmd_a\n' > "$D/report-hit.txt"
OUT="$(sh "$SCRIPT" --verify retarget-evidence "$D/m.es" "$D/report-hit.txt" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q 'ALIVE' && pass "hit -> ALIVE" || fail "expected ALIVE/0, got $RC: $OUT"
printf 'evt_b\n' > "$D/report-miss.txt"
OUT="$(sh "$SCRIPT" --verify retarget-evidence "$D/m.es" "$D/report-miss.txt" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q 'DEAD' && pass "miss -> DEAD" || fail "expected DEAD/1, got $RC: $OUT"

echo "property 6: fewer than two eligible items -> setup error (exit 2)"
printf 'N e1 event 起きた | fields=x:制約 | evidence=src/A.java:1 | role=r。\n' > "$D/one.es"
OUT="$(sh "$SCRIPT" --inject retarget-evidence "$D/one.es" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 2 ] && pass "cannot inject -> exit 2 (never a false verdict)" || fail "expected 2, got $RC: $OUT"

echo "property 7: deterministic injection"
sh "$SCRIPT" --inject swap-decide "$D/m.es" > "$D/mut2b.es"
cmp -s "$D/mut2.es" "$D/mut2b.es" && pass "same input -> identical mutant" || fail "mutants differ"

echo "---- test-probe-semantic-liveness: PASS=$PASS FAIL=$FAIL ----"
[ "$FAIL" -eq 0 ]
