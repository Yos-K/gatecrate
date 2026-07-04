#!/bin/sh
# [汎用core] ファイル行数上限チェック（言語非依存）
# Fitness Function: enforce a per-file line-count limit across configurable globs.
#
# This is the stack-agnostic sibling of adapters/android-jvm/scripts/check-file-sizes.sh
# (which is hardwired to src/**.java). It scans caller-chosen paths and name patterns,
# so it enforces the same 300-line rule on shell scripts, docs, configs — anything.
# That is what lets the kit dogfood its OWN 300-line rule on its shell scripts.
#
# Config (optional, from harness.config.sh in the consumer repo root, or env):
#   FILE_LINE_LIMIT       — line limit (default: FITNESS_MAX_LINES, else 300)
#   FILE_LINE_PATHS       — space-separated roots to scan (default: ".")
#   FILE_LINE_NAMES       — space-separated find -name patterns (default: "*.sh")
#   FILE_LINE_EXCEPTIONS  — path to exceptions file (default: scripts/file-line-exceptions.txt)
#
# Consumption model: repo root is resolved with `git rev-parse` so the SAME file
# works in this kit (core/scripts/) or installed into a consumer (scripts/) —
# no install-time path rewriting, which keeps kit<->consumer sync diff-free.
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
MAX_LINES="${FILE_LINE_LIMIT:-${FITNESS_MAX_LINES:-300}}"
SCAN_PATHS="${FILE_LINE_PATHS:-.}"
SCAN_NAMES="${FILE_LINE_NAMES:-*.sh}"
EXCEPTIONS_FILE="${FILE_LINE_EXCEPTIONS:-$ROOT/scripts/file-line-exceptions.txt}"

# Disable pathname expansion (noglob). SCAN_NAMES holds GLOB PATTERNS ("*.sh *.md") that are
# word-split unquoted below (for pat in $SCAN_NAMES) — without set -f the shell would EXPAND those
# patterns against the cwd, turning them into the literal root-level filenames that happen to match
# (install.sh, CHANGELOG.md, …). The find would then only look for those exact basenames, silently
# skipping every subdir file (core/scripts/*.sh, .claude/**.md, …) — the gate would scan almost
# nothing yet still pass. set -f keeps the patterns literal so they reach find as real -name globs.
set -f

is_exception() {
  target="$1"
  [ -f "$EXCEPTIONS_FILE" ] || return 1
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    [ "$target" = "$line" ] && return 0
  done < "$EXCEPTIONS_FILE"
  return 1
}

# Build the find name filter (-name A -o -name B ...) from FILE_LINE_NAMES.
build_name_args() {
  first=1
  for pat in $SCAN_NAMES; do
    if [ "$first" = 1 ]; then first=0; else printf ' -o '; fi
    # Quote the pattern so eval does not glob-expand it against the current dir.
    printf -- "-name '%s'" "$pat"
  done
}

violations=0
exceptions_used=0

for sub in $SCAN_PATHS; do
  base="$ROOT/$sub"
  [ -e "$base" ] || continue
  # -prune .git so we never flag vendored/VCS files. eval expands the OR'd -name group.
  files=$(eval "find \"\$base\" -name .git -prune -o -type f \\( $(build_name_args) \\) -print" 2>/dev/null || true)
  [ -n "$files" ] || continue
  for file in $files; do
    lines=$(wc -l < "$file")
    if [ "$lines" -gt "$MAX_LINES" ]; then
      relative="${file#$ROOT/}"
      relative="${relative#./}"  # normalize when scanned via "." (find emits ./path)
      if is_exception "$relative"; then
        echo "EXEMPT  $lines lines  $relative"
        exceptions_used=$((exceptions_used + 1))
      else
        echo "FAIL    $lines lines  $relative (limit: $MAX_LINES)"
        violations=$((violations + 1))
      fi
    fi
  done
done

echo ""
if [ "$violations" -gt 0 ]; then
  echo "File-line check FAILED: $violations file(s) exceed the $MAX_LINES line limit."
  echo "Split the file by responsibility, or add it to $EXCEPTIONS_FILE with a reason."
  exit 1
fi

echo "File-line check passed (limit: $MAX_LINES lines, $exceptions_used exempted)."
