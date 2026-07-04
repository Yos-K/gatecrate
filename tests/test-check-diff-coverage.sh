#!/bin/sh
# tests/test-check-diff-coverage.sh — core/scripts/check-diff-coverage.sh の挙動テスト
#
# 文脈: テストの無いレガシーに絶対カバレッジ floor（coverage>=80）を入れると初日に必ず落ち、ゲートごと外され、
# 安全網は永遠に育たない。diff-coverage はレガシー本体には何も要求せず「このPRで変更/追加した行だけ」に被覆を
# 要求する ratchet 型ゲート。本テストは「変更行が被覆されていなければ reject し、被覆されていれば通す。被覆対象
# でない変更（コメント/docs/報告に現れない行）は分母から外して誤判定しない」を回帰固定する。
#
# 検証する性質:
#   1. 変更行が全て被覆 -> pass(exit 0)
#   2. 変更行の被覆率が floor 未満 -> FAIL(exit 1) で未被覆を file:line で名指し
#   3. 境界（被覆率 == floor）-> pass（>= で通す）
#   4. 被覆対象の変更行が無い（報告に現れない/コードでない）-> pass(exit 0・"nothing to gate")
#   5. floor は DIFF_COVERAGE_THRESHOLD で可変
#   6. git のパス（src/main/kotlin/...）と JaCoCo の package パスを suffix で対応付ける
#   7. 実 git リポの diff から変更行を抽出できる（DIFF_LINES_FILE seam を使わない経路）
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-diff-coverage.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT
TAB="$(printf '\t')"

# 共通 JaCoCo フィクスチャ: com/example/foo/Foo.kt の被覆実態
#   line 3 covered, line 4 missed, line 5 covered, line 9 missed
cat > "$D/jacoco.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<report name="fixture">
  <package name="com/example/foo">
    <sourcefile name="Foo.kt">
      <line nr="3" mi="0" ci="2" mb="0" cb="0"/>
      <line nr="4" mi="2" ci="0" mb="0" cb="0"/>
      <line nr="5" mi="0" ci="1" mb="0" cb="0"/>
      <line nr="9" mi="3" ci="0" mb="0" cb="0"/>
    </sourcefile>
  </package>
</report>
EOF

# run with the DIFF_LINES_FILE seam (path<TAB>nr per line). 第2引数は changed-lines ファイル。
run_seam() {
  OUT="$(COVERAGE_REPORT="$D/jacoco.xml" DIFF_LINES_FILE="$1" \
        DIFF_COVERAGE_THRESHOLD="${2:-80}" sh "$SCRIPT" 2>&1)" && RC=0 || RC=$?
}

echo "property 1: all changed lines covered -> pass"
printf 'src/main/kotlin/com/example/foo/Foo.kt\t3\nsrc/main/kotlin/com/example/foo/Foo.kt\t5\n' > "$D/c1"
run_seam "$D/c1"
[ "$RC" -eq 0 ] && pass "all covered -> exit 0" || fail "expected 0, got $RC: $OUT"

echo "property 2: changed coverage below floor -> fail and name uncovered lines"
printf 'a/Foo.kt\t3\na/Foo.kt\t4\na/Foo.kt\t9\n' | sed 's#a/#src/main/kotlin/com/example/foo/#' > "$D/c2"
run_seam "$D/c2" 80
[ "$RC" -eq 1 ] && pass "33%<80 -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'Foo.kt:4' && pass "names uncovered line 4" || fail "line 4 not named: $OUT"
printf '%s\n' "$OUT" | grep -q 'Foo.kt:9' && pass "names uncovered line 9" || fail "line 9 not named: $OUT"

echo "property 3: boundary (coverage == floor) -> pass"
# changed 3(cov),4(miss) -> 50%; floor 50 -> pass (>=)
printf 'src/main/kotlin/com/example/foo/Foo.kt\t3\nsrc/main/kotlin/com/example/foo/Foo.kt\t4\n' > "$D/c3"
run_seam "$D/c3" 50
[ "$RC" -eq 0 ] && pass "50%>=50 -> exit 0" || fail "expected 0, got $RC: $OUT"

