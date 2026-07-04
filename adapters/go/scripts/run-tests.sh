#!/bin/sh
# [Goアダプタ] go test + coverage フロアゲート（consumable form）
set -eu
ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-80}"
cd "$ROOT"
go test -coverprofile=coverage.out ./...
pct="$(go tool cover -func=coverage.out | awk '/^total:/ {gsub("%","",$3); print $3}')"
echo "Total coverage: ${pct}% (floor ${COVERAGE_THRESHOLD}%)"
awk -v p="$pct" -v t="$COVERAGE_THRESHOLD" 'BEGIN{ if (p+0 < t+0) { print "Coverage below floor."; exit 1 } }'
