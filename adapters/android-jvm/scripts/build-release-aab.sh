#!/bin/sh
# [Android-JVMアダプタ] Android App Bundle (AAB) リリースビルド
# Builds a signed release AAB using aapt2 + d8 + bundletool (no Gradle required).
#
# Required env vars (set in harness.config.sh):
#   BUILDCONFIG_PACKAGE         — Java package for BuildConfig stub
#   APP_RELEASE_KEYSTORE        — path to the production keystore (.jks)
#   APP_RELEASE_KEY_ALIAS       — key alias in the keystore
#   BUNDLETOOL_JAR              — path to bundletool.jar
#
# Optional env vars:
#   ANDROID_HOME                — Android SDK root (default: $HOME/AndroidDev/sdk)
#   ANDROID_PLATFORM            — Android platform (default: android-33)
#   ANDROID_BUILD_TOOLS         — Build tools version (default: 35.0.0)
#   APP_PRO_FEATURES_ENABLED    — enable pro features in BuildConfig (default: false)
#   APP_PLAY_BILLING_ENABLED    — enable Play billing in BuildConfig (default: false)
#   APP_RELEASE_AAB             — output path override for the signed AAB
#   APP_RELEASE_STORE_PASS      — keystore password (env variable for jarsigner)
#   APP_RELEASE_KEY_PASS        — key password (env variable for jarsigner)
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
JAVA="${JAVA:-java}"
JARSIGNER="${JARSIGNER:-jarsigner}"
ASSETS_DIR="$ROOT/src/main/assets"
AAPT_ASSETS_ARGS=""
if [ -d "$ASSETS_DIR" ]; then
  AAPT_ASSETS_ARGS="-A $ASSETS_DIR"
fi

: "${BUNDLETOOL_JAR:?Set BUNDLETOOL_JAR to the bundletool .jar path.}"
: "${APP_RELEASE_KEYSTORE:?Set APP_RELEASE_KEYSTORE to the production keystore path.}"
: "${APP_RELEASE_KEY_ALIAS:?Set APP_RELEASE_KEY_ALIAS to the production key alias.}"
BUILDCONFIG_PACKAGE="${BUILDCONFIG_PACKAGE:?BUILDCONFIG_PACKAGE must be set in harness.config.sh}"

if [ ! -f "$BUNDLETOOL_JAR" ]; then
  echo "Missing bundletool jar: $BUNDLETOOL_JAR" >&2
  exit 1
fi

if [ ! -f "$APP_RELEASE_KEYSTORE" ]; then
  echo "Missing release keystore: $APP_RELEASE_KEYSTORE" >&2
  exit 1
fi

BUILD="$ROOT/build"
RELEASE_BUILD="$BUILD/release"
PROTO_APK="$RELEASE_BUILD/base-proto.apk"
BASE_DIR="$RELEASE_BUILD/base"
BASE_ZIP="$RELEASE_BUILD/base.zip"
OUT_UNSIGNED_BUNDLE="$RELEASE_BUILD/app-$VERSION_NAME-release-unsigned.aab"
OUT_BUNDLE="${APP_RELEASE_AAB:-$RELEASE_BUILD/app-$VERSION_NAME-release.aab}"
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
  --proto-format \
  -I "$ANDROID_JAR" \
  --manifest "$MANIFEST" \
  --java "$BUILD/generated" \
  $AAPT_ASSETS_ARGS \
  -o "$PROTO_APK" \
  "$BUILD/compiled/resources.zip"

# Collect generated sources AFTER aapt2 link: it writes R.java here, so any
# main source that references R (e.g. vector icon drawables) needs the
# generated tree on the javac source list at compile time.
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

mkdir -p "$BASE_DIR"
unzip -q "$PROTO_APK" -d "$BASE_DIR"
mkdir -p "$BASE_DIR/manifest" "$BASE_DIR/dex"
mv "$BASE_DIR/AndroidManifest.xml" "$BASE_DIR/manifest/AndroidManifest.xml"
cp "$BUILD/dex/classes.dex" "$BASE_DIR/dex/classes.dex"

(cd "$BASE_DIR" && zip -q -D -r "$BASE_ZIP" .)

"$JAVA" -jar "$BUNDLETOOL_JAR" build-bundle \
  --modules="$BASE_ZIP" \
  --output="$OUT_UNSIGNED_BUNDLE"

JARSIGNER_PASSWORD_ARGS=""
if [ "${APP_RELEASE_STORE_PASS:-}" ]; then
  JARSIGNER_PASSWORD_ARGS="$JARSIGNER_PASSWORD_ARGS -storepass:env APP_RELEASE_STORE_PASS"
fi
if [ "${APP_RELEASE_KEY_PASS:-}" ]; then
  JARSIGNER_PASSWORD_ARGS="$JARSIGNER_PASSWORD_ARGS -keypass:env APP_RELEASE_KEY_PASS"
fi

# shellcheck disable=SC2086
"$JARSIGNER" \
  -keystore "$APP_RELEASE_KEYSTORE" \
  $JARSIGNER_PASSWORD_ARGS \
  -signedjar "$OUT_BUNDLE" \
  "$OUT_UNSIGNED_BUNDLE" \
  "$APP_RELEASE_KEY_ALIAS"

"$JARSIGNER" -verify "$OUT_BUNDLE"

"$JAVA" -jar "$BUNDLETOOL_JAR" validate \
  --bundle="$OUT_BUNDLE"

echo "Built release AAB: $OUT_BUNDLE"
