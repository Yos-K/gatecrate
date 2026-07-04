#!/bin/sh
# [汎用コア] Conventional Commits タイトル検証 — スタック非依存
# Validate a Conventional Commits title.
#
# Reads the title from the first argument, or from stdin if no argument is given.
# Exits non-zero with guidance when the title is not a valid Conventional Commits
# subject. Shared by scripts/open-pr.sh and the CI pull-request title check so the
# accepted variants stay identical in both places.
set -eu

if [ "$#" -ge 1 ]; then
  TITLE="$1"
else
  # Keep the read value even when the input has no trailing newline.
  IFS= read -r TITLE || true
fi

# <type>[optional scope][!]: <description>
PATTERN='^(feat|fix|docs|test|refactor|build|ci|chore|perf|style|revert)(\([A-Za-z0-9._/-]+\))?!?: .+'

if ! printf '%s\n' "$TITLE" | grep -Eq "$PATTERN"; then
  echo "Invalid Conventional Commits title: $TITLE" >&2
  echo "Expected: <type>[optional scope][!]: <description>" >&2
  echo "Types: feat, fix, docs, test, refactor, build, ci, chore, perf, style, revert" >&2
  echo "Example: ci: add device smoke workflow" >&2
  exit 1
fi

echo "Conventional Commits title ok: $TITLE"
