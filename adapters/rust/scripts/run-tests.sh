#!/bin/sh
# [Rustアダプタ] cargo test + coverage フロアゲート（cargo-llvm-cov、consumable form）
set -eu
ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-80}"
cd "$ROOT"
# cargo-llvm-cov runs the tests and enforces the floor with a clean non-zero exit.
cargo llvm-cov --fail-under-lines "$COVERAGE_THRESHOLD"
