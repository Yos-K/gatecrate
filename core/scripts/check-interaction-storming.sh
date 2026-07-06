#!/bin/sh
# [汎用コア] interaction-storming 完結性ゲート（prevention） — スタック非依存
# gatecrate-type: prevention
#
# WHY: 「ダイアログに閉じる手段がない」「別フォルダを選び直せない」——ユーザー操作の流れが完結しない欠陥は、
# UI自動探索で見つかるが、探索そのものをゲートにすると重く不安定。**探索はゲートにしない。探索から蒸留された
# 状態表（machine-readableなflow表）の整合性だけを軽量ゲートにする**（consumer実証: localmd-reader #6）。
# 各画面状態に「完結(completion)・離脱(escape)・回復(recovery)」の手段と evidence が揃っているかを機械検査する。
#
# 入力（PSV・1行1状態）:
#   flow_id|state_id|event|available_commands|completion_command|escape_command|recovery_command|evidence
#   - available_commands はカンマ区切り。completion/escape/recovery はその中に含まれること
#   - evidence はカンマ区切りの実在パス（探索記録・実装ファイル）
#   - "#" 行・空行・ヘッダ行(flow_id)はスキップ。"-" は空とみなし必須違反
#
# Config: INTERACTION_FLOWS — flow表のパス（harness.config.sh か環境変数。引数が最優先）
# Usage: sh check-interaction-storming.sh [flows.psv]   （違反は行番号つきで報告し exit 1）
# 注: 失敗は fail() で明示集計するため set -e は使わない（条件&&fail パターンと衝突する）
set -u

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
SPEC="${1:-${INTERACTION_FLOWS:-}}"
[ -n "$SPEC" ] || { echo "check-interaction-storming: flow表が未指定（引数か INTERACTION_FLOWS で指定）" >&2; exit 2; }
[ -f "$SPEC" ] || { echo "check-interaction-storming: not found: $SPEC" >&2; exit 2; }

failures=0; line_no=0
fail() { failures=$((failures + 1)); echo "  [ERROR] line $line_no: $1"; }
blank() { case "$1" in ""|"-") return 0 ;; *) return 1 ;; esac; }
require() { blank "$2" && fail "$1 が必須（状態に $1 が無い＝流れが完結しない）"; }
available() { # <label> <command> <available_csv>
  blank "$2" && return 0
  case ",$3," in *",$2,"*) : ;; *) fail "$1 \"$2\" が available_commands \"$3\" に無い" ;; esac
}

echo "=== check-interaction-storming: $SPEC ==="
while IFS='|' read -r flow_id state_id event avail completion escape recovery evidence extra; do
  line_no=$((line_no + 1))
  case "$flow_id" in ""|"#"*) continue ;; flow_id) continue ;; esac
  [ -n "${extra:-}" ] && fail "列が多すぎる（8列: flow_id|state_id|event|available|completion|escape|recovery|evidence）"
  require "flow_id" "$flow_id"; require "state_id" "$state_id"; require "event" "$event"
  require "available_commands" "$avail"
  require "completion_command（完結手段）" "$completion"
  require "escape_command（離脱手段）" "$escape"
  require "recovery_command（回復手段）" "$recovery"
  require "evidence" "$evidence"
  available "completion_command" "$completion" "$avail"
  available "escape_command" "$escape" "$avail"
  available "recovery_command" "$recovery" "$avail"
  if ! blank "$evidence"; then
    OLDIFS="$IFS"; IFS=','
    for p in $evidence; do
      IFS="$OLDIFS"
      if blank "$p"; then fail "evidence に空のパスがある"
      elif [ ! -e "$ROOT/$p" ] && [ ! -e "$p" ]; then fail "evidence が実在しない: $p"; fi
      IFS=','
    done
    IFS="$OLDIFS"
  fi
done < "$SPEC"

if [ "$failures" -gt 0 ]; then
  echo "---- ERROR=$failures ----（各状態に 完結・離脱・回復 の手段と evidence を揃える）"
  exit 1
fi
echo "  OK: 全状態に 完結・離脱・回復 の手段と evidence が揃っている"
echo "---- ERROR=0 ----"
