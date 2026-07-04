#!/bin/sh
# tests/test-check-release-version-name.sh — core/scripts/check-release-version-name.sh の挙動テスト
#
# 文脈（リリース衛生ゲート）: ユーザー可視の版名を前回タグと同じまま公開する事故を、リリースより
# 手前で止めるゲート。検査は純 git（タグ一覧 vs VERSION_NAME）なのでスタック非依存。スクリプトは
# 消費者モデル（scripts/ に配置され scripts/version-env.sh を source する）で動くため、一時的に
# consumer 風のリポ（scripts/ + VERSION + git tag）を組んで決定論に検証する。
#
# 検証する性質:
#   1. 版名が最新タグと一致 -> リリース拒否（exit 1）
#   2. ALLOW_VERSION_NAME_REUSE=true なら据え置きを許可（exit 0）
#   3. 版名が最新タグより新しい -> 許可（exit 0）
#   4. リリースタグが無い -> 許可（exit 0）
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
GUARD="$ROOT/core/scripts/check-release-version-name.sh"
VERSION_ENV="$ROOT/core/scripts/version-env.sh"
PASS=0; FAIL=0

tmp="${TMPDIR:-/tmp}/gatecrate-version-guard-$$"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT

# Build a consumer-style repo: scripts/check-release-version-name.sh + scripts/version-env.sh
# resolved via the SAME relative source the installed layout uses.
make_repo() {
  repo="$1"; version_name="$2"; version_code="$3"; tag="$4"
  mkdir -p "$repo/scripts"
  cp "$GUARD" "$repo/scripts/check-release-version-name.sh"
  cp "$VERSION_ENV" "$repo/scripts/version-env.sh"
  printf 'VERSION_NAME=%s\nVERSION_CODE=%s\n' "$version_name" "$version_code" > "$repo/VERSION"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@example.invalid"
  git -C "$repo" config user.name "Test"
  git -C "$repo" add .
  git -C "$repo" commit -q -m "test: seed version"
  [ -n "$tag" ] && git -C "$repo" tag "$tag"
  return 0
}

check() {
  desc="$1"; expect="$2"; repo="$3"; allow="${4:-}"
  # Capture the exit code without tripping `set -e` on an expected non-zero.
  if [ -n "$allow" ]; then
    ALLOW_VERSION_NAME_REUSE=true ROOT="$repo" sh "$repo/scripts/check-release-version-name.sh" >/dev/null 2>&1 && rc=0 || rc=$?
  else
    ROOT="$repo" sh "$repo/scripts/check-release-version-name.sh" >/dev/null 2>&1 && rc=0 || rc=$?
  fi
  if [ "$rc" -eq "$expect" ]; then
    PASS=$((PASS + 1)); echo "PASS: $desc"
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $desc (expected exit $expect, got $rc)"
  fi
}

# 1. reused version name -> reject
make_repo "$tmp/same" "0.1.0" "16" "v0.1.0"
check "reused VERSION_NAME is rejected" 1 "$tmp/same"

# 2. reuse allowed by env override
check "ALLOW_VERSION_NAME_REUSE bypasses the guard" 0 "$tmp/same" allow

# 3. newer version name -> accept
make_repo "$tmp/next" "0.1.1" "17" "v0.1.0"
check "newer VERSION_NAME is accepted" 0 "$tmp/next"

# 4. no release tag -> accept
make_repo "$tmp/none" "0.1.0" "16" ""
check "no release tag is acceptable" 0 "$tmp/none"

echo
echo "Release version name guard: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
