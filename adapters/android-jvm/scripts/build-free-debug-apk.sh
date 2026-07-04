#!/bin/sh
# [Android-JVMアダプタ] Freeバリアントのデバッグ APK ビルド（Termux/ローカル用）
# Builds the Free debug APK via build.sh in the project root.
#
# Optional env vars:
#   APP_FREE_DEBUG_PACKAGE — Free debug package suffix (default: .free.debug)
#   APP_FREE_DEBUG_NAME    — Free debug app name (default: App Free Dev)
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
OUT="${1:-/sdcard/Download/app-free-debug.apk}"
PACKAGE="${APP_PACKAGE:-com.example.app}"
SUFFIX="${APP_FREE_DEBUG_PACKAGE:-.free.debug}"
APP_NAME="${APP_FREE_DEBUG_NAME:-App Free Dev}"

APP_DEBUG_PRO_FEATURES=false \
APP_DEBUG_PLAY_BILLING=false \
APP_DEBUG_PACKAGE="${PACKAGE}${SUFFIX}" \
APP_DEBUG_NAME="$APP_NAME" \
"$ROOT/build.sh" > /dev/null

cp "$ROOT/app-debug.apk" "$OUT"

echo "Built Free debug APK: $OUT"
