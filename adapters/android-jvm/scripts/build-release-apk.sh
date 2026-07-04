#!/bin/sh
# [Android-JVMアダプタ] Android APK リリースビルド（署名済み）
# Builds a signed release APK using aapt2 + d8 + apksigner (no Gradle required).
#
# Required env vars (set in harness.config.sh):
#   BUILDCONFIG_PACKAGE      — Java package for BuildConfig stub
#   APP_RELEASE_KEYSTORE     — path to the production keystore (.jks)
#   APP_RELEASE_KEY_ALIAS    — key alias in the keystore
#   APP_RELEASE_STORE_PASS   — keystore password
#   APP_RELEASE_KEY_PASS     — key password
#
# Optional env vars:
#   ANDROID_HOME             — Android SDK root (default: $HOME/AndroidDev/sdk)
#   ANDROID_PLATFORM         — Android platform (default: android-33)
#   ANDROID_BUILD_TOOLS      — Build tools version (default: 35.0.0)
#   APP_PRO_FEATURES_ENABLED — enable pro features in BuildConfig (default: false)
#   APP_PLAY_BILLING_ENABLED — enable Play billing in BuildConfig (default: false)
#   APP_RELEASE_APK          — output path override for the signed APK
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
if [ -f "$ROOT/env.project.sh" ]; then
  . "$ROOT/env.project.sh"
fi
. "$ROOT/scripts/version-env.sh"
. "$ROOT/scripts/android-dependency-env.sh"
ANDROID_HOME="${ANDROID_HOME:-$HOME/AndroidDev/sdk}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-33}"
ANDROID_BUILD_TOOLS="${ANDROID_BUILD_TOOLS:-35.0.0}"
ANDROID_JAR="$ANDROID_HOME/platforms/$ANDROID_PLATFORM/android.jar"
BUILD_TOOLS="$ANDROID_HOME/build-tools/$ANDROID_BUILD_TOOLS"

AAPT2="${AAPT2:-$BUILD_TOOLS/aapt2}"
D8="${D8:-$BUILD_TOOLS/d8}"
ZIPALIGN="${ZIPALIGN:-$BUILD_TOOLS/zipalign}"
APKSIGNER="${APKSIGNER:-$BUILD_TOOLS/apksigner}"
ASSETS_DIR="$ROOT/src/main/assets"
AAPT_ASSETS_ARGS=""
if [ -d "$ASSETS_DIR" ]; then
  AAPT_ASSETS_ARGS="-A $ASSETS_DIR"
fi

: "${APP_RELEASE_KEYSTORE:?Set APP_RELEASE_KEYSTORE to the production keystore path.}"
: "${APP_RELEASE_KEY_ALIAS:?Set APP_RELEASE_KEY_ALIAS to the production key alias.}"
: "${APP_RELEASE_STORE_PASS:?Set APP_RELEASE_STORE_PASS for apksigner.}"
: "${APP_RELEASE_KEY_PASS:?Set APP_RELEASE_KEY_PASS for apksigner.}"
BUILDCONFIG_PACKAGE="${BUILDCONFIG_PACKAGE:?BUILDCONFIG_PACKAGE must be set in harness.config.sh}"

if [ ! -f "$APP_RELEASE_KEYSTORE" ]; then
  echo "Missing release keystore: $APP_RELEASE_KEYSTORE" >&2
  exit 1
fi

BUILD="$ROOT/build"
RELEASE_BUILD="$BUILD/release"
OUT_UNSIGNED="$RELEASE_BUILD/app-release-unsigned.apk"
OUT_ALIGNED="$RELEASE_BUILD/app-release-aligned.apk"
OUT_SIGNED="${APP_RELEASE_APK:-$RELEASE_BUILD/app-$VERSION_NAME-release.apk}"
MANIFEST="$BUILD/AndroidManifest.release.xml"

rm -rf "$BUILD"
mkdir -p "$BUILD/compiled" "$BUILD/generated" "$BUILD/classes" "$BUILD/dex" "$RELEASE_BUILD"
sh "$ROOT/scripts/version-apply-manifest.sh" "$ROOT/src/main/AndroidManifest.xml" "$MANIFEST"
if [ "${APP_PLAY_BILLING_ENABLED:-false}" = "true" ]; then
  sh "$ROOT/scripts/apply-billing-manifest.sh" "$MANIFEST"
fi

PKG_DIR=$(echo "$BUILDCONFIG_PACKAGE" | tr '.' '/')
mkdir -p "$BUILD/generated/$PKG_DIR"
cat > "$BUILD/generated/$PKG_DIR/BuildConfig.java" <<EOF
package $BUILDCONFIG_PACKAGE;

public final class BuildConfig {
    public static final boolean PRO_FEATURES_ENABLED = ${APP_PRO_FEATURES_ENABLED:-false};
    public static final boolean PLAY_BILLING_ENABLED = ${APP_PLAY_BILLING_ENABLED:-false};

    private BuildConfig() {
    }
}
EOF
find "$ROOT/src/main/java" -name "*.java" > "$BUILD/main-sources.txt"
if [ "${APP_PLAY_BILLING_ENABLED:-false}" = "true" ] && [ -d "$ROOT/src/billing/java" ]; then
  find "$ROOT/src/billing/java" -name "*.java" >> "$BUILD/main-sources.txt"
fi
"$AAPT2" compile --dir "$ROOT/src/main/res" -o "$BUILD/compiled/resources.zip"
"$AAPT2" link \
  -I "$ANDROID_JAR" \
  --manifest "$MANIFEST" \
  --java "$BUILD/generated" \
  $AAPT_ASSETS_ARGS \
  -o "$OUT_UNSIGNED" \
  "$BUILD/compiled/resources.zip"

find "$BUILD/generated" -name "*.java" >> "$BUILD/main-sources.txt"

javac \
  -source 8 \
  -target 8 \
  -bootclasspath "$ANDROID_JAR" \
  -classpath "$ANDROID_JAR${ANDROID_DEPENDENCY_CLASSPATH:+:$ANDROID_DEPENDENCY_CLASSPATH}" \
  -d "$BUILD/classes" \
  @"$BUILD/main-sources.txt"

"$D8" \
  --lib "$ANDROID_JAR" \
  --output "$BUILD/dex" \
  $(find "$BUILD/classes" -name "*.class") \
  $ANDROID_DEPENDENCY_D8_INPUTS

(cd "$BUILD/dex" && zip -q -D "$OUT_UNSIGNED" classes.dex)
"$ZIPALIGN" -f 4 "$OUT_UNSIGNED" "$OUT_ALIGNED"

"$APKSIGNER" sign \
  --ks "$APP_RELEASE_KEYSTORE" \
  --ks-key-alias "$APP_RELEASE_KEY_ALIAS" \
  --ks-pass env:APP_RELEASE_STORE_PASS \
  --key-pass env:APP_RELEASE_KEY_PASS \
  --out "$OUT_SIGNED" \
  "$OUT_ALIGNED"

"$APKSIGNER" verify "$OUT_SIGNED"
sh "$ROOT/scripts/check-release-basics.sh" "$OUT_SIGNED"

echo "Built release APK: $OUT_SIGNED"
