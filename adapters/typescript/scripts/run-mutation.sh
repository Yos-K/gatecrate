#!/bin/sh
# [TypeScriptアダプタ] Stryker ミューテーションゲート（consumable form）
set -eu
ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
cd "$ROOT"
[ -d node_modules ] || npm ci 2>/dev/null || npm install

# A+B 戦略（docs/mutation-strategy.md）: diff モード = Stryker の --since <base>（変更ファイルだけミューテーション）。
# 変更ソース無しなら SKIP。Stryker は score が break 閾値（stryker.config.json）未満だと非0で終了する。
SCOPE="$(dirname -- "$0")/mutation-scope.sh"
if [ -f "$SCOPE" ] && [ "$(sh "$SCOPE" mode)" = diff ]; then
  [ -n "$(sh "$SCOPE" changed '*.ts' '*.tsx' '*.js' '*.jsx' '*.mts' '*.cts')" ] \
    || { echo "run-mutation: no changed JS/TS sources vs base — skipping (diff scope)"; exit 0; }
  exec npx stryker run --since "$(sh "$SCOPE" base)"
fi
npx stryker run
