#!/bin/sh
# tests/test-check-kit-drift.sh — core/scripts/check-kit-drift.sh の挙動テスト
#
# 文脈（消費可能 sync の不変条件）: consumed_scripts は pin 版のキット原本と byte-identical であるべき。
# 本ガードはそれを再検査する。clone(非決定論)は KIT_DIR seam で偽キット checkout に差し替え、git 非依存に
# 検証する。
#
# 検証する性質:
#   1. 全 consumed が原本一致 -> ok のみ・exit 0
#   2. 1本が改変(drift) -> 既定 advisory(exit 0)・report に DRIFT
#   3. 同上 + --strict -> FAIL(exit 1)
#   4. consumed が宣言されているのにローカル不在 -> DRIFT 扱い
#   5. consumed が kit whitelist に無い -> UNRESOLVED（drift とは区別）
#   6. sync-manifest.yaml が無い -> SKIP(exit 0)
#   7. オフライン等で kit 解決不能（KIT_DIR 不在）-> SKIP(exit 0・--strict でも非致命)
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-kit-drift.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

# 偽キット checkout を作る: sync-manifests/test-adapter.yaml + core/scripts/{foo,bar}.sh
mk_kit() {
  K="$(mktemp -d)"
  mkdir -p "$K/sync-manifests" "$K/core/scripts"
  printf 'sync_target:\n  adapter: test-adapter\n  core_scripts:\n    - core/scripts/foo.sh\n    - core/scripts/bar.sh\n' > "$K/sync-manifests/test-adapter.yaml"
  printf 'echo foo v1\n' > "$K/core/scripts/foo.sh"
  printf 'echo bar v1\n' > "$K/core/scripts/bar.sh"
  echo "$K"
}
# 消費者 git リポを作る: sync-manifest.yaml(pin/adapter/consumed) + scripts/ に vendor
mk_consumer() {
  W="$(mktemp -d)"; git -C "$W" init -q; mkdir -p "$W/scripts"
  cp "$SCRIPT" "$W/scripts/check-kit-drift.sh"
  printf 'gatecrate_version: "v9.9.9"\nadapter: test-adapter\nconsumed_scripts:\n  - scripts/foo.sh\n  - scripts/bar.sh\n' > "$W/sync-manifest.yaml"
  printf 'echo foo v1\n' > "$W/scripts/foo.sh"
  printf 'echo bar v1\n' > "$W/scripts/bar.sh"
  echo "$W"
}
run() { OUT="$(cd "$W" && KIT_DIR="$K" sh scripts/check-kit-drift.sh "$@" 2>&1)" && RC=0 || RC=$?; }

echo "property 1: all consumed match kit original -> ok only, exit 0"
K=$(mk_kit); W=$(mk_consumer); run
[ "$RC" -eq 0 ] && pass "exit 0 when in sync" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'ok=2 drift=0 unresolved=0' && pass "ok=2 drift=0" || fail "counts wrong: $OUT"
rm -rf "$K" "$W"

echo "property 2: one consumed edited (drift) -> advisory exit 0, DRIFT in report"
K=$(mk_kit); W=$(mk_consumer); printf 'echo foo EDITED\n' > "$W/scripts/foo.sh"; run
[ "$RC" -eq 0 ] && pass "advisory exit 0 on drift" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'DRIFT       scripts/foo.sh' && pass "foo reported as DRIFT" || fail "no DRIFT line: $OUT"
printf '%s\n' "$OUT" | grep -q 'drift=1' && pass "drift=1" || fail "drift count wrong: $OUT"
rm -rf "$K" "$W"

echo "property 3: drift + --strict -> FAIL exit 1"
K=$(mk_kit); W=$(mk_consumer); printf 'echo foo EDITED\n' > "$W/scripts/foo.sh"; run --strict
[ "$RC" -eq 1 ] && pass "strict exits 1 on drift" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'FAIL (--strict)' && pass "reports strict fail" || fail "no strict msg: $OUT"
rm -rf "$K" "$W"

echo "property 4: consumed declared but absent locally -> DRIFT"
K=$(mk_kit); W=$(mk_consumer); rm "$W/scripts/bar.sh"; run
printf '%s\n' "$OUT" | grep -q 'DRIFT       scripts/bar.sh (declared consumed but absent' && pass "absent consumed is DRIFT" || fail "absent not DRIFT: $OUT"
[ "$RC" -eq 0 ] && pass "advisory exit 0" || fail "expected 0, got $RC: $OUT"
rm -rf "$K" "$W"

echo "property 5: consumed not in kit whitelist -> UNRESOLVED (distinct from drift)"
K=$(mk_kit); W=$(mk_consumer)
printf 'gatecrate_version: "v9.9.9"\nadapter: test-adapter\nconsumed_scripts:\n  - scripts/foo.sh\n  - scripts/ghost.sh\n' > "$W/sync-manifest.yaml"
printf 'echo ghost\n' > "$W/scripts/ghost.sh"; run
printf '%s\n' "$OUT" | grep -q 'UNRESOLVED  scripts/ghost.sh' && pass "ghost is UNRESOLVED" || fail "ghost not UNRESOLVED: $OUT"
printf '%s\n' "$OUT" | grep -q 'unresolved=1' && pass "unresolved=1" || fail "unresolved count wrong: $OUT"
printf '%s\n' "$OUT" | grep -q 'drift=0' && pass "unresolved not counted as drift" || fail "ghost miscounted: $OUT"
rm -rf "$K" "$W"

echo "property 6: no sync-manifest.yaml -> SKIP exit 0"
K=$(mk_kit); W=$(mk_consumer); rm "$W/sync-manifest.yaml"; run
[ "$RC" -eq 0 ] && pass "skip exit 0" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'SKIP' && pass "reports SKIP" || fail "no SKIP: $OUT"
rm -rf "$K" "$W"

echo "property 7: kit unresolvable (KIT_DIR absent) -> SKIP even with --strict"
W=$(mk_consumer)
OUT="$(cd "$W" && KIT_DIR="/no/such/kit" sh scripts/check-kit-drift.sh --strict 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 0 ] && pass "offline never fatal (exit 0)" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'SKIP' && pass "reports SKIP on missing kit" || fail "no SKIP: $OUT"
rm -rf "$W"

echo ""
echo "check-kit-drift tests: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