echo "property 4: no instrumented changed lines -> pass (nothing to gate)"
printf 'src/main/kotlin/com/example/foo/Foo.kt\t100\nREADME.md\t12\n' > "$D/c4"
run_seam "$D/c4" 80
[ "$RC" -eq 0 ] && pass "no gateable lines -> exit 0" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -qi 'nothing to gate\|no .*changed' && pass "explains nothing to gate" || fail "no explanation: $OUT"

echo "property 5: floor is configurable"
# changed 3(cov),5(cov),4(miss) -> 66%
printf 'src/main/kotlin/com/example/foo/Foo.kt\t3\nsrc/main/kotlin/com/example/foo/Foo.kt\t5\nsrc/main/kotlin/com/example/foo/Foo.kt\t4\n' > "$D/c5"
run_seam "$D/c5" 60
[ "$RC" -eq 0 ] && pass "66%>=60 -> exit 0" || fail "expected 0, got $RC: $OUT"
run_seam "$D/c5" 80
[ "$RC" -eq 1 ] && pass "66%<80 -> exit 1" || fail "expected 1, got $RC: $OUT"

echo "property 6: git path is matched to jacoco package by suffix"
# 異なる接頭辞（exec/src/main/kotlin/...）でも package suffix com/example/foo/Foo.kt で一致する
printf 'exec/src/main/kotlin/com/example/foo/Foo.kt\t4\n' > "$D/c6"
run_seam "$D/c6" 80
[ "$RC" -eq 1 ] && pass "suffix-matched uncovered -> exit 1" || fail "expected 1, got $RC: $OUT"

echo "property 7: changed lines come from a real git diff (no seam)"
G="$D/repo"
mkdir -p "$G/src/main/kotlin/com/example/foo"
git -C "$G" init -q
git -C "$G" config user.email t@t && git -C "$G" config user.name t
# 初期コミット: Foo.kt の行3-9 を用意（行4を後で「変更」する）
{ i=1; while [ "$i" -le 9 ]; do echo "line$i"; i=$((i+1)); done; } > "$G/src/main/kotlin/com/example/foo/Foo.kt"
git -C "$G" add -A && git -C "$G" commit -qm init
base="$(git -C "$G" rev-parse HEAD)"
# 行4 を変更（未被覆行）-> diff の +行は line4。floor 80 で reject されるはず
{ i=1; while [ "$i" -le 9 ]; do [ "$i" -eq 4 ] && echo "changed4" || echo "line$i"; i=$((i+1)); done; } > "$G/src/main/kotlin/com/example/foo/Foo.kt"
git -C "$G" add -A && git -C "$G" commit -qm change
cp "$D/jacoco.xml" "$G/jacoco.xml"
OUT="$(cd "$G" && COVERAGE_REPORT="$G/jacoco.xml" DIFF_BASE="$base" \
      DIFF_COVERAGE_THRESHOLD=80 sh "$SCRIPT" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 1 ] && pass "real git diff, uncovered line 4 -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'Foo.kt:4' && pass "real diff names line 4" || fail "line 4 not named: $OUT"

echo "property 8: a SINGLE-LINE jacoco report (no newlines between elements) is parsed"
# 回帰固定: 実 jacoco.xml は要素間に改行が無い単一行（751KB 等）。改行前提のパーサ（tr/sed）は分割に失敗する——
# この性質が無いと「複数行 fixture では緑だが実データでは全行 nothing-to-gate」のバグ（実運用の jacoco.xml で露見）を見逃す。
printf '%s' '<?xml version="1.0"?><!DOCTYPE report PUBLIC "-//JACOCO//DTD Report 1.1//EN" "report.dtd"><report name="x"><package name="com/example/foo"><sourcefile name="Foo.kt"><line nr="3" mi="0" ci="2"/><line nr="4" mi="2" ci="0"/></sourcefile></package></report>' > "$D/oneline.xml"
printf 'src/main/kotlin/com/example/foo/Foo.kt\t4\n' > "$D/c8"
OUT="$(COVERAGE_REPORT="$D/oneline.xml" DIFF_LINES_FILE="$D/c8" DIFF_COVERAGE_THRESHOLD=80 sh "$SCRIPT" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 1 ] && pass "single-line xml, uncovered line 4 -> exit 1" || fail "expected 1 (parsed), got $RC: $OUT"
printf '%s\n' "$OUT" | grep -qi 'nothing to gate' && fail "single-line xml parsed as empty (the tr bug)!" || pass "single-line xml is NOT mis-parsed as empty"

