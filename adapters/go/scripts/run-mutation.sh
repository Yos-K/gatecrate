#!/bin/sh
# [Goアダプタ] gremlins ミューテーションゲート（consumable form）
set -eu
ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
MUTATION_THRESHOLD="${MUTATION_THRESHOLD:-80}"
cd "$ROOT"

# A+B 戦略（docs/mutation-strategy.md）: gremlins にネイティブ diff は無いため diff モード = 変更 *.go の
# パッケージディレクトリだけに gremlins を絞る（path-scoped・各パッケージが閾値を満たす必要あり）。変更 *.go 無しなら SKIP。
SCOPE="$(dirname -- "$0")/mutation-scope.sh"
if [ -f "$SCOPE" ] && [ "$(sh "$SCOPE" mode)" = diff ]; then
  changed_go="$(sh "$SCOPE" changed '*.go')"
  [ -n "$changed_go" ] || { echo "run-mutation: no changed *.go vs base — skipping (diff scope)"; exit 0; }
  dirs="$(printf '%s\n' "$changed_go" | while IFS= read -r f; do dirname "$f"; done | sort -u)"
  for d in $dirs; do
    echo "run-mutation: gremlins on ./$d (diff scope)"
    gremlins unleash --threshold-efficacy "$MUTATION_THRESHOLD" "./$d"
  done
  exit 0
fi
# gremlins は efficacy（捕捉率）が閾値未満だと非0で終了する。
gremlins unleash --threshold-efficacy "$MUTATION_THRESHOLD"
