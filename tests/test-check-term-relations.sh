#!/bin/sh
# tests/test-check-term-relations.sh — core/scripts/check-term-relations.sh の挙動テスト
#
# 文脈: 深さゲート(check-bc-domain)は用語ごとの不変条件しか強制しないため、**用語間のルール**（包含・多重度・ペア・
# 整合・コンテキスト間同一性）が抜ける（実走で観測: TAKT 生成の BC 文書に用語間ルールの節が無かった）。ゲートが
# 強制しない次元は agent が手を抜く。本ゲートは「用語間のルール」節と、**型付き(包含/多重度/ペア/整合/同一性/依存)
# ＋evidence** のルールを規定数以上含むことを機械強制する。
#
# 検証する性質:
#   1. 用語間ルール節 + 型付き＋evidence のルール >= N -> pass(exit 0)
#   2. 用語間ルール節が無い -> FAIL(exit 1)
#   3. 節はあるがルール数が閾値未満 -> FAIL(exit 1)
#   4. 型キーワードはあるが evidence が無い行 -> 数えない -> 閾値未満で FAIL
#   5. evidence はあるが型キーワードが無い行 -> 数えない
#   6. 閾値は TERM_REL_MIN で可変
#   7. 英語見出し/キーワード(relationship/pair/multiplicity/identity)でも通る
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-term-relations.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
D="$(mktemp -d)"; trap 'rm -rf "$D"' EXIT
run() { OUT="$(TERM_REL_MIN="${2:-3}" sh "$SCRIPT" "$1" 2>&1)" && RC=0 || RC=$?; }

echo "property 1: relations section with >=3 typed+evidence rules -> pass"
cat > "$D/good.md" <<'EOF'
## 用語集
| 用語 | 定義 | 不変条件 | evidence |
|---|---|---|---|
| A | d | i | Foo.java:1 |
## 用語間のルール
- ペア: ALIAS_AUID は ALIAS_KBN を伴う（区分を先に検証）。Foo.java:905
- 整合: 応答 SEQUENCE == 要求 SEQUENCE。Foo.java:842
- 多重度: 子機回線 [1..4]。Foo.java:1060
- 同一性: 加入者CD = SPS CustomerId。Bar.java:137
## hotspot
h
EOF
run "$D/good.md" 3
[ "$RC" -eq 0 ] && pass "4 typed rules >=3 -> exit 0" || fail "expected 0, got $RC: $OUT"

echo "property 2: no relations section -> fail"
cat > "$D/nosec.md" <<'EOF'
## 用語集
| 用語 | 定義 | 不変条件 | evidence |
|---|---|---|---|
| A | d | i | Foo.java:1 |
## hotspot
h
EOF
run "$D/nosec.md" 3
[ "$RC" -eq 1 ] && pass "no section -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -qiE '用語間|relation' && pass "names missing section" || fail "no msg: $OUT"

echo "property 3: too few rules -> fail"
run "$D/good.md" 9
[ "$RC" -eq 1 ] && pass "4<9 -> exit 1" || fail "expected 1, got $RC: $OUT"

echo "property 4: typed but no evidence -> not counted"
cat > "$D/noev.md" <<'EOF'
## 用語間のルール
- ペア: ALIAS_AUID は ALIAS_KBN を伴う（evidence無し）
- 整合: 応答 seq == 要求 seq（evidence無し）
- 多重度: 子機 [1..4]（evidence無し）
EOF
run "$D/noev.md" 1
[ "$RC" -eq 1 ] && pass "no-evidence rules don't count -> exit 1" || fail "expected 1, got $RC: $OUT"

echo "property 5: evidence but no type keyword -> not counted"
cat > "$D/notype.md" <<'EOF'
## 用語間のルール
- 加入者CDを使う Foo.java:10
- 何かの説明 Bar.java:20
EOF
run "$D/notype.md" 1
[ "$RC" -eq 1 ] && pass "no-type rules don't count -> exit 1" || fail "expected 1, got $RC: $OUT"

echo "property 6: threshold configurable"
run "$D/good.md" 4
[ "$RC" -eq 0 ] && pass "4>=4 -> exit 0" || fail "expected 0, got $RC: $OUT"

echo "property 7: english headings/keywords work"
cat > "$D/en.md" <<'EOF'
## Term relationships
- pair: ALIAS_AUID requires ALIAS_KBN. Foo.java:905
- consistency: response seq == request seq. Foo.java:842
- multiplicity: child line [1..4]. Foo.java:1060
EOF
run "$D/en.md" 3
[ "$RC" -eq 0 ] && pass "english -> exit 0" || fail "expected 0, got $RC: $OUT"

echo "---- test-check-term-relations: PASS=$PASS FAIL=$FAIL ----"
[ "$FAIL" -eq 0 ]
