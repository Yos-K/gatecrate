#!/bin/sh
# [Android-JVMアダプタ] Android依存クラスパス組み立て — JVM直接ビルド用
# Builds ANDROID_DEPENDENCY_CLASSPATH and ANDROID_DEPENDENCY_D8_INPUTS
# from the local Android dependency cache directory.
#
# Optional env vars:
#   APP_ANDROID_DEPS_DIR     — path to downloaded Android deps (default: .android-deps)
#   APP_INCLUDE_ANDROID_DEPS — set to "true" to include deps in classpath (default: false)
set -eu

ROOT="${ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)}"
ANDROID_DEPS_DIR="${APP_ANDROID_DEPS_DIR:-$ROOT/.android-deps}"
ANDROID_DEPENDENCY_CLASSPATH=""
ANDROID_DEPENDENCY_D8_INPUTS=""

if [ "${APP_INCLUDE_ANDROID_DEPS:-false}" = "true" ] && [ -d "$ANDROID_DEPS_DIR/classes" ]; then
  for jar in "$ANDROID_DEPS_DIR"/classes/*.jar; do
    if [ -f "$jar" ]; then
      if [ -z "$ANDROID_DEPENDENCY_CLASSPATH" ]; then
        ANDROID_DEPENDENCY_CLASSPATH="$jar"
      else
        ANDROID_DEPENDENCY_CLASSPATH="$ANDROID_DEPENDENCY_CLASSPATH:$jar"
      fi
      ANDROID_DEPENDENCY_D8_INPUTS="$ANDROID_DEPENDENCY_D8_INPUTS $jar"
    fi
  done
fi

export ANDROID_DEPS_DIR ANDROID_DEPENDENCY_CLASSPATH ANDROID_DEPENDENCY_D8_INPUTS
