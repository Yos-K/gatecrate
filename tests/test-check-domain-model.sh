#!/bin/sh
# tests/test-check-domain-model.sh — core/scripts/check-domain-model.sh の挙動テスト
#
# 文脈（ROADMAP P4・ドメイン学習ループの出口）: 本ゲートは .als ドメインモデルを Alloy で検査し、
# ルール退行を実装より手前で止める＝エージェントが学んだドメイン知識を CI で効かせるループの出口。
# Alloy 実行(java + jar + network)は非決定論なのでテスト対象から外し、決定論な部分——モデル探索、
# advisory/strict 判定、no-models 挙動——を検証する。java 不在は DOMAIN_MODEL_JAVA seam で再現する。
#
# 検証する性質:
#   1. docs/domain/models/*.als を探索し --print が一覧する（既定パス・複数モデル）
#   2. DOMAIN_MODEL_PATHS で探索パスを上書きできる
#   3. .als が無ければ run/print とも exit 0（検査不能を偽失敗にしない）
#   4. 引数指定したモデルが既定パスより優先される
#   5. java 不在は既定で advisory skip（exit 0）
#   6. java 不在でも DOMAIN_MODEL_STRICT=1 なら fail（exit 1・opt-in hard ゲート）
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-domain-model.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

# mk: 一時的な消費者 git リポにスクリプトを vendor し、$W を返す。
mk() {
  W="$(mktemp -d)"
  git -C "$W" init -q
  mkdir -p "$W/scripts"
  cp "$SCRIPT" "$W/scripts/check-domain-model.sh"
  echo "$W"
}
# als <repo> <relpath>: 最小の .als ファイルを作る（中身は探索対象としてのみ使う・Alloy 実行はしない）
als() { mkdir -p "$1/$(dirname "$2")"; printf 'module m\n' > "$1/$2"; }

echo "property 1: discover docs/domain/models/*.als and list via --print"
W=$(mk); als "$W" docs/domain/models/theme.als; als "$W" docs/domain/models/entitlement.als
OUT="$(cd "$W" && sh scripts/check-domain-model.sh --print 2>&1)"
printf '%s\n' "$OUT" | grep -q 'model: docs/domain/models/entitlement.als' && pass "entitlement.als listed" || fail "missing entitlement: $OUT"
printf '%s\n' "$OUT" | grep -q 'model: docs/domain/models/theme.als' && pass "theme.als listed" || fail "missing theme: $OUT"
printf '%s\n' "$OUT" | grep -q 'paths=docs/domain/models' && pass "default path reported" || fail "wrong path line: $OUT"
rm -rf "$W"

echo "property 2: DOMAIN_MODEL_PATHS overrides the search path"
W=$(mk); als "$W" spec/alloy/order.als
OUT="$(cd "$W" && DOMAIN_MODEL_PATHS=spec/alloy sh scripts/check-domain-model.sh --print 2>&1)"
printf '%s\n' "$OUT" | grep -q 'model: spec/alloy/order.als' && pass "custom path discovered" || fail "custom path missed: $OUT"
# 既定パスの .als は対象外（上書きが効いている）
als "$W" docs/domain/models/ignored.als
OUT="$(cd "$W" && DOMAIN_MODEL_PATHS=spec/alloy sh scripts/check-domain-model.sh --print 2>&1)"
printf '%s\n' "$OUT" | grep -q 'ignored.als' && fail "default path leaked despite override: $OUT" || pass "override excludes default path"
rm -rf "$W"

echo "property 3: no .als models -> exit 0 (run and print), not a false failure"
W=$(mk)
OUT="$(cd "$W" && sh scripts/check-domain-model.sh --print 2>&1)"
printf '%s\n' "$OUT" | grep -q '(no .als models found)' && pass "print reports no models" || fail "print no-models text: $OUT"
OUT="$(cd "$W" && sh scripts/check-domain-model.sh 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 0 ] && pass "run exits 0 with no models" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'nothing to check' && pass "run reports nothing to check" || fail "no nothing-to-check msg: $OUT"
rm -rf "$W"

echo "property 4: explicit model args override the configured paths"
W=$(mk); als "$W" custom/a.als
OUT="$(cd "$W" && DOMAIN_MODEL_PATHS=docs/domain/models sh scripts/check-domain-model.sh --print custom/a.als 2>&1)"
printf '%s\n' "$OUT" | grep -q 'model: custom/a.als' && pass "explicit arg used" || fail "explicit arg ignored: $OUT"
rm -rf "$W"

echo "property 5: java missing -> advisory skip (exit 0) when models exist"
W=$(mk); als "$W" docs/domain/models/theme.als
OUT="$(cd "$W" && DOMAIN_MODEL_JAVA=__nojava__ sh scripts/check-domain-model.sh 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 0 ] && pass "advisory skip exits 0" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -qi 'skipping (advisory' && pass "reports advisory skip" || fail "no advisory msg: $OUT"
rm -rf "$W"

echo "property 6: java missing + DOMAIN_MODEL_STRICT=1 -> fail (exit 1)"
W=$(mk); als "$W" docs/domain/models/theme.als
OUT="$(cd "$W" && DOMAIN_MODEL_JAVA=__nojava__ DOMAIN_MODEL_STRICT=1 sh scripts/check-domain-model.sh 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 1 ] && pass "strict mode exits 1 on missing java" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -qi 'failing' && pass "reports strict failure" || fail "no strict-fail msg: $OUT"
# strict でもモデルが無ければ no-models が先に効いて exit 0（誤って落とさない）
W2=$(mk)
OUT="$(cd "$W2" && DOMAIN_MODEL_JAVA=__nojava__ DOMAIN_MODEL_STRICT=1 sh scripts/check-domain-model.sh 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 0 ] && pass "strict + no models still exits 0" || fail "strict no-models expected 0, got $RC: $OUT"
rm -rf "$W" "$W2"

echo ""
echo "check-domain-model tests: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
