#!/bin/sh
# [Lean4アダプタ] lake build ゲート（型検査 + proof チェック・consumable form）
# Lean4 では build がそのまま型/証明の検査。proof-checked `example` が落ちれば build が失敗する。
# coverage/mutation は定理証明系には不適なので、build/typecheck を唯一のゲートとする。
set -eu
ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
cd "$ROOT"
lake build
