#!/bin/sh
# tests/test-check-third-party-notices.sh — core/scripts/check-third-party-notices.sh の挙動テスト
#
# 検証する性質:
#   1. 設定なし（TPN_BUNDLED_ASSET 未設定）-> 資産チェックは skip(pass)
#   2. 資産あり + 必須文字列あり -> pass
#   3. 資産あり + 必須文字列欠落 -> fail(exit 1)
#   4. 資産あり + 表記ファイル欠落 -> fail(exit 1)
#   5. CDN 参照禁止: 該当があれば fail
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-third-party-notices.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

D="$(mktemp -d)"; git -C "$D" init -q; mkdir -p "$D/scripts"
cp "$SCRIPT" "$D/scripts/check-third-party-notices.sh"
# env で設定を渡す run（cd して相対パスで実行）
run() { OUT="$(cd "$D" && env "$@" sh scripts/check-third-party-notices.sh 2>&1)" && RC=0 || RC=$?; }

echo "property 1: no config -> asset check skipped (pass)"
run
[ "$RC" -eq 0 ] && pass "no-config exit 0" || fail "expected 0, got $RC: $OUT"

printf 'bundled mermaid\n' > "$D/asset.js"

echo "property 2: asset present + required string present -> pass"
printf 'This product bundles Mermaid (MIT).\n' > "$D/THIRD_PARTY_NOTICES.md"
run TPN_BUNDLED_ASSET=asset.js TPN_REQUIRED_STRINGS=Mermaid
[ "$RC" -eq 0 ] && pass "string present exit 0" || fail "expected 0, got $RC: $OUT"

echo "property 3: asset present + required string missing -> fail"
printf 'no attribution here\n' > "$D/THIRD_PARTY_NOTICES.md"
run TPN_BUNDLED_ASSET=asset.js TPN_REQUIRED_STRINGS=Mermaid
[ "$RC" -eq 1 ] && pass "missing string exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'missing required notice string' && pass "reports the missing string" || fail "no message: $OUT"

echo "property 4: asset present + notices file missing -> fail"
rm -f "$D/THIRD_PARTY_NOTICES.md"
run TPN_BUNDLED_ASSET=asset.js TPN_REQUIRED_STRINGS=Mermaid
[ "$RC" -eq 1 ] && pass "missing notices file exit 1" || fail "expected 1, got $RC: $OUT"

echo "property 5: a forbidden CDN reference is rejected"
mkdir -p "$D/src"; printf '<script src="https://unpkg.com/x"></script>\n' > "$D/src/index.html"
run TPN_CDN_SCAN_PATHS=src
[ "$RC" -eq 1 ] && pass "CDN ref exit 1" || fail "expected 1, got $RC: $OUT"

rm -rf "$D"
echo ""
echo "check-third-party-notices tests: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
