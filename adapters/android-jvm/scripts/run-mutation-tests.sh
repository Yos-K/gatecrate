#!/bin/sh
# [Android-JVMアダプタ] PITest ミューテーションテスト（Android SDK不要・JVM直接実行・Kotlin/Java 混在対応）
# Mutation testing for the pure-JVM logic layers (PITest).
# .kt があれば kotlinc で先にコンパイルし PITest で変異する（Gradle/AGP 非依存・gatecrate#25 Gap1）。
#
# Required env vars (set in harness.config.sh):
#   BUILDCONFIG_PACKAGE  — Java package for BuildConfig stub (e.g. com.example.app.infrastructure)
#   TARGET_CLASSES       — PITest target class globs (e.g. com.example.app.domain.*,com.example.app.service.*)
#   TARGET_TESTS         — PITest target test globs (e.g. com.example.app.*)
#
# Optional env vars:
#   MUTATION_THRESHOLD   — fail threshold % (default: 79, ratchet floor — never lower)
#   EXCLUDED_CLASSES     — PITest excluded class globs (default: *Test,*Tests,*Property,*Properties)
#   EXCLUDED_TESTS       — PITest excluded test globs (default: *.architecture.*,*Property,*Properties)
#   BUILDCONFIG_FIELDS   — Java field declarations the BuildConfig stub must expose for the
#                          Android-free code to compile (default: a single PRO_FEATURES_ENABLED flag)
#   EXTRA_MAIN_SOURCES   — extra main source paths (repo-root-relative, space-separated) the default
#                          scan excludes but the mutation set needs (default: none)
#   MAIN_SOURCES_EXCLUDE — glob excluded at compile time (default: */presentation/*; e.g. Android-coupled files)
#   JVM_MAIN_SRC_DIRS    — repo-root-relative main source roots, space-separated
#                          (default: "src/main/java src/main/kotlin"; multi-module: e.g. "exec/src/main/kotlin")
#   JVM_TEST_SRC_DIRS    — repo-root-relative test source roots (default: "src/test/java src/test/kotlin")
#   KOTLIN_VERSION       — kotlinc dist version, only fetched when .kt present (default: 2.0.21)
#   KOTLIN_JVM_TARGET    — kotlinc -jvm-target (default: 17)
#   PITEST_VERSION       — PITest version (default: 1.15.0)
#   PITEST_JUNIT5_VERSION — PITest JUnit5 plugin version (default: 1.2.1)
#   JUNIT_VERSION        — JUnit version (default: 1.11.4)
#   ARCHUNIT_VERSION     — ArchUnit version (default: 1.3.0)
#   SLF4J_VERSION        — SLF4J version (default: 2.0.13)
#   JQWIK_VERSION        — jqwik version (default: 1.9.0)
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"

# 必須 co-dependency を早期に検証（jar ダウンロード前に fail-fast）。純 Java でもコンパイルは
# android-kotlin-compile.sh の ak_compile 経由。既存消費者が本スクリプトだけ sync すると欠落（localmd #194）。
AK_HELPER="$ROOT/scripts/android-kotlin-compile.sh"
if [ ! -f "$AK_HELPER" ]; then
  echo "ERROR: required helper not found: $AK_HELPER" >&2
  echo "  run-mutation-tests.sh は android-kotlin-compile.sh（gatecrate v0.8.0 で追加）に依存します。" >&2
  echo "  consumed_scripts に追加して同梱してください（run-unit-tests.sh も同様）。" >&2
  exit 2
fi

BUILD="$ROOT/build/mutation"
LIB="$BUILD/lib"
MAIN_CLASSES="$BUILD/main"
TEST_CLASSES="$BUILD/test"
REPORT_DIR="$BUILD/report"
THRESHOLD="${MUTATION_THRESHOLD:-79}"

BUILDCONFIG_PACKAGE="${BUILDCONFIG_PACKAGE:?BUILDCONFIG_PACKAGE must be set in harness.config.sh}"
TARGET_CLASSES="${TARGET_CLASSES:?TARGET_CLASSES must be set in harness.config.sh}"
TARGET_TESTS="${TARGET_TESTS:?TARGET_TESTS must be set in harness.config.sh}"
EXCLUDED_CLASSES="${EXCLUDED_CLASSES:-*Test,*Tests,*Property,*Properties}"
EXCLUDED_TESTS="${EXCLUDED_TESTS:-*.architecture.*,*Property,*Properties}"
# ソース収集（compile 段階）の glob 除外。Android 依存ファイル（例: android.* を import する
# クラス）は JVM 直接コンパイル不可なのでここで除外する。PITest の --excludedClasses（変異対象の
# 除外）とは別レイヤ。default は presentation 層。
MAIN_SOURCES_EXCLUDE="${MAIN_SOURCES_EXCLUDE:-*/presentation/*}"
# ソースルート（マルチモジュール対応）。repo-root 相対・スペース区切り。各 dir から .java/.kt 両方を拾う。
JVM_MAIN_SRC_DIRS="${JVM_MAIN_SRC_DIRS:-src/main/java src/main/kotlin}"
JVM_TEST_SRC_DIRS="${JVM_TEST_SRC_DIRS:-src/test/java src/test/kotlin}"
# Logic injection points (vs plain values): the fields the generated BuildConfig stub must
# expose so the project's Android-free code compiles, and any source files the default scan
# excludes but the mutation set still needs. Defaults keep a generic project working unconfigured.
BUILDCONFIG_FIELDS="${BUILDCONFIG_FIELDS:-    public static final boolean PRO_FEATURES_ENABLED = false;}"
EXTRA_MAIN_SOURCES="${EXTRA_MAIN_SOURCES:-}"

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

