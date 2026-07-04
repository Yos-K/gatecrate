#!/bin/sh
# [Android-JVMアダプタ] JVMユニットテスト実行（Android SDKなし・Kotlin/Java 混在対応）
# Runs JUnit5/ArchUnit/jqwik unit tests via JVM directly (no Android SDK required).
# .kt があれば kotlinc で先にコンパイルし .class を混ぜる（Gradle/AGP 非依存・gatecrate#25 Gap1）。
#
# Required env vars (set in harness.config.sh):
#   BUILDCONFIG_PACKAGE  — Java package for BuildConfig stub (e.g. com.example.app.infrastructure)
#
# Optional env vars:
#   MAIN_SOURCES_EXCLUDE — glob pattern to exclude from main sources (default: */presentation/*)
#   JVM_MAIN_SRC_DIRS    — repo-root-relative main source roots, space-separated
#                          (default: "src/main/java src/main/kotlin"; multi-module: e.g. "exec/src/main/kotlin")
#   JVM_TEST_SRC_DIRS    — repo-root-relative test source roots (default: "src/test/java src/test/kotlin")
#   KOTLIN_VERSION       — kotlinc dist version, only fetched when .kt present (default: 2.0.21)
#   KOTLIN_JVM_TARGET    — kotlinc -jvm-target (default: 17)
#   MAIN_SOURCES_INCLUDE — additional source file to include from presentation (default: none)
#   JUNIT_VERSION        — JUnit Platform console standalone version (default: 1.11.4)
#   ARCHUNIT_VERSION     — ArchUnit version (default: 1.3.0)
#   SLF4J_VERSION        — SLF4J version (default: 2.0.13)
#   JQWIK_VERSION        — jqwik version (default: 1.9.0)
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"

# 必須 co-dependency を早期に検証（jar ダウンロード前に fail-fast）。run-unit-tests.sh は
# 純 Java でもコンパイルを android-kotlin-compile.sh の ak_compile 経由で行うため必須。
# 既存消費者が本スクリプトだけを sync するとここで欠落する（localmd #194）。
AK_HELPER="$ROOT/scripts/android-kotlin-compile.sh"
if [ ! -f "$AK_HELPER" ]; then
  echo "ERROR: required helper not found: $AK_HELPER" >&2
  echo "  run-unit-tests.sh は android-kotlin-compile.sh（gatecrate v0.8.0 で追加）に依存します。" >&2
  echo "  consumed_scripts に追加して同梱してください（run-mutation-tests.sh も同様）。" >&2
  exit 2
fi

BUILD="$ROOT/build/unit-tests"
LIB="$BUILD/lib"
MAIN_CLASSES="$BUILD/main"
TEST_CLASSES="$BUILD/test"
JUNIT_VERSION="${JUNIT_VERSION:-1.11.4}"
JUNIT_JAR="$LIB/junit-platform-console-standalone-$JUNIT_VERSION.jar"
ARCHUNIT_VERSION="${ARCHUNIT_VERSION:-1.3.0}"
ARCHUNIT_JAR="$LIB/archunit-$ARCHUNIT_VERSION.jar"
SLF4J_VERSION="${SLF4J_VERSION:-2.0.13}"
SLF4J_API_JAR="$LIB/slf4j-api-$SLF4J_VERSION.jar"
SLF4J_NOP_JAR="$LIB/slf4j-nop-$SLF4J_VERSION.jar"
JQWIK_VERSION="${JQWIK_VERSION:-1.9.0}"
JQWIK_API_JAR="$LIB/jqwik-api-$JQWIK_VERSION.jar"
JQWIK_ENGINE_JAR="$LIB/jqwik-engine-$JQWIK_VERSION.jar"

BUILDCONFIG_PACKAGE="${BUILDCONFIG_PACKAGE:?BUILDCONFIG_PACKAGE must be set in harness.config.sh}"
MAIN_SOURCES_EXCLUDE="${MAIN_SOURCES_EXCLUDE:-*/presentation/*}"

rm -rf "$BUILD"
mkdir -p "$MAIN_CLASSES" "$TEST_CLASSES" "$LIB"

PKG_DIR=$(echo "$BUILDCONFIG_PACKAGE" | tr '.' '/')
mkdir -p "$BUILD/generated/$PKG_DIR"
cat > "$BUILD/generated/$PKG_DIR/BuildConfig.java" <<EOF
package $BUILDCONFIG_PACKAGE;

public final class BuildConfig {
    public static final boolean PRO_FEATURES_ENABLED = false;

    private BuildConfig() {
    }
}
EOF

download_if_missing() {
  target_path="$1"
  url="$2"
  if [ ! -f "$target_path" ]; then
    echo "Downloading $(basename "$target_path")..."
    curl -sL "$url" -o "$target_path"
  fi
}

