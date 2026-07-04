#!/bin/sh
# tests/test-doc-currency.sh — core/scripts/check-doc-currency.sh の挙動テスト
#
# 文脈（2026-06-14 ROI 自己評価で検出した consolidate-candidate）: EN/JA ドキュメントは
# X.md + X.ja.md の対で、正しさが手作業同期に依存しドリフトする。本ゲートは「対の片側だけを
# 変更したら相方が陳腐化」を機械検知する。
#
# 検証する性質:
#   1. 対の片側(EN)だけ変更 -> STALE で exit 1（相方 JA が陳腐化）
#   2. 対の両側を変更 -> pass（exit 0）
#   3. 孤立 doc（.ja.md の相方なし）は対象外＝変更しても落とさない
#   4. base ref が解決できない場合は skip（exit 0・偽陽性を出さない）
#   5. DOC_CURRENCY_SKIP=1 で明示スキップ（exit 0）
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-doc-currency.sh"
PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

# 一時 consumer repo を作り、probe と同じ消費モデル（scripts/ にコピー）で配置する。
W="$(mktemp -d)"
git -C "$W" init -q
git -C "$W" config user.email t@t; git -C "$W" config user.name t
mkdir -p "$W/scripts" "$W/docs"
cp "$SCRIPT" "$W/scripts/check-doc-currency.sh"
# base コミット: 同期した対 + 孤立 doc
printf 'EN v1\n' > "$W/docs/guide.md"
printf 'JA v1\n' > "$W/docs/guide.ja.md"
printf 'solo\n'  > "$W/docs/notes.md"          # 相方 .ja.md なし＝対象外
git -C "$W" add -A; git -C "$W" commit -qm base
BASE="$(git -C "$W" rev-parse HEAD)"

run() { OUT="$(cd "$W" && DOC_CURRENCY_BASE="$1" sh scripts/check-doc-currency.sh 2>&1)" && RC=0 || RC=$?; }

# ---- 性質1: 片側(EN)だけ変更 -> STALE exit 1 ----
echo "property 1: editing only the EN side of a pair -> STALE (exit 1)"
printf 'EN v2\n' > "$W/docs/guide.md"
printf 'solo v2\n' > "$W/docs/notes.md"   # 孤立 doc も変更（性質3 用）
git -C "$W" commit -qam "edit EN only"
run "$BASE"
[ "$RC" -eq 1 ] && pass "exit 1 on one-sided edit" || fail "expected exit 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q "guide.ja.md was not" && pass "names the stale JA sibling" || fail "no stale JA message: $OUT"

# ---- 性質3: 孤立 doc は対象外（上で notes.md を変更したが落ちない理由＝対が無い） ----
echo "property 3: a lone doc with no .ja.md sibling is never flagged"
printf '%s\n' "$OUT" | grep -q "notes" && fail "lone doc wrongly flagged: $OUT" || pass "lone doc ignored"

# ---- 性質2: 両側を変更 -> pass ----
echo "property 2: editing both sides -> pass (exit 0)"
printf 'JA v2\n' > "$W/docs/guide.ja.md"
git -C "$W" commit -qam "sync JA"
run "$BASE"
[ "$RC" -eq 0 ] && pass "exit 0 when both sides edited" || fail "expected exit 0, got $RC: $OUT"

# ---- 性質4: base ref 解決不能 -> skip(exit 0) ----
echo "property 4: unresolvable base ref -> skip (exit 0)"
run "does-not-exist-ref"
[ "$RC" -eq 0 ] && pass "exit 0 on unresolvable base" || fail "expected exit 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q "skipping" && pass "reports skip" || fail "no skip notice: $OUT"

# ---- 性質5: DOC_CURRENCY_SKIP=1 で明示スキップ ----
echo "property 5: DOC_CURRENCY_SKIP=1 -> skip (exit 0)"
printf 'EN v3\n' > "$W/docs/guide.md"; git -C "$W" commit -qam "EN only again"
OUT="$(cd "$W" && DOC_CURRENCY_BASE="$BASE" DOC_CURRENCY_SKIP=1 sh scripts/check-doc-currency.sh 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 0 ] && pass "exit 0 when skipped" || fail "expected exit 0 with skip, got $RC: $OUT"

# ---- 性質6: 対の片側(JA)だけ削除 -> STALE（一方的な削除/リネームも検知） ----
echo "property 6: deleting only the JA side of a pair -> STALE (exit 1)"
printf 'EN\n' > "$W/docs/del.md"; printf 'JA\n' > "$W/docs/del.ja.md"
git -C "$W" add -A; git -C "$W" commit -qm "add del pair"
BASE2="$(git -C "$W" rev-parse HEAD)"
git -C "$W" rm -q docs/del.ja.md; git -C "$W" commit -qm "delete JA only"
run "$BASE2"
[ "$RC" -eq 1 ] && pass "exit 1 on one-sided deletion" || fail "expected exit 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q "STALE.*del.ja.md" && pass "names the orphaned JA pair" || fail "no deletion message: $OUT"

# ---- 性質7: 既存EN(変更なし)へ JA 翻訳を追加 -> pass（追い付き翻訳は同期扱い） ----
echo "property 7: adding a JA translation to an unchanged EN -> pass (exit 0)"
printf 'solo EN\n' > "$W/docs/lonely.md"
git -C "$W" add -A; git -C "$W" commit -qm "add lonely EN"
BASE3="$(git -C "$W" rev-parse HEAD)"
printf 'lonely JA\n' > "$W/docs/lonely.ja.md"
git -C "$W" add -A; git -C "$W" commit -qm "add JA translation only"
run "$BASE3"
[ "$RC" -eq 0 ] && pass "exit 0 when adding a translation to an unchanged EN" || fail "expected exit 0, got $RC: $OUT"

rm -rf "$W"
echo ""
echo "doc-currency tests: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