PITEST_VERSION="${PITEST_VERSION:-1.15.0}"
PITEST_JUNIT5_VERSION="${PITEST_JUNIT5_VERSION:-1.2.1}"
PIT_JAR="$LIB/pitest-$PITEST_VERSION.jar"
PIT_ENTRY_JAR="$LIB/pitest-entry-$PITEST_VERSION.jar"
PIT_CLI_JAR="$LIB/pitest-command-line-$PITEST_VERSION.jar"
PIT_JUNIT5_JAR="$LIB/pitest-junit5-plugin-$PITEST_JUNIT5_VERSION.jar"
COMMONS_TEXT_VERSION="1.11.0"
COMMONS_LANG3_VERSION="3.13.0"
COMMONS_TEXT_JAR="$LIB/commons-text-$COMMONS_TEXT_VERSION.jar"
COMMONS_LANG3_JAR="$LIB/commons-lang3-$COMMONS_LANG3_VERSION.jar"
# PITest's report writers need commons-text (+ commons-lang3); not bundled in the CLI jars.

# Wipe regenerated outputs but keep $LIB so the downloaded jars survive between
# runs (download_if_missing skips what is present). This lets CI cache build/mutation/lib.
rm -rf "$MAIN_CLASSES" "$TEST_CLASSES" "$REPORT_DIR" "$BUILD/generated"
mkdir -p "$MAIN_CLASSES" "$TEST_CLASSES" "$LIB" "$REPORT_DIR"

PKG_DIR=$(echo "$BUILDCONFIG_PACKAGE" | tr '.' '/')
mkdir -p "$BUILD/generated/$PKG_DIR"
cat > "$BUILD/generated/$PKG_DIR/BuildConfig.java" <<EOF
package $BUILDCONFIG_PACKAGE;

