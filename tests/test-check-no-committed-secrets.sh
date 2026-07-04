#!/bin/sh
# tests/test-check-no-committed-secrets.sh — core/scripts/check-no-committed-secrets.sh の挙動テスト
#
# 検証する性質:
#   1. クリーンな tree -> pass(exit 0)
#   2. tracked な keystore 風ファイル（key.properties / *.jks）-> fail(exit 1)
#   3. tracked テキスト内の PEM 秘密鍵 -> fail(exit 1)
#   4. 深いサブディレクトリの秘密ファイルも検出（:(glob)**）
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-no-committed-secrets.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

# fresh throwaway repo with the gate vendored at scripts/
newrepo() {
  D="$(mktemp -d)"; git -C "$D" init -q
  git -C "$D" config user.email p@p; git -C "$D" config user.name p
  mkdir -p "$D/scripts"; cp "$SCRIPT" "$D/scripts/check-no-committed-secrets.sh"
  printf '#!/bin/sh\necho hi\n' > "$D/ok.sh"
  git -C "$D" add -A >/dev/null 2>&1
}
run() { OUT="$(cd "$D" && sh scripts/check-no-committed-secrets.sh 2>&1)" && RC=0 || RC=$?; }

echo "property 1: a clean tree passes"
newrepo; run
[ "$RC" -eq 0 ] && pass "clean exit 0" || fail "expected 0, got $RC: $OUT"
rm -rf "$D"

echo "property 2: a tracked keystore-like file is rejected"
newrepo
printf 'storePassword=hunter2\n' > "$D/key.properties"; git -C "$D" add -A >/dev/null 2>&1
run
[ "$RC" -eq 1 ] && pass "key.properties exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'key.properties' && pass "names the secret file" || fail "no name: $OUT"
rm -rf "$D"

echo "property 3: PEM private key material in a tracked file is rejected"
newrepo
printf -- '-----BEGIN RSA PRIVATE KEY-----\nx\n-----END RSA PRIVATE KEY-----\n' > "$D/leak.txt"
git -C "$D" add -A >/dev/null 2>&1
run
[ "$RC" -eq 1 ] && pass "PEM material exit 1" || fail "expected 1, got $RC: $OUT"
rm -rf "$D"

echo "property 4: a secret nested in a subdirectory is detected"
newrepo
mkdir -p "$D/app/config"; printf 'x\n' > "$D/app/config/release.jks"
git -C "$D" add -A >/dev/null 2>&1
run
[ "$RC" -eq 1 ] && pass "nested .jks exit 1" || fail "expected 1, got $RC: $OUT"
rm -rf "$D"

echo ""
echo "check-no-committed-secrets tests: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
