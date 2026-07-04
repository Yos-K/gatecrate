#!/bin/sh
# [汎用core] テスト scaffold のコンパイル検査（実行せずビルドのみ・スタック非依存）
# gatecrate-type: detection  (非0 exit でブロックし、コンパイル失敗=開発中に起きる事象で発火する)
# An IGNORED/skipped test is still BUILT — `cargo test`, `go test`, `tsc` compile every test file
# before deciding what to run. So a pending scaffold that does not compile breaks the build red just
# like a failing one. This script BUILDS the tests WITHOUT running them, per the detected stack, and
# exits non-zero on a compile error. The harness-rule-reflect `scaffold-compiles` quality gate runs
# it, so TAKT re-invokes the step to fix a non-compiling scaffold (the demo finding it was born from).
#
# Command chosen by (in order):
#   1. harness.config.sh TEST_COMPILE_CMD — explicit override (any stack / monorepo).
#   2. autodetect: Cargo.toml -> `cargo test --no-run` · go.mod -> `go test -run=__nomatch__` ·
#      tsconfig.json -> `tsc --noEmit` · pyproject.toml/setup.py -> `python -m compileall` on .py.
#   3. nothing recognized -> notice + exit 0 (cannot check; set TEST_COMPILE_CMD to enforce).
#
# Modes:
#   check-test-compiles.sh           run the build-no-run check; its exit code is the result.
#   check-test-compiles.sh --print   print the detected stack + the command, exit 0 (for tests).
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
cd "$ROOT"

MODE="run"
[ "${1:-}" = "--print" ] && MODE="print"

# Decide the build-no-run command and a label for the detected stack.
if [ -n "${TEST_COMPILE_CMD:-}" ]; then
  stack="config"
  cmd="$TEST_COMPILE_CMD"
elif [ -f Cargo.toml ]; then
  stack="rust"
  cmd="cargo test --no-run -q"
elif [ -f go.mod ]; then
  stack="go"
  cmd="go test ./... -run=__nomatch__ -count=1"
elif [ -f tsconfig.json ]; then
  stack="typescript"
  cmd="npx --no-install tsc --noEmit"
elif [ -f pyproject.toml ] || [ -f setup.py ]; then
  stack="python"
  # Compile by DIRECTORY (not a shell-interpolated file list), so a path with spaces / newlines /
  # shell metacharacters is never re-parsed by the shell. -x skips vendored/build dirs (a regex
  # matched against each path). compileall exits non-zero on any syntax error.
  cmd="python -m compileall -q -x '(\\.venv|/venv/|\\.git/|/build/|/dist/|node_modules|/target/)' ."
else
  stack="none"
  cmd=""
fi

if [ "$MODE" = "print" ]; then
  echo "stack: $stack"
  echo "cmd: ${cmd:-<none>}"
  exit 0
fi

if [ -z "$cmd" ]; then
  echo "check-test-compiles: no rust/go/ts/python build detected — cannot verify the scaffold compiles."
  echo "Set TEST_COMPILE_CMD in harness.config.sh to a build-no-run command to enforce it."
  exit 0
fi

echo "check-test-compiles ($stack): $cmd"
sh -c "$cmd"
echo "check-test-compiles passed: the test scaffolds compile."
