#!/bin/sh
# [汎用コア][shim] イベントストーミング HTML ビューア生成器（ツール・非ゲート） — スタック非依存
#
# 実装は Rust（crates/gatecrate-model が源泉の文法、crates/gatecrate-render が射影）。
# このシムは呼び出し面と exit code 契約（0=生成 / 1=引数不足 / 2=ファイル欠落）を固定し、
# 実装だけを差し替える。移植の経緯と等価性の証明は docs/design/rust-port-plan.md。
#
# Usage: sh es-render-html.sh <asis.es> [tobe.es] [map.cmap] [loops.cld] [analysis.md ...] > model.html
#   各モデルの隣に <name>.spec があれば「箱の内側(入力→処理→出力)」として自動的に読む。
set -eu

KIT_ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd))"

BIN="${GATECRATE_BIN:-}"
if [ -z "$BIN" ]; then
  for candidate in "$KIT_ROOT/target/release/gatecrate" "$KIT_ROOT/target/debug/gatecrate"; do
    if [ -x "$candidate" ]; then BIN="$candidate"; break; fi
  done
fi
if [ -z "$BIN" ]; then BIN="$(command -v gatecrate 2>/dev/null || true)"; fi
if [ -z "$BIN" ]; then
  echo "es-render-html: gatecrate binary not found — run 'cargo build --release' in the kit, or set GATECRATE_BIN" >&2
  exit 2
fi

exec "$BIN" es render-html "$@"
