#!/bin/sh
# [Android-JVMアダプタ] Proバリアントのデバッグ APK ビルド（Termux/ローカル用）
# Builds the Pro debug APK via build.sh in the project root.
#
# Optional env vars:
#   APP_PRO_DEBUG_PACKAGE — Pro debug package suffix (default: .pro.debug)
#   APP_PRO_DEBUG_NAME    — Pro debug app name (default: App Pro Dev)
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
OUT="${1:-/sdcard/Download/app-pro-debug.apk}"
PACKAGE="${APP_PACKAGE:-com.example.app}"
SUFFIX="${APP_PRO_DEBUG_PACKAGE:-.pro.debug}"
APP_NAME="${APP_PRO_DEBUG_NAME:-App Pro Dev}"

sh "$ROOT/scripts/prepare-android-dependencies.sh" > /dev/null

APP_DEBUG_PRO_FEATURES=true \
APP_DEBUG_PLAY_BILLING=true \
APP_INCLUDE_ANDROID_DEPS=true \
APP_DEBUG_PACKAGE="${PACKAGE}${SUFFIX}" \
APP_DEBUG_NAME="$APP_NAME" \
"$ROOT/build.sh" > /dev/null

cp "$ROOT/app-debug.apk" "$OUT"

echo "Built Pro debug APK: $OUT"
