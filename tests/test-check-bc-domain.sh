#!/bin/sh
# tests/test-check-bc-domain.sh — core/scripts/check-bc-domain.sh の挙動テスト
#
# 文脈: レガシーのドメイン知識抽出は、エージェントに任せると「深さ」がぶれる（浅すぎ/無限に掘る）。スキルの注意書きでは
# 制御できない。本ゲートは「1つのBCのドメイン知識文書が、規定の深さ（用語数・各用語の定義/不変条件/evidence が埋まって
# いる・ユースケース流れ・hotspot がある）に達しているか」を機械判定し、TAKT の command ゲートとして深掘りを強制する。
#
# 検証する性質:
#   1. 規定数以上の用語＋各用語に定義/不変条件/evidence＋UC節＋hotspot節 -> pass(exit 0)
#   2. 用語数が閾値未満 -> FAIL(exit 1) で不足を名指し
#   3. 一部の用語で不変条件 or evidence が空（"-"/"未"等含む）-> その行は数えない -> 閾値未満で FAIL
#   4. ユースケース/流れ の節が無い -> FAIL
#   5. hotspot 節が無い -> FAIL
#   6. 閾値は BC_MIN_TERMS で可変
#   7. 英語見出し(term/invariant/evidence/use case/hotspot)でも通る
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-bc-domain.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
D="$(mktemp -d)"; trap 'rm -rf "$D"' EXIT
run() { OUT="$(BC_MIN_TERMS="${2:-3}" sh "$SCRIPT" "$1" 2>&1)" && RC=0 || RC=$?; }

# 完全な BC 文書（用語3・全セル埋・UC・hotspot）
cat > "$D/good.md" <<'EOF'
# BC: 課金実行
## 用語集
| 用語 | 定義 | 不変条件 | evidence |
|---|---|---|---|
| USERID | ユーザID | 長さ4..32 ∧ isValidId | Foo.java:862 |
| ACCOUNTCD | アカウントCD | 長さ=8 ∧ 英数 | Foo.java:1032 |
| OPTFLAG | オプション | ∈{01,02} | Foo.java:1046 |
## ユースケースと流れ
1. リクエスト検証 -> 2. 外部連携 -> 3. 課金
## hotspot
- なぜ8桁かは要確認
EOF

echo "property 1: complete BC doc (>=3 terms, all cells, UC, hotspot) -> pass"
run "$D/good.md" 3
[ "$RC" -eq 0 ] && pass "complete -> exit 0" || fail "expected 0, got $RC: $OUT"

echo "property 2: too few terms -> fail"
run "$D/good.md" 5
[ "$RC" -eq 1 ] && pass "3<5 -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -qiE '用語|term' && pass "names the term shortfall" || fail "no shortfall msg: $OUT"

echo "property 3: rows with empty invariant/evidence don't count"
cat > "$D/holes.md" <<'EOF'
## 用語集
| 用語 | 定義 | 不変条件 | evidence |
|---|---|---|---|
| USERID | ユーザID | 長さ4..32 | Foo.java:862 |
| X | 定義 | - | Foo.java:1 |
| Y | 定義 | 不変条件 |  |
## ユースケース
flow
## hotspot
h
EOF
run "$D/holes.md" 3
[ "$RC" -eq 1 ] && pass "only 1 valid term <3 -> exit 1" || fail "expected 1, got $RC: $OUT"

echo "property 4: missing use-case section -> fail"
cat > "$D/nouc.md" <<'EOF'
## 用語集
| 用語 | 定義 | 不変条件 | evidence |
|---|---|---|---|
| A | d | i | e:1 |
| B | d | i | e:2 |
| C | d | i | e:3 |
## hotspot
h
EOF
run "$D/nouc.md" 3
[ "$RC" -eq 1 ] && pass "no use-case -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -qiE 'ユースケース|流れ|use.?case|flow' && pass "names missing use-case" || fail "no uc msg: $OUT"

echo "property 5: missing hotspot section -> fail"
cat > "$D/nohot.md" <<'EOF'
## 用語集
| 用語 | 定義 | 不変条件 | evidence |
|---|---|---|---|
| A | d | i | e:1 |
| B | d | i | e:2 |
| C | d | i | e:3 |
## 流れ
flow
EOF
run "$D/nohot.md" 3
[ "$RC" -eq 1 ] && pass "no hotspot -> exit 1" || fail "expected 1, got $RC: $OUT"

echo "property 6: threshold is configurable (BC_MIN_TERMS)"
run "$D/good.md" 2
[ "$RC" -eq 0 ] && pass "3>=2 -> exit 0" || fail "expected 0, got $RC: $OUT"

echo "property 7: english headers/columns work"
cat > "$D/en.md" <<'EOF'
## Glossary
| term | definition | invariant | evidence |
|---|---|---|---|
| A | d | i | e:1 |
| B | d | i | e:2 |
| C | d | i | e:3 |
## Use cases
flow
## Hotspots
h
EOF
run "$D/en.md" 3
[ "$RC" -eq 0 ] && pass "english -> exit 0" || fail "expected 0, got $RC: $OUT"

echo "---- test-check-bc-domain: PASS=$PASS FAIL=$FAIL ----"
[ "$FAIL" -eq 0 ]
