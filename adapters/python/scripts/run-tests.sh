#!/bin/sh
# [Pythonアダプタ] pytest + coverage ゲート（uv 実行）
# Runs the test suite with a coverage floor. Consumable form: the repo root is resolved with
# `git rev-parse` so the same file works in this kit and when installed into a consumer's
# `scripts/`, and it sources `harness.config.sh` from the repo root if present.
#
# Config (optional, from harness.config.sh):
#   COVERAGE_SOURCE     — coverage measurement target (default: src)
#   COVERAGE_THRESHOLD  — fail-under percentage (default: 80)
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
COVERAGE_SOURCE="${COVERAGE_SOURCE:-src}"
COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-80}"

cd "$ROOT"
uv run pytest --cov="$COVERAGE_SOURCE" --cov-report=term-missing --cov-fail-under="$COVERAGE_THRESHOLD"
