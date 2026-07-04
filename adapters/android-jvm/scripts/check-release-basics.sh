#!/bin/sh
# [Android-JVMアダプタ] リリース APK の基本チェック（署名・バージョン・アプリ名）
# Verifies a signed APK: no INTERNET permission, version matches VERSION file,
# and the app name matches the expected value.
#
# Required env vars (set in harness.config.sh):
#   APP_NAME             — expected app name in strings.xml (e.g. My App)
#
# Optional env vars:
#   ANDROID_HOME         — Android SDK root
#   ANDROID_BUILD_TOOLS  — Build tools version (default: 35.0.0)
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
. "$ROOT/scripts/version-env.sh"
APK="${1:-$ROOT/app-debug.apk}"
ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/android-sdk}}"
ANDROID_BUILD_TOOLS="${ANDROID_BUILD_TOOLS:-35.0.0}"
BUILD_TOOLS="$ANDROID_HOME/build-tools/$ANDROID_BUILD_TOOLS"
AAPT="${AAPT:-$BUILD_TOOLS/aapt}"
APKSIGNER="${APKSIGNER:-$BUILD_TOOLS/apksigner}"
APP_NAME="${APP_NAME:?APP_NAME must be set in harness.config.sh}"

if [ ! -f "$APK" ]; then
  echo "Missing APK: $APK" >&2
  exit 1
fi

if [ ! -x "$AAPT" ]; then
  AAPT="$(command -v aapt || true)"
fi

if [ ! -x "$APKSIGNER" ]; then
  APKSIGNER="$(command -v apksigner || true)"
fi

if [ -z "$AAPT" ] || [ ! -x "$AAPT" ]; then
  echo "Missing aapt. Set ANDROID_HOME and ANDROID_BUILD_TOOLS." >&2
  exit 1
fi

if [ -z "$APKSIGNER" ] || [ ! -x "$APKSIGNER" ]; then
  echo "Missing apksigner. Set ANDROID_HOME and ANDROID_BUILD_TOOLS." >&2
  exit 1
fi

if "$AAPT" dump permissions "$APK" | grep -q "android.permission.INTERNET"; then
  echo "Unexpected INTERNET permission" >&2
  exit 1
fi

if ! grep -q "android:versionName=\"$VERSION_NAME\"" "$ROOT/src/main/AndroidManifest.xml" "$ROOT/build/AndroidManifest."*.xml 2>/dev/null; then
  echo "Unexpected or missing versionName" >&2
  exit 1
fi

if ! grep -q "android:versionCode=\"$VERSION_CODE\"" "$ROOT/src/main/AndroidManifest.xml" "$ROOT/build/AndroidManifest."*.xml 2>/dev/null; then
  echo "Unexpected or missing versionCode" >&2
  exit 1
fi

if ! grep -q 'android:icon="@mipmap/ic_launcher"' "$ROOT/src/main/AndroidManifest.xml"; then
  echo "Missing launcher icon declaration" >&2
  exit 1
fi

if ! grep -q "<string name=\"app_name\">$APP_NAME</string>" "$ROOT/src/main/res/values/strings.xml"; then
  echo "Unexpected or missing app name (expected: $APP_NAME)" >&2
  exit 1
fi

"$APKSIGNER" verify "$APK" >/dev/null
echo "Basic release checks passed"
