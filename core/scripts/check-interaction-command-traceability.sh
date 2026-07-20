#!/bin/sh
# [汎用コア] interaction command traceability ガード — スタック非依存
# gatecrate-type: prevention
#
# WHY (issue #27, consumer実証: localmd-reader PR #18): ADR に「スクロールできるメニュー」の決定があり
# ScrollView の構造テストも在ったのに、相互作用モデルに scroll_menu コマンドが無く、縦スワイプが下方の
# アクションに実際に届くことを証明する挙動テストも無かった——**緑のモデルが実装を守らない**。本ゲートは
# 契約台帳の各行について次の連鎖を機械検査し、どこが切れても PR を止める:
#
#   state + command → モデル化された遷移 → 実装 path+locator → 挙動テスト path+locator
#
# 検出する切断: 契約に対応する遷移が無い／実装・テストの evidence ファイル欠落／locator のドリフト・消失／
# 実装マーカー（ソース中の "interaction-command: <name>"）に契約が無い／state|command 契約の重複。
#
# 増分採用モデル（issueの提案どおり）: 高リスク・新規追加・変更・探索由来の相互作用から契約を足す。
# 全歴史コマンドへの一括要求は「トレーサビリティを満たすだけのプレースホルダテスト」を誘発するため、しない。
# 台帳の雛形と採用基準: templates/interaction-command-contracts.psv.example
#
# 入力（PSV・"#"行/空行/ヘッダ行はスキップ・"-" は空とみなす）:
#   contracts   = state_id|command|implementation|implementation_locator|test|test_locator
#   transitions = from_state|command|to_state|event
#
# Config (optional, from harness.config.sh in the consumer repo root, or env; 引数が最優先):
#   INTERACTION_CONTRACTS   — 契約台帳（既定: docs/harness/interaction-command-contracts.psv）
#   INTERACTION_TRANSITIONS — 遷移表（既定: docs/harness/interaction-model-transitions.psv）
#   INTERACTION_SOURCE_ROOT — 実装マーカーの走査ルート（既定: src）
#
# Usage: sh check-interaction-command-traceability.sh [contracts.psv [transitions.psv [source-root]]]
# Exit:  0=pass  1=連鎖の切断  2=setup（spec・source-root の欠落＝黙って skip しない）
# Consumption model: repo root を git で解決するので kit(core/scripts/)でも消費者(scripts/)でも動く。
# 注: 失敗は fail() で明示集計するため set -e は使わない（条件&&fail パターンと衝突する）
set -u

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"

CONTRACTS="${1:-${INTERACTION_CONTRACTS:-docs/harness/interaction-command-contracts.psv}}"
TRANSITIONS="${2:-${INTERACTION_TRANSITIONS:-docs/harness/interaction-model-transitions.psv}}"
SOURCE_ROOT="${3:-${INTERACTION_SOURCE_ROOT:-src}}"

# resolve <path> — cwd 相対（テスト/CI の実行位置）→ repo root 相対の順に解決。見つからなければ空。
resolve() {
  if [ -e "$1" ]; then printf '%s' "$1"
  elif [ -e "$ROOT/$1" ]; then printf '%s' "$ROOT/$1"
  fi
}

C_FILE="$(resolve "$CONTRACTS")"
T_FILE="$(resolve "$TRANSITIONS")"
S_DIR="$(resolve "$SOURCE_ROOT")"
[ -n "$C_FILE" ] || { echo "interaction-command-traceability: missing contracts spec: $CONTRACTS" >&2; exit 2; }
[ -n "$T_FILE" ] || { echo "interaction-command-traceability: missing transitions spec: $TRANSITIONS" >&2; exit 2; }
[ -n "$S_DIR" ] && [ -d "$S_DIR" ] \
  || { echo "interaction-command-traceability: missing source directory: $SOURCE_ROOT" >&2; exit 2; }

failures=0
fail() { failures=$((failures + 1)); echo "interaction-command-traceability: FAIL: $1" >&2; }
blank() { case "$1" in ""|"-") return 0 ;; *) return 1 ;; esac; }

transition_exists() {
  awk -F'|' -v state="$1" -v command="$2" '
    $1 == state && $2 == command { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$T_FILE"
}

# check_evidence <key> <label> <path> <locator> — ファイル実在と locator の生存を検査
check_evidence() {
  ce_file="$(resolve "$3")"
  if [ -z "$ce_file" ] || [ ! -f "$ce_file" ]; then
    fail "$1 $2 file does not exist: $3"
  elif ! grep -F -q -- "$4" "$ce_file"; then
    fail "$1 $2 locator is absent: $4 (in $3)"
  fi
}

DUPLICATE_KEYS="$(awk -F'|' '
  $1 != "" && substr($1, 1, 1) != "#" && $1 != "state_id" {
    key = $1 "|" $2
    if (++seen[key] == 2) print key
  }
' "$C_FILE")"
for key in $DUPLICATE_KEYS; do
  fail "duplicate command contract: $key"
done

while IFS='|' read -r state command implementation impl_locator test test_locator extra; do
  case "$state" in ""|"#"*) continue ;; state_id) continue ;; esac
  [ -z "${extra:-}" ] || fail "$state/$command has too many columns (6 expected)"
  for value in "$state" "$command" "$implementation" "$impl_locator" "$test" "$test_locator"; do
    blank "$value" && { fail "$state/$command has a required empty field"; break; }
  done
  key="$state|$command"
  transition_exists "$state" "$command" || fail "$key has no modeled transition"
  check_evidence "$key" "implementation" "$implementation" "$impl_locator"
  check_evidence "$key" "behavior-test" "$test" "$test_locator"
done < "$C_FILE"

# 逆向きの検査: 実装に "interaction-command: X" マーカーが在るのに契約が無い＝台帳の取りこぼし
MARKERS="$(grep -R -h -E 'interaction-command:[[:space:]]*[a-z0-9_-]+' "$S_DIR" 2>/dev/null \
  | sed -n 's/^.*interaction-command:[[:space:]]*\([a-z0-9_-]*\).*$/\1/p' | sort -u)"
for command in $MARKERS; do
  if ! awk -F'|' -v command="$command" \
      '$2 == command { found = 1 } END { exit(found ? 0 : 1) }' "$C_FILE"; then
    fail "implemented command marker has no contract: $command"
  fi
done

if [ "$failures" -gt 0 ]; then
  echo "interaction-command-traceability: $failures model/implementation/test gap(s) found." >&2
  exit 1
fi
echo "interaction-command-traceability: modeled commands have implementation and behavior-test evidence."