echo "property 9: COVERAGE_FORMAT=lcov — rust/typescript/python の被覆報告を消費できる"
# lcov: SF がリポ相対のケース。line3=hit / line4=miss
cat > "$D/cov.lcov" <<'EOF'
TN:
SF:src/lib.rs
DA:3,2
DA:4,0
DA:5,1
end_of_record
EOF
printf 'src/lib.rs\t3\nsrc/lib.rs\t5\n' > "$D/l1"
OUT="$(COVERAGE_REPORT="$D/cov.lcov" COVERAGE_FORMAT=lcov DIFF_LINES_FILE="$D/l1" DIFF_COVERAGE_THRESHOLD=80 sh "$SCRIPT" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 0 ] && pass "lcov all covered -> exit 0" || fail "lcov: expected 0, got $RC: $OUT"
printf 'src/lib.rs\t3\nsrc/lib.rs\t4\n' > "$D/l2"
OUT="$(COVERAGE_REPORT="$D/cov.lcov" COVERAGE_FORMAT=lcov DIFF_LINES_FILE="$D/l2" DIFF_COVERAGE_THRESHOLD=80 sh "$SCRIPT" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 1 ] && pass "lcov 50%<80 -> exit 1" || fail "lcov: expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'lib.rs:4' && pass "lcov names the uncovered line" || fail "lcov line not named: $OUT"

echo "property 9b: lcov の SF が絶対パスでも diff のリポ相対パスと突合できる"
cat > "$D/cov-abs.lcov" <<'EOF'
SF:/home/ci/work/repo/src/app.py
DA:7,0
end_of_record
EOF
printf 'src/app.py\t7\n' > "$D/l3"
OUT="$(COVERAGE_REPORT="$D/cov-abs.lcov" COVERAGE_FORMAT=lcov DIFF_LINES_FILE="$D/l3" DIFF_COVERAGE_THRESHOLD=80 sh "$SCRIPT" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 1 ] && pass "absolute SF matched by suffix; uncovered -> exit 1" || fail "abs SF: expected 1, got $RC: $OUT"

echo "property 10: COVERAGE_FORMAT=gocover — go ネイティブ coverprofile を消費できる"
# ブロック 3-5行=count1（covered）、7-8行=count0（miss）。同一行の重複ブロックは max が勝つ
cat > "$D/coverage.out" <<'EOF'
mode: set
github.com/ex/repo/pkg/svc.go:3.2,5.10 2 1
github.com/ex/repo/pkg/svc.go:7.2,8.4 1 0
github.com/ex/repo/pkg/svc.go:7.2,7.9 1 0
EOF
printf 'pkg/svc.go\t4\n' > "$D/g1"
OUT="$(COVERAGE_REPORT="$D/coverage.out" COVERAGE_FORMAT=gocover DIFF_LINES_FILE="$D/g1" DIFF_COVERAGE_THRESHOLD=80 sh "$SCRIPT" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 0 ] && pass "gocover covered block -> exit 0" || fail "gocover: expected 0, got $RC: $OUT"
printf 'pkg/svc.go\t7\n' > "$D/g2"
OUT="$(COVERAGE_REPORT="$D/coverage.out" COVERAGE_FORMAT=gocover DIFF_LINES_FILE="$D/g2" DIFF_COVERAGE_THRESHOLD=80 sh "$SCRIPT" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 1 ] && pass "gocover uncovered block -> exit 1" || fail "gocover: expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'svc.go:7' && pass "gocover names the uncovered line" || fail "gocover line not named: $OUT"

echo "property 11: 未対応フォーマットは今も明示エラー"
OUT="$(COVERAGE_REPORT="$D/jacoco.xml" COVERAGE_FORMAT=cobertura DIFF_LINES_FILE="$D/c1" sh "$SCRIPT" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 2 ] && pass "unsupported format -> exit 2" || fail "expected 2, got $RC: $OUT"

echo "---- test-check-diff-coverage: PASS=$PASS FAIL=$FAIL ----"
[ "$FAIL" -eq 0 ]
