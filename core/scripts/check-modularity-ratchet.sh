#!/bin/sh
# [汎用core] check-modularity-ratchet.sh — Balanced Coupling バランス違反の ratchet ゲート
# gatecrate-type: prevention  (新規のバランス違反エッジを reject する予防型；発火0=悪化なし=正常)
#
# WHY: モジュール性の絶対 floor（RED=0）をレガシーに入れると初日に必ず落ち、消費側はゲートごと外して
# シグナルの価値はゼロのまま構造も良くならない（diff-coverage が塞いだのと同じ轍）。本ゲートは既知の
# バランス違反（強い×遠い×変動 = measure-modularity.sh の RED エッジ）を modularity-baseline.tsv
# （コミット済み・レビューで正当化された負債台帳）に凍結し、「台帳に無い新規の RED エッジ」だけを
# reject する。＝アーキテクチャ品質のボーイスカウトルールの機械強制: 既存負債は責めないが、新しい
# 「遠くの変動源への強い依存」はマージさせない。
#
# 判定は measure-modularity.sh の決定論出力（modularity-red.tsv）にのみ基づく。strength の意味論的分類は
# 判断層（modularity-review スキル）が modularity-strength.tsv に証拠つきで供給する——本ゲート自身は
# 一切判断しない（決定論は機械・判断はエージェント・承認は人間）。
#
# Usage:
#   sh check-modularity-ratchet.sh                   # gate: 新規 RED があれば exit 1
#   sh check-modularity-ratchet.sh --emit-baseline   # brownfield 初期化: 現在の RED を台帳へ凍結
#
# Config (env, from harness.config.sh or CLI env):
#   MODULARITY_BASELINE_FILE — 負債台帳 (default: <root>/modularity-baseline.tsv; 無ければ空=greenfield)
#   MODULARITY_RED_FILE      — test seam: measure を呼ばず RED 集合(TSV)を直接読む
#   (計測側の設定は measure-modularity.sh のヘッダを参照)
# Exit: 0=悪化なし / 1=新規バランス違反 / 2=setup error（計測不能を黙って pass にしない）
# Consumption model: repo root を git で解決するので kit(core/scripts/)でも消費者(scripts/)でも動く。
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"

BASELINE="${MODULARITY_BASELINE_FILE:-$ROOT/modularity-baseline.tsv}"
RED="${MODULARITY_RED_FILE:-}"

if [ -z "$RED" ]; then
  if ! sh "$(dirname -- "$0")/measure-modularity.sh" > "$ROOT/build/quality/modularity-report.txt" 2>&1; then
    echo "modularity-ratchet: ERROR — measure-modularity.sh failed; cannot gate without a measurement." >&2
    echo "  See $ROOT/build/quality/modularity-report.txt (COUPLING_PKG_PREFIX set? sources present?)." >&2
    exit 2
  fi
  RED="$ROOT/build/quality/modularity-red.tsv"
fi
if [ ! -f "$RED" ]; then
  echo "modularity-ratchet: ERROR — RED set not found: $RED (run measure-modularity.sh first)." >&2
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Edge keys are the first two columns (src_pkg, dst_pkg).
cut -f1,2 "$RED" | sort -u > "$WORK/current"
if [ -f "$BASELINE" ]; then
  grep -v '^[[:space:]]*#' "$BASELINE" | grep -v '^[[:space:]]*$' | cut -f1,2 | sort -u > "$WORK/base"
else
  : > "$WORK/base"
fi

if [ "${1:-}" = "--emit-baseline" ]; then
  {
    echo "# modularity-baseline.tsv — 既知のバランス違反エッジ台帳（src_pkg <TAB> dst_pkg）"
    echo "# check-modularity-ratchet.sh はここに無い新規 RED だけを reject する。追記はレビューで正当化すること。"
    cat "$WORK/current"
  } > "$BASELINE"
  n=$(wc -l < "$WORK/current" | tr -d ' ')
  echo "modularity-ratchet: baseline written to $BASELINE ($n known edge(s) frozen). Commit it."
  exit 0
fi

NEW="$(comm -23 "$WORK/current" "$WORK/base")"
STALE="$(comm -13 "$WORK/current" "$WORK/base")"

if [ -n "$STALE" ]; then
  echo "modularity-ratchet: NOTE — baseline entries no longer RED (debt repaid; remove them to tighten the ratchet):"
  printf '%s\n' "$STALE" | sed 's/^/  /; s/	/ -> /'
fi

if [ -n "$NEW" ]; then
  echo "modularity-ratchet: FAIL — new Balanced-Coupling violation(s): strong x distant x volatile edge(s) not in the baseline." >&2
  printf '%s\n' "$NEW" | while IFS="$(printf '\t')" read -r s d; do
    awk -F'\t' -v s="$s" -v d="$d" '$1 == s && $2 == d {
      printf "  %s -> %s  (strength=%s, distance=%s, volatility=%s)\n", $1, $2, $4, $5, $6 }' "$RED" >&2
  done
  echo "  直し方（どれか1つ）:" >&2
  echo "   1. 結合を弱める — 内部知識の共有をやめ contract(公開API/イベント)経由にする" >&2
  echo "   2. 近づける — 一緒に変わるものは同じモジュール境界の中へ移す" >&2
  echo "   3. 分類を見直す — 実は contract 結合なら modularity-strength.tsv に証拠つきで分類する" >&2
  echo "   4. 意識的な負債として台帳へ — modularity-baseline.tsv に追記し、レビューで正当化する" >&2
  exit 1
fi

cur_n=$(wc -l < "$WORK/current" | tr -d ' ')
if [ "$cur_n" -eq 0 ]; then
  echo "modularity-ratchet: no RED edges at all — coupling is in balance. pass."
else
  echo "modularity-ratchet: no new balance violations ($cur_n RED edge(s), all accepted in the baseline). pass."
fi
