#!/bin/sh
# tests/test-check-evidence-resolves.sh — core/scripts/check-evidence-resolves.sh の挙動テスト
#
# 文脈: 深さゲート(check-bc-domain)は「evidence セルが非空か」しか見ないので、ソースを読めないエージェントが
# もっともらしい file:method を**捏造**して埋めれば素通りする（実走で観測: TAKT 内の agent が実ファイルにアクセス
# できず `Foo.java:validateAccountCd()` 等の実在しないメソッドを書いてゲートを通した）。本ゲートは evidence の
# file:line / file:method 参照が**実コードに解決するか**を機械検証し、捏造を弾く。深さ(check-bc-domain)と真実性
# (本ゲート)で対を成す。
#
# 検証する性質:
#   1. 全 evidence が解決（file 実在 ∧ 行が範囲内 / メソッドが実在）-> pass(exit 0)
#   2. 実在しないメソッド参照（捏造）-> FAIL(exit 1) で名指し
#   3. 実在しないファイル参照 -> FAIL(exit 1)
#   4. 行番号がファイル行数超過 -> FAIL(exit 1)
#   5. file 参照を1つも含まない evidence セル -> FAIL（解決可能な参照が必要）
#   6. ファイル名のみ（locator 無し）で実在 -> pass
#   7. 解決先は EVIDENCE_CODE_ROOT で指定
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-evidence-resolves.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
D="$(mktemp -d)"; trap 'rm -rf "$D"' EXIT

# フィクスチャのコードベース
mkdir -p "$D/code/src"
{ i=1; while [ "$i" -le 50 ]; do echo "line$i"; i=$((i+1)); done; } > "$D/code/src/Foo.java"
# Foo.java に実在するメソッドを仕込む
sed -i.x '10s/.*/    public void validateAlphaNumericExact() {}/' "$D/code/src/Foo.java" && rm -f "$D/code/src/Foo.java.x"
echo "class Bar {}" > "$D/code/src/Bar.java"
run() { OUT="$(EVIDENCE_CODE_ROOT="$D/code" sh "$SCRIPT" "$1" 2>&1)" && RC=0 || RC=$?; }

echo "property 1: all evidence resolves -> pass"
cat > "$D/good.md" <<'EOF'
## 用語集
| 用語 | 定義 | 不変条件 | evidence |
|---|---|---|---|
| A | d | i | Foo.java:10 |
| B | d | i | Foo.java:validateAlphaNumericExact() |
| C | d | i | Bar.java |
EOF
run "$D/good.md"
[ "$RC" -eq 0 ] && pass "all resolve -> exit 0" || fail "expected 0, got $RC: $OUT"

echo "property 2: fabricated (nonexistent) method -> fail and name it"
cat > "$D/fakemethod.md" <<'EOF'
## 用語集
| 用語 | 定義 | 不変条件 | evidence |
|---|---|---|---|
| A | d | i | Foo.java:validateAccountCd() |
| B | d | i | Foo.java:10 |
EOF
run "$D/fakemethod.md"
[ "$RC" -eq 1 ] && pass "fake method -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'validateAccountCd' && pass "names the fabricated ref" || fail "not named: $OUT"

echo "property 3: nonexistent file -> fail"
cat > "$D/fakefile.md" <<'EOF'
## 用語集
| 用語 | 定義 | 不変条件 | evidence |
|---|---|---|---|
| A | d | i | Ghost.java:5 |
EOF
run "$D/fakefile.md"
[ "$RC" -eq 1 ] && pass "ghost file -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'Ghost.java' && pass "names ghost file" || fail "not named: $OUT"

echo "property 4: line number beyond file length -> fail"
cat > "$D/badline.md" <<'EOF'
## 用語集
| 用語 | 定義 | 不変条件 | evidence |
|---|---|---|---|
| A | d | i | Foo.java:9999 |
EOF
run "$D/badline.md"
[ "$RC" -eq 1 ] && pass "line 9999 > 50 -> exit 1" || fail "expected 1, got $RC: $OUT"

echo "property 5: evidence cell with no file reference -> fail"
cat > "$D/noref.md" <<'EOF'
## 用語集
| 用語 | 定義 | 不変条件 | evidence |
|---|---|---|---|
| A | d | i | 業界標準・要確認 |
EOF
run "$D/noref.md"
[ "$RC" -eq 1 ] && pass "no file ref -> exit 1" || fail "expected 1, got $RC: $OUT"

echo "property 6: filename only (no locator), file exists -> pass"
cat > "$D/fileonly.md" <<'EOF'
## 用語集
| 用語 | 定義 | 不変条件 | evidence |
|---|---|---|---|
| A | d | i | Foo.java |
| B | d | i | Bar.java |
EOF
run "$D/fileonly.md"
[ "$RC" -eq 0 ] && pass "filename only resolves -> exit 0" || fail "expected 0, got $RC: $OUT"

echo "property 7: resolution root honored (wrong root -> unresolved)"
OUT="$(EVIDENCE_CODE_ROOT="$D/empty" sh "$SCRIPT" "$D/good.md" 2>&1)" && RC=0 || RC=$?
[ "$RC" -ne 0 ] && pass "wrong root -> non-zero" || fail "expected non-zero with empty root: $OUT"

echo "---- test-check-evidence-resolves: PASS=$PASS FAIL=$FAIL ----"
[ "$FAIL" -eq 0 ]
