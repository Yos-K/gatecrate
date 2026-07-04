#!/bin/sh
# [Android-JVMアダプタ] リリース前プリフライト — ソースレベルのリリース検査を一括で走らせ、
# ビルド/アップロード前に一つの簡潔な合否サマリを出す。
#
# WHY: Play へのアップロードは版名・リリースノート・パッケージ id・署名前提など複数の
# 不変条件に依存するが、それらは APK をビルドしないと一部しか確認できないと思われがち。
# 本スクリプトはソースレベルで確認できる不変条件（APK / Android SDK 不要）を先に全部潰し、
# 落ちる基準を「ビルド・アップロードより手前」で捕まえる。APK レベルの検査
# （check-release-basics.sh）はリリースワークフロー側でビルド済み APK に対して別途走る。
#
# Android/Play 固有のため core ではなくアダプタに置く（applicationId・AndroidManifest・
# Gradle flavor・Play の free-only アップロードガードは Android-JVM リリース経路に固有）。
#
# 設定（harness.config.sh または環境変数）:
#   RELEASE_PACKAGE_ID   — アップロード対象パッケージ id（必須。例: com.example.app）
#   MANIFEST_PATH        — applicationId/package を宣言する Manifest（既定: src/main/AndroidManifest.xml）
#   GRADLE_BUILD_FILE    — applicationId を宣言する Gradle ファイル（既定: app/build.gradle）
#   PLAY_RELEASE_WORKFLOW— Play アップロードワークフロー（既定: .github/workflows/play-release.yml）
#   FREE_ONLY_UPLOAD_GUARD— Play ワークフローに存在すべき free-only ガード文字列
#                           （既定: 空 = ガード存在チェックをスキップ）
#   CHECK_GRADLE_FLAVOR_SUFFIXES— "1" なら Gradle の flavor 用 applicationIdSuffix 存在も検査（既定: 0）
set -u

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"
cd "$ROOT"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
. "$ROOT/scripts/version-env.sh"

SCRIPTS_DIR="scripts"
RELEASE_PACKAGE_ID="${RELEASE_PACKAGE_ID:-}"
MANIFEST_PATH="${MANIFEST_PATH:-src/main/AndroidManifest.xml}"
GRADLE_BUILD_FILE="${GRADLE_BUILD_FILE:-app/build.gradle}"
PLAY_RELEASE_WORKFLOW="${PLAY_RELEASE_WORKFLOW:-.github/workflows/play-release.yml}"
FREE_ONLY_UPLOAD_GUARD="${FREE_ONLY_UPLOAD_GUARD:-}"
CHECK_GRADLE_FLAVOR_SUFFIXES="${CHECK_GRADLE_FLAVOR_SUFFIXES:-0}"

status=0
results=""

record() {
  if [ "$2" -eq 0 ]; then
    results="$results
  PASS  $1"
  else
    results="$results
  FAIL  $1"
    status=1
  fi
}

run_check() {
  name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    record "$name" 0
  else
    record "$name" 1
  fi
}

# A core/adapter gate is only run if it is actually installed.
run_script_check() {
  name="$1"; script="$2"
  if [ ! -f "$SCRIPTS_DIR/$script" ]; then
    return 0
  fi
  run_check "$name" sh "$SCRIPTS_DIR/$script"
}

# The upload package id must be identical in both release-path sources:
# the manifest (script path) and the Gradle build file (Gradle path).
check_upload_package_id() {
  [ -n "$RELEASE_PACKAGE_ID" ] || return 1
  grep -q "package=\"$RELEASE_PACKAGE_ID\"" "$MANIFEST_PATH" \
    && grep -q "applicationId \"$RELEASE_PACKAGE_ID\"" "$GRADLE_BUILD_FILE"
}

# Gradle product-flavor suffixes are present (optional; opt-in via config).
check_gradle_flavor_ids() {
  grep -q 'applicationIdSuffix' "$GRADLE_BUILD_FILE"
}

# Play upload guard string is present in the release workflow.
check_free_only_upload() {
  [ -n "$FREE_ONLY_UPLOAD_GUARD" ] || return 1
  grep -q "$FREE_ONLY_UPLOAD_GUARD" "$PLAY_RELEASE_WORKFLOW"
}

run_script_check "version consistency" "version-check.sh"
run_script_check "version name not already released" "check-release-version-name.sh"
run_script_check "release notes present and current" "check-release-notes.sh"
run_script_check "hard constraints" "check-hard-constraints.sh"
run_script_check "no committed secrets or keystores" "check-no-committed-secrets.sh"
run_script_check "third-party notices present" "check-third-party-notices.sh"

if [ -n "$RELEASE_PACKAGE_ID" ]; then
  run_check "upload package id ($RELEASE_PACKAGE_ID; manifest and gradle agree)" check_upload_package_id
fi
if [ "$CHECK_GRADLE_FLAVOR_SUFFIXES" = "1" ]; then
  run_check "gradle flavor package suffixes present" check_gradle_flavor_ids
fi
if [ -n "$FREE_ONLY_UPLOAD_GUARD" ]; then
  run_check "Play upload guard present" check_free_only_upload
fi

echo "Release preflight for v$VERSION_NAME ($VERSION_CODE):$results"
if [ "$status" -ne 0 ]; then
  echo "Release preflight FAILED" >&2
else
  echo "Release preflight passed"
fi
exit "$status"