download_if_missing "$JUNIT_JAR" \
  "https://repo1.maven.org/maven2/org/junit/platform/junit-platform-console-standalone/$JUNIT_VERSION/junit-platform-console-standalone-$JUNIT_VERSION.jar"
download_if_missing "$ARCHUNIT_JAR" \
  "https://repo1.maven.org/maven2/com/tngtech/archunit/archunit/$ARCHUNIT_VERSION/archunit-$ARCHUNIT_VERSION.jar"
download_if_missing "$SLF4J_API_JAR" \
  "https://repo1.maven.org/maven2/org/slf4j/slf4j-api/$SLF4J_VERSION/slf4j-api-$SLF4J_VERSION.jar"
download_if_missing "$SLF4J_NOP_JAR" \
  "https://repo1.maven.org/maven2/org/slf4j/slf4j-nop/$SLF4J_VERSION/slf4j-nop-$SLF4J_VERSION.jar"
download_if_missing "$JQWIK_API_JAR" \
  "https://repo1.maven.org/maven2/net/jqwik/jqwik-api/$JQWIK_VERSION/jqwik-api-$JQWIK_VERSION.jar"
download_if_missing "$JQWIK_ENGINE_JAR" \
  "https://repo1.maven.org/maven2/net/jqwik/jqwik-engine/$JQWIK_VERSION/jqwik-engine-$JQWIK_VERSION.jar"

LIB_CLASSPATH="$JUNIT_JAR:$ARCHUNIT_JAR:$SLF4J_API_JAR:$SLF4J_NOP_JAR:$JQWIK_API_JAR:$JQWIK_ENGINE_JAR"

# Kotlin+Java 混在コンパイルヘルパー（早期に存在確認済み・.kt が無ければ素の javac と同じ挙動）。
# shellcheck source=/dev/null
. "$AK_HELPER"

# ソースルート（マルチモジュール対応: vibe-coder 等は exec/src/... に置く。default は単一モジュール）。
# repo-root 相対・スペース区切り。各 dir から .java と .kt の両方を拾う。gatecrate#25 Gap1。
JVM_MAIN_SRC_DIRS="${JVM_MAIN_SRC_DIRS:-src/main/java src/main/kotlin}"
JVM_TEST_SRC_DIRS="${JVM_TEST_SRC_DIRS:-src/test/java src/test/kotlin}"

: > "$BUILD/main-sources.txt"
: > "$BUILD/main-kt.txt"
for rel in $JVM_MAIN_SRC_DIRS; do
  d="$ROOT/$rel"; [ -d "$d" ] || continue
  find "$d" -name "*.java" ! -path "$MAIN_SOURCES_EXCLUDE" >> "$BUILD/main-sources.txt"
  find "$d" -name "*.kt"   ! -path "$MAIN_SOURCES_EXCLUDE" >> "$BUILD/main-kt.txt"
done
if [ -n "${MAIN_SOURCES_INCLUDE:-}" ] && [ -f "$MAIN_SOURCES_INCLUDE" ]; then
  echo "$MAIN_SOURCES_INCLUDE" >> "$BUILD/main-sources.txt"
fi
find "$BUILD/generated" -name "*.java" >> "$BUILD/main-sources.txt"

: > "$BUILD/test-sources.txt"
: > "$BUILD/test-kt.txt"
for rel in $JVM_TEST_SRC_DIRS; do
  d="$ROOT/$rel"; [ -d "$d" ] || continue
  find "$d" -name "*.java" >> "$BUILD/test-sources.txt"
  find "$d" -name "*.kt"   >> "$BUILD/test-kt.txt"
done

STDLIB=""
ak_compile "$MAIN_CLASSES" "$BUILD/main-kt.txt" "$BUILD/main-sources.txt" "$LIB_CLASSPATH"
[ -n "$AK_STDLIB_JAR" ] && STDLIB="$AK_STDLIB_JAR"
TEST_CP="$MAIN_CLASSES:$LIB_CLASSPATH"
[ -n "$STDLIB" ] && TEST_CP="$TEST_CP:$STDLIB"
ak_compile "$TEST_CLASSES" "$BUILD/test-kt.txt" "$BUILD/test-sources.txt" "$TEST_CP" "$MAIN_CLASSES"
[ -n "$AK_STDLIB_JAR" ] && STDLIB="$AK_STDLIB_JAR"

RUN_CLASSPATH="$MAIN_CLASSES:$TEST_CLASSES:$LIB_CLASSPATH"
[ -n "$STDLIB" ] && RUN_CLASSPATH="$RUN_CLASSPATH:$STDLIB"

java -jar "$JUNIT_JAR" \
  --class-path "$RUN_CLASSPATH" \
  --scan-class-path "$TEST_CLASSES" \
  --include-classname "^.*(Test|Tests|Property|Properties)$" \
  --fail-if-no-tests

echo "Unit tests passed"
