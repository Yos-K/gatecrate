#!/bin/sh
# [汎用core] ミューテーション範囲の解決 — diff(PR) / full(nightly) の共通エンジン — スタック非依存
# （これはゲートでなくミューテーション補助ツール＝classify の NON_GATE に登録済み・not-a-gate 扱い）
#
# WHY (docs/mutation-strategy.md / A+B 戦略): ミューテーションを毎PRで全コード回すと分単位で遅い。
# A=差分限定(PR は変更分だけミューテーション=秒)・B=フルは nightly/trunk に回す、という二段戦略の
# 「範囲決定」を**全アダプタで1度だけ**実装する。各 adapter の run-mutation.sh はこれを呼び、結果を
# 自分のツールのフラグ（cargo-mutants --in-diff / stryker --since / mutmut --paths-to-mutate …）に写すだけ。
#
# 後方互換: 既定は full（MUTATION_SCOPE 未設定の既存消費者は従来どおり全コード）。diff は opt-in。
#
# Env:
#   MUTATION_SCOPE      diff | full   （既定 full）
#   MUTATION_DIFF_BASE  diff モードの基準 ref（既定: origin の既定ブランチ→無ければ main）
#
# Commands:
#   mutation-scope.sh mode                 -> "diff" または "full" を出力
#   mutation-scope.sh base                 -> 解決した基準 ref を出力（diff モード用）
#   mutation-scope.sh changed [<glob>...]  -> base..HEAD で変更されたファイルを1行ずつ出力（glob で絞れる・削除は除外）
#   mutation-scope.sh diff                 -> base..HEAD の unified diff を stdout に出力（--in-diff を取るツール用）
#
# 呼び出し側の契約: mode=full ならツールを全範囲で実行。mode=diff なら changed が空＝変更無し＝SKIP、
# 非空なら diff/changed をツールの差分フラグへ渡す。
set -eu

mode() { case "${MUTATION_SCOPE:-full}" in diff) echo diff ;; *) echo full ;; esac; }

# resolve_base: MUTATION_DIFF_BASE を最優先。無ければ origin の既定ブランチ、無ければ main。
resolve_base() {
  if [ -n "${MUTATION_DIFF_BASE:-}" ]; then echo "$MUTATION_DIFF_BASE"; return 0; fi
  db="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
  [ -n "$db" ] || db=main
  if git rev-parse --verify --quiet "origin/$db" >/dev/null 2>&1; then echo "origin/$db"; else echo "$db"; fi
}

# changed [glob...]: base..HEAD で変更（追加/変更、削除は除外）されたファイルを glob で絞って出力。
changed() {
  base="$(resolve_base)"
  files="$(git diff --name-only --diff-filter=d "$base"...HEAD 2>/dev/null || git diff --name-only --diff-filter=d "$base" 2>/dev/null || true)"
  [ -n "$files" ] || return 0
  if [ "$#" -eq 0 ]; then printf '%s\n' "$files"; return 0; fi
  printf '%s\n' "$files" | while IFS= read -r f; do
    for g in "$@"; do
      # shellcheck disable=SC2254  # glob は意図的にパターンとして使う
      case "$f" in $g) echo "$f"; break ;; esac
    done
  done
}

cmd="${1:-mode}"
case "$cmd" in
  mode)    mode ;;
  base)    resolve_base ;;
  changed) shift 2>/dev/null || true; changed "$@" ;;
  diff)    base="$(resolve_base)"; git diff --diff-filter=d "$base"...HEAD 2>/dev/null || git diff --diff-filter=d "$base" 2>/dev/null || true ;;
  *) echo "mutation-scope: unknown command '$cmd' (mode|base|changed|diff)" >&2; exit 2 ;;
esac
