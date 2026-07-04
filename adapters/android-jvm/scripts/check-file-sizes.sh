#!/bin/sh
# [Android-JVMアダプタ] Javaソースファイルの行数上限チェック
# Fitness Function: enforce per-file line count limit for Java source files.
#
# Config (optional, from harness.config.sh in the consumer repo root):
#   FITNESS_MAX_LINES   — line limit (default: 300)
#   FITNESS_EXCEPTIONS  — path to exceptions file (default: scripts/fitness-exceptions.txt)
#
# Consumption model (this is the pilot script for it): repo root is resolved with
# `git rev-parse` so the SAME file works whether it lives in this kit
# (adapters/android-jvm/scripts/) or installed into a consumer (scripts/) — no
# install-time path rewriting, which makes kit<->consumer sync diff-free.
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"
# Project-specific values live in the consumer's harness.config.sh; the kit repo
# has none, so defaults apply. This sourcing is the config -> script wiring.
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
MAX_LINES="${FITNESS_MAX_LINES:-300}"
EXCEPTIONS_FILE="${FITNESS_EXCEPTIONS:-$ROOT/scripts/fitness-exceptions.txt}"

is_exception() {
  target="$1"
  if [ ! -f "$EXCEPTIONS_FILE" ]; then
    return 1
  fi
  while IFS= read -r line; do
    case "$line" in
      ''|'#'*) continue ;;
    esac
    if [ "$target" = "$line" ]; then
      return 0
    fi
  done < "$EXCEPTIONS_FILE"
  return 1
}

violations=0
exceptions_used=0

# Check all Java source files under src/
java_files=$(find "$ROOT/src" -name "*.java" -type f 2>/dev/null || true)
if [ -n "$java_files" ]; then
  for file in $java_files; do
    lines=$(wc -l < "$file")
    if [ "$lines" -gt "$MAX_LINES" ]; then
      relative="${file#$ROOT/}"
      if is_exception "$relative"; then
        echo "EXEMPT  $lines lines  $relative"
        exceptions_used=$((exceptions_used + 1))
      else
        echo "FAIL    $lines lines  $relative (limit: $MAX_LINES)"
        violations=$((violations + 1))
      fi
    fi
  done
fi

echo ""
if [ "$violations" -gt 0 ]; then
  echo "Fitness check FAILED: $violations file(s) exceed the $MAX_LINES line limit."
  echo "Either split the file by responsibility, or add it to the exceptions file with a reason."
  exit 1
fi

echo "Fitness check passed (limit: $MAX_LINES lines, $exceptions_used exempted)."
