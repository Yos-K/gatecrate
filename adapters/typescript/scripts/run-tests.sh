#!/bin/sh
# [TypeScriptアダプタ] vitest + coverage フロアゲート（consumable form）
set -eu
ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-80}"
cd "$ROOT"
[ -d node_modules ] || npm ci 2>/dev/null || npm install
npx vitest run --coverage
node -e "const p=require('./coverage/coverage-summary.json').total.lines.pct; \
console.log('Total line coverage: '+p+'% (floor ${COVERAGE_THRESHOLD}%)'); \
process.exit(p>=${COVERAGE_THRESHOLD}?0:1)"
