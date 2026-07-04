#!/bin/sh
# tests/test-sync-check.sh — scripts/sync-check.sh の挙動テスト（issue #28 回帰防止）
#
# 検証する性質:
#   1. 部分採用の消費者で、採用済みファイルがドリフト0なら exit 0（未採用は情報扱い・誤検知しない）
#   2. 採用済みファイルが kit master と差分なら exit 1 で [UPDATED] を報告する
#   3. consumed_scripts で宣言したのに消費側に無いファイルは exit 1 で [MISSING] を報告する
#
# 一時 consumer ディレクトリを作り、実物の scripts/sync-check.sh を実行して終了コードと出力を検証する。
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SYNC_CHECK="$ROOT/scripts/sync-check.sh"
CORE_SAMPLE="$ROOT/core/scripts/check-conventional-title.sh"  # 採用される core スクリプトの実物
MUT_SAMPLE="$ROOT/adapters/android-jvm/scripts/run-mutation-tests.sh"  # 別 kit スクリプトを source する実物
PASS=0
FAIL=0

fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

# run_check <consumer_dir> -> stdout を $OUT、終了コードを $RC に格納
run_check() {
  OUT="$(sh "$SYNC_CHECK" "$1" 2>&1)" && RC=0 || RC=$?
}

# ---- ケース1: 部分採用・ドリフト0 → exit 0、未採用は情報扱い ----
echo "case 1: partial adoption, no drift -> exit 0, unadopted are informational"
C1="$(mktemp -d)"
mkdir -p "$C1/scripts"
cp "$CORE_SAMPLE" "$C1/scripts/check-conventional-title.sh"   # 1本だけ採用（byte 一致）
run_check "$C1"
[ "$RC" -eq 0 ] && pass "exit 0" || fail "expected exit 0, got $RC"
printf '%s\n' "$OUT" | grep -q "ドリフトはありません" && pass "reports diff-zero" || fail "missing diff-zero message"
printf '%s\n' "$OUT" | grep -q "未採用の任意スクリプト" && pass "unadopted shown as info" || fail "missing unadopted-info line"
printf '%s\n' "$OUT" | grep -q "\[UPDATED\]" && fail "should not report UPDATED" || pass "no false UPDATED"
rm -rf "$C1"

# ---- ケース2: 採用済みファイルにドリフト → exit 1, [UPDATED] ----
echo "case 2: adopted file drifts -> exit 1, [UPDATED]"
C2="$(mktemp -d)"
mkdir -p "$C2/scripts"
cp "$CORE_SAMPLE" "$C2/scripts/check-conventional-title.sh"
printf '\n# local drift\n' >> "$C2/scripts/check-conventional-title.sh"  # 改変してドリフトを作る
run_check "$C2"
[ "$RC" -eq 1 ] && pass "exit 1" || fail "expected exit 1, got $RC"
printf '%s\n' "$OUT" | grep -q "\[UPDATED\] scripts/check-conventional-title.sh" \
  && pass "reports UPDATED for the drifted file" || fail "missing UPDATED report"
rm -rf "$C2"

# ---- ケース3: consumed_scripts 宣言済みだが消費側に無い → exit 1, [MISSING] ----
echo "case 3: consumed_scripts declares a file absent in scripts/ -> exit 1, [MISSING]"
C3="$(mktemp -d)"
mkdir -p "$C3/scripts"
cat > "$C3/sync-manifest.yaml" <<'EOF'
harness_kit_version: "v0.0.0-test"
consumed_scripts:
  - scripts/check-conventional-title.sh
  - scripts/run-mutation-tests.sh
EOF
cp "$CORE_SAMPLE" "$C3/scripts/check-conventional-title.sh"   # 1本はある / run-mutation-tests.sh は無い
run_check "$C3"
[ "$RC" -eq 1 ] && pass "exit 1" || fail "expected exit 1, got $RC"
printf '%s\n' "$OUT" | grep -q "\[MISSING\] scripts/run-mutation-tests.sh" \
  && pass "reports MISSING for declared-but-absent file" || fail "missing MISSING report"
printf '%s\n' "$OUT" | grep -q "opt-in 宣言" && pass "uses consumed_scripts opt-in source" || fail "did not use opt-in source"
rm -rf "$C3"

# ---- ケース4: 採用済みスクリプトが source する kit スクリプトが未採用 -> exit 1, [DEP] ----
echo "case 4: adopted script sources an un-adopted kit script -> exit 1, [DEP]"
C4="$(mktemp -d)"
mkdir -p "$C4/scripts"
cat > "$C4/sync-manifest.yaml" <<'EOF'
harness_kit_version: "v0.0.0-test"
consumed_scripts:
  - scripts/run-mutation-tests.sh
EOF
cp "$MUT_SAMPLE" "$C4/scripts/run-mutation-tests.sh"  # 本体はある＆diff-zero。だが source 先の helper は未採用
run_check "$C4"
[ "$RC" -eq 1 ] && pass "exit 1" || fail "expected exit 1, got $RC"
printf '%s\n' "$OUT" | grep -q "\[DEP\] scripts/run-mutation-tests.sh は scripts/android-kotlin-compile.sh" \
  && pass "reports DEP for the un-adopted source dependency" || fail "missing DEP report"
printf '%s\n' "$OUT" | grep -q "\[UPDATED\]" && fail "should not report UPDATED (file is diff-zero)" || pass "no false UPDATED"
rm -rf "$C4"

echo ""
echo "sync-check tests: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
