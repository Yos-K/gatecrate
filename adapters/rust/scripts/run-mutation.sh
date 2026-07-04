#!/bin/sh
# [Rustアダプタ] cargo-mutants ミューテーションゲート（consumable form）
# cargo-mutants は生き残った mutant があると非0で終了する＝クリーンなゲート（floor 不要）。
# 低価値な mutant は Cargo.toml の [package.metadata.mutants] exclude で除外する。
set -eu
ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
cd "$ROOT"

# A+B 戦略（docs/mutation-strategy.md）: mutation-scope.sh（消費者では scripts/ の sibling）が diff/full を決める。
# diff モード = PR で変更行だけ（cargo-mutants は --in-diff をネイティブ対応）・変更 *.rs 無しなら SKIP。
SCOPE="$(dirname -- "$0")/mutation-scope.sh"
if [ -f "$SCOPE" ] && [ "$(sh "$SCOPE" mode)" = diff ]; then
  [ -n "$(sh "$SCOPE" changed '*.rs')" ] || { echo "run-mutation: no changed *.rs vs base — skipping (diff scope)"; exit 0; }
  sh "$SCOPE" diff > "${TMPDIR:-/tmp}/gatecrate-mutation.diff"
  exec cargo mutants --no-shuffle --in-diff "${TMPDIR:-/tmp}/gatecrate-mutation.diff"
fi
cargo mutants --no-shuffle
