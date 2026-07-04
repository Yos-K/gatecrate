#!/bin/sh
# [汎用core] PR を開く前にローカルでゲートを走らせるランナー — スタック非依存
#
# WHY: CI でしか落ちない受け入れ基準違反は、フィードバックが遅く往復コストが高い。
# 本スクリプトは CI の fitness（衛生）ゲートと同じ純シェルのチェック群をローカルで
# 走らせ、一つの簡潔な合否サマリを出す。PR を開く前に流せば、落ちる基準が CI ではなく
# 手元で捕まる。
#
# ゲートの導出: チェックは「インストール済みのスクリプトから自動導出」する。
# 各ゲートは対応するスクリプトが存在する場合のみ実行し、無ければ SKIP する。
# これにより、core のみ・adapter 入り・部分採用のどの消費者でも、追加設定なしで
# 「入っているものだけ」を流せる（ハードコードしたゲート一覧の同期ずれを避ける）。
#
# 対象スクリプト（scripts/ にあれば実行）:
#   check-conventional-title.sh   — PR タイトルの Conventional Commits 検証（引数で渡した時のみ）
#   check-file-line-limit.sh      — ファイル行数上限
#   check-hard-constraints.sh     — プロジェクト固有のハード制約
#   check-no-committed-secrets.sh — コミット済みシークレット検出
#   check-doc-currency.sh         — ドキュメント整合性
#   check-rule-doc-currency.sh    — ルールドキュメント整合性
#   check-test-smells.sh          — テストスメル（純 grep。CI の test ジョブのミラー）
#
# Usage:
#   sh pr-preflight.sh ["<conventional-pr-title>"]
#
# タイトル引数を渡すと Conventional Commits タイトルチェックを有効化する（省略可）。
set -u

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/.." && pwd))"
cd "$ROOT"
SCRIPTS_DIR="$(dirname -- "$0")"

TITLE="${1:-}"
failures=0
skipped=0
results=""

record() {
  # record <status: PASS|FAIL|SKIP> <label>
  results="${results}  $1  $2
"
  if [ "$1" = "FAIL" ]; then
    failures=$((failures + 1))
  elif [ "$1" = "SKIP" ]; then
    skipped=$((skipped + 1))
  fi
}

section() {
  printf '\n=== %s ===\n' "$1"
}

# Run a gate only if its script is installed; otherwise SKIP (not FAIL).
run_gate() {
  label="$1"
  script="$2"
  if [ ! -f "$SCRIPTS_DIR/$script" ]; then
    record SKIP "$label ($script not installed)"
    return
  fi
  section "$label"
  if sh "$SCRIPTS_DIR/$script"; then
    record PASS "$label"
  else
    record FAIL "$label"
  fi
}

# 1. Conventional Commits title — only when a title is provided.
LABEL="Conventional Commits title"
if [ -n "$TITLE" ] && [ -f "$SCRIPTS_DIR/check-conventional-title.sh" ]; then
  section "$LABEL"
  if printf '%s\n' "$TITLE" | sh "$SCRIPTS_DIR/check-conventional-title.sh"; then
    record PASS "$LABEL"
  else
    record FAIL "$LABEL"
  fi
elif [ -z "$TITLE" ]; then
  record SKIP "$LABEL (no title argument)"
else
  record SKIP "$LABEL (check-conventional-title.sh not installed)"
fi

# 2..N: derived from what's installed.
run_gate "Per-file line limit" "check-file-line-limit.sh"
run_gate "Hard constraints" "check-hard-constraints.sh"
run_gate "No committed secrets" "check-no-committed-secrets.sh"
run_gate "Documentation currency" "check-doc-currency.sh"
run_gate "Rule documentation currency" "check-rule-doc-currency.sh"
run_gate "Test smells" "check-test-smells.sh"

printf '\n==================== preflight summary ====================\n'
printf '%s' "$results"
printf '===========================================================\n'

if [ "$failures" -eq 0 ]; then
  if [ "$skipped" -gt 0 ]; then
    printf 'Executed gates passed (%d skipped: not installed or no title).\n' "$skipped"
    exit 0
  fi
  printf 'All gates passed. Safe to open a PR.\n'
  exit 0
fi

printf '%d gate(s) failed. Fix before opening a PR (CI would reject this).\n' "$failures"
exit 1
