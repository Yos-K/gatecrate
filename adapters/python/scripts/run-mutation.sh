#!/bin/sh
# [Pythonアダプタ] mutmut ミューテーションゲート（uv 実行）
# Python analog of the android-jvm run-mutation-tests.sh (PITest).
#
# Porting note (why this wrapper exists): unlike PITest's `--mutationThreshold`, `mutmut run`
# exits 0 even when mutants survive — there is no clean threshold-exit. So we read mutmut's
# CI/CD stats JSON and enforce the floor ourselves. Also, mutmut writes a `mutants/` working
# copy of the project; configure pytest to ignore it (testpaths/norecursedirs) or pytest
# collection collides on duplicate test module names.
#
# Config:
#   MUTATION_THRESHOLD  — fail floor percentage (default: 80; never lower it)
# The mutated targets come from pyproject `[tool.mutmut] source_paths`; exclude low-value
# modules (string catalogs, generated code) there, the analog of EXCLUDED_CLASSES.
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
MUTATION_THRESHOLD="${MUTATION_THRESHOLD:-80}"

cd "$ROOT"

# A+B 戦略（docs/mutation-strategy.md）: diff モード = 変更 *.py だけを --paths-to-mutate でミューテーション
# （mutmut にネイティブ diff は無いため path-scoped）。変更 *.py 無しなら SKIP。
SCOPE="$(dirname -- "$0")/mutation-scope.sh"
MUTMUT_SCOPE=""
if [ -f "$SCOPE" ] && [ "$(sh "$SCOPE" mode)" = diff ]; then
  changed_py="$(sh "$SCOPE" changed '*.py')"
  [ -n "$changed_py" ] || { echo "run-mutation: no changed *.py vs base — skipping (diff scope)"; exit 0; }
  MUTMUT_SCOPE="--paths-to-mutate $(printf '%s' "$changed_py" | paste -sd, -)"
fi
# shellcheck disable=SC2086  # MUTMUT_SCOPE は意図的に分割（空なら全範囲）
uv run mutmut run $MUTMUT_SCOPE || true   # do not trust run's exit code; the threshold check is below
uv run mutmut export-cicd-stats >/dev/null
uv run python - "mutants/mutmut-cicd-stats.json" "$MUTATION_THRESHOLD" <<'PY'
import json, sys
stats = json.load(open(sys.argv[1]))
floor = float(sys.argv[2])
total = stats["total"] or 1
killed = stats["killed"]
score = killed / total * 100
print(f"Mutation score: {score:.1f}% ({killed}/{total} killed, {stats['survived']} survived), floor={floor}%")
if stats["survived"]:
    print("SURVIVED hotspots: weak/missing assertions — add a test, or exclude low-value")
    print("targets in pyproject [tool.mutmut] source_paths. Never lower the floor.")
sys.exit(0 if score >= floor else 1)
PY