public final class BuildConfig {
$BUILDCONFIG_FIELDS

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

CENTRAL="https://repo1.maven.org/maven2"
download_if_missing "$JUNIT_JAR" \
  "$CENTRAL/org/junit/platform/junit-platform-console-standalone/$JUNIT_VERSION/junit-platform-console-standalone-$JUNIT_VERSION.jar"
download_if_missing "$ARCHUNIT_JAR" \
  "$CENTRAL/com/tngtech/archunit/archunit/$ARCHUNIT_VERSION/archunit-$ARCHUNIT_VERSION.jar"
download_if_missing "$SLF4J_API_JAR" \
  "$CENTRAL/org/slf4j/slf4j-api/$SLF4J_VERSION/slf4j-api-$SLF4J_VERSION.jar"
download_if_missing "$SLF4J_NOP_JAR" \
  "$CENTRAL/org/slf4j/slf4j-nop/$SLF4J_VERSION/slf4j-nop-$SLF4J_VERSION.jar"
download_if_missing "$JQWIK_API_JAR" \
  "$CENTRAL/net/jqwik/jqwik-api/$JQWIK_VERSION/jqwik-api-$JQWIK_VERSION.jar"
download_if_missing "$JQWIK_ENGINE_JAR" \
  "$CENTRAL/net/jqwik/jqwik-engine/$JQWIK_VERSION/jqwik-engine-$JQWIK_VERSION.jar"
download_if_missing "$PIT_JAR" \
  "$CENTRAL/org/pitest/pitest/$PITEST_VERSION/pitest-$PITEST_VERSION.jar"
download_if_missing "$PIT_ENTRY_JAR" \
  "$CENTRAL/org/pitest/pitest-entry/$PITEST_VERSION/pitest-entry-$PITEST_VERSION.jar"
download_if_missing "$PIT_CLI_JAR" \
  "$CENTRAL/org/pitest/pitest-command-line/$PITEST_VERSION/pitest-command-line-$PITEST_VERSION.jar"
download_if_missing "$PIT_JUNIT5_JAR" \
  "$CENTRAL/org/pitest/pitest-junit5-plugin/$PITEST_JUNIT5_VERSION/pitest-junit5-plugin-$PITEST_JUNIT5_VERSION.jar"
download_if_missing "$COMMONS_TEXT_JAR" \
  "$CENTRAL/org/apache/commons/commons-text/$COMMONS_TEXT_VERSION/commons-text-$COMMONS_TEXT_VERSION.jar"
download_if_missing "$COMMONS_LANG3_JAR" \
  "$CENTRAL/org/apache/commons/commons-lang3/$COMMONS_LANG3_VERSION/commons-lang3-$COMMONS_LANG3_VERSION.jar"

LIB_CLASSPATH="$JUNIT_JAR:$ARCHUNIT_JAR:$SLF4J_API_JAR:$SLF4J_NOP_JAR:$JQWIK_API_JAR:$JQWIK_ENGINE_JAR"
PIT_CLASSPATH="$PIT_JAR:$PIT_ENTRY_JAR:$PIT_CLI_JAR:$PIT_JUNIT5_JAR:$COMMONS_TEXT_JAR:$COMMONS_LANG3_JAR"

# Kotlin+Java 混在コンパイルヘルパー（早期に存在確認済み）。PITest は kotlinc 出力もそのまま変異できる。
# shellcheck source=/dev/null
. "$AK_HELPER"

# ソース収集（マルチモジュール対応・各 dir から .java/.kt 両方）。
: > "$BUILD/main-sources.txt"
: > "$BUILD/main-kt.txt"
for rel in $JVM_MAIN_SRC_DIRS; do
  d="$ROOT/$rel"; [ -d "$d" ] || continue
  find "$d" -name "*.java" ! -path "$MAIN_SOURCES_EXCLUDE" >> "$BUILD/main-sources.txt"
  find "$d" -name "*.kt"   ! -path "$MAIN_SOURCES_EXCLUDE" >> "$BUILD/main-kt.txt"
done
# Add project-specific sources the default scan excludes (e.g. one presentation file the
# Android-free set still references). Paths are relative to the repo root; missing ones are skipped.
for extra in $EXTRA_MAIN_SOURCES; do
  [ -f "$ROOT/$extra" ] && echo "$ROOT/$extra" >> "$BUILD/main-sources.txt"
done
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

PIT_RUN_CP="$PIT_CLASSPATH:$MAIN_CLASSES:$TEST_CLASSES:$LIB_CLASSPATH"
[ -n "$STDLIB" ] && PIT_RUN_CP="$PIT_RUN_CP:$STDLIB"

# sourceDirs はレポート描画用。実在する main ソースルートだけをカンマ区切りで渡す。
SOURCE_DIRS=""
for rel in $JVM_MAIN_SRC_DIRS; do
  d="$ROOT/$rel"; [ -d "$d" ] || continue
  [ -z "$SOURCE_DIRS" ] && SOURCE_DIRS="$d" || SOURCE_DIRS="$SOURCE_DIRS,$d"
done
[ -n "$SOURCE_DIRS" ] || SOURCE_DIRS="$ROOT"

echo "Running PITest (threshold ${THRESHOLD}%)..."
set +e
java -cp "$PIT_RUN_CP" \
  org.pitest.mutationtest.commandline.MutationCoverageReport \
  --reportDir "$REPORT_DIR" \
  --targetClasses "$TARGET_CLASSES" \
  --excludedClasses "$EXCLUDED_CLASSES" \
  --targetTests "$TARGET_TESTS" \
  --excludedTestClasses "$EXCLUDED_TESTS" \
  --sourceDirs "$SOURCE_DIRS" \
  --outputFormats HTML,XML \
  --timestampedReports false \
  --testPlugin junit5 \
  --threads 2 \
  --mutationThreshold "$THRESHOLD"
PIT_RC=$?
set -e

XML="$REPORT_DIR/mutations.xml"
TRIAGE="$REPORT_DIR/triage.txt"
if [ -f "$XML" ]; then
  {
    echo "SURVIVED hotspots (weak/missing assertions — fix these first):"
    grep "status='SURVIVED'" "$XML" \
      | sed -E "s@.*<mutatedClass>([^<]+)</mutatedClass>.*@\1@" \
      | sort | uniq -c | sort -rn | head -10
    echo ""
    echo "NO_COVERAGE hotspots (no example test runs this — add a test or exclude with a reason):"
    grep "status='NO_COVERAGE'" "$XML" \
      | sed -E "s@.*<mutatedClass>([^<]+)</mutatedClass>.*@\1@" \
      | sort | uniq -c | sort -rn | head -10
  } > "$TRIAGE"
  echo ""
  echo "=== Triage (also at $TRIAGE) ==="
  cat "$TRIAGE"
  echo "================================"
fi

if [ "$PIT_RC" -ne 0 ]; then
  echo "Mutation score below floor ${THRESHOLD}%. Do NOT lower the floor — add example tests" >&2
  echo "for the SURVIVED hotspots above, or exclude low-value targets with a recorded reason." >&2
  exit "$PIT_RC"
fi
echo "Mutation testing passed (>= ${THRESHOLD}% mutation score). Report: $REPORT_DIR/index.html"
