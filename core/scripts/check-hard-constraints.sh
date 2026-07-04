#!/bin/sh
# [汎用core] ハード制約（コンテンツ不変条件）ゲート — スタック非依存
#
# WHY: プロダクトの「絶対に破ってはいけない設計判断」をソースレベルで機械強制し、PR を fail-fast させる。
# これらは「正しさ」（テストが見る）ではなく「意図の境界」——人や AI が善意で破りうる（例: オフライン
# reader につい INTERNET 権限を足す、特定 WebView でうっかり JS を有効化する、新ソースに LICENSE ヘッダを
# 付け忘れる）。意図はコードに自明には書かれないので、機械で固定しないと静かに侵食される。
#
# 設定駆動: 何が「破ってはいけない不変条件」かは消費者ごとに違うので、制約を hard-constraints.tsv に外出しし、
# スクリプトは汎用エンジンに保つ。各行 = 1制約:
#   <kind>\t<file_pathspec>\t<regex>\t<message>\t[<mode>]\t[<guard_pathspec>]
#     kind          : forbid（マッチが在れば違反） | require（マッチが無ければ違反）
#     file_pathspec : git ls-files のパススペック（例 src/main/AndroidManifest.xml ・ '*.gradle'）
#     regex         : ERE。mode=nows なら空白除去後に照合（複数行/整形ゆれに強い）
#     message       : 違反時に出す人間向けの理由
#     mode          : raw（既定・行単位 grep） | nows（全空白除去後に照合）
#     guard_pathspec: 任意・条件。これが在るとき、guard が1件もマッチしなければこの制約はスキップ。
#                     例「vendored 依存が在るときだけ帰属表示を require」（third-party notices）。guard 列を
#                     使うときは mode 列を明示すること（既定なら raw と書く）。
#   forbid : パススペックの どのファイルにも マッチが在ってはならない
#   require: パススペックの 各ファイルすべて に マッチが在らねばならない。リテラルパス（glob 文字 *? 無し）が
#            1件も無い＝必須ファイル欠落も違反。glob で0件はvacuous pass。
#   `#` 始まりと空行は無視。
#
# third-party notices の例（vendored 依存が在るときだけ帰属を必須にし、CDN 参照は常に禁止）:
#   require<TAB>THIRD_PARTY_NOTICES.md<TAB>Mermaid<TAB>vendored mermaid must be attributed<TAB>raw<TAB>src/main/assets/mermaid.min.js
#   forbid<TAB>src/main/**<TAB>unpkg|jsdelivr|cdnjs<TAB>no CDN refs in app code
#
# Config (harness.config.sh または env):
#   HARD_CONSTRAINTS_FILE — 制約定義 TSV のパス。既定: hard-constraints.tsv。無ければ skip(exit 0・advisory)
#
# Usage: sh check-hard-constraints.sh
# Consumption model: repo root を git で解決するので kit(core/scripts/)でも消費者(scripts/)でも動く。
set -u

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
cd "$ROOT"

CFILE="${HARD_CONSTRAINTS_FILE:-hard-constraints.tsv}"
if [ ! -r "$CFILE" ]; then
  echo "hard-constraints: no constraints file ($CFILE); nothing configured, skipping (advisory)." >&2
  exit 0
fi

# Scratch file via mktemp — a predictable PID-suffixed /tmp name is a symlink-attack / collision risk
# and is forbidden by check-posix-portability. Reused (truncated with >) across constraints; trap cleans up.
HC_TMP="$(mktemp 2>/dev/null || mktemp -t hc)"
trap 'rm -f "$HC_TMP"' EXIT

# present <file> <regex> <mode> : true if regex matches the file's content (raw lines, or after
# stripping all whitespace when mode=nows — which tolerates multi-line / reformatted matches).
present() {
  if [ "$3" = "nows" ]; then
    tr -d '[:space:]' < "$1" | grep -qE "$2"
  else
    grep -qE "$2" "$1"
  fi
}

VIOL=0
report() { echo "  VIOLATION: $1" >&2; VIOL=$((VIOL + 1)); }

while IFS="$(printf '\t')" read -r kind glob regex msg mode guard; do
  case "$kind" in ''|\#*) continue ;; esac
  [ -n "${glob:-}" ] && [ -n "${regex:-}" ] || continue
  mode="${mode:-raw}"
  # Conditional guard: when a guard pathspec is given and matches nothing, the constraint does not
  # apply (e.g. require an attribution only when the vendored dependency is actually present).
  if [ -n "${guard:-}" ] && [ -z "$(git ls-files -- "$guard" 2>/dev/null || true)" ]; then
    continue
  fi
  files="$(git ls-files -- "$glob" 2>/dev/null || true)"

  case "$kind" in
    forbid)
      [ -n "$files" ] || continue
      printf '%s\n' "$files" | while IFS= read -r f; do
        [ -f "$f" ] && present "$f" "$regex" "$mode" && echo "$f"
      done > "$HC_TMP" 2>/dev/null || true
      if [ -s "$HC_TMP" ]; then
        while IFS= read -r hit; do report "$msg [forbidden pattern in $hit]"; done < "$HC_TMP"
      fi
      rm -f "$HC_TMP"
      ;;
    require)
      if [ -z "$files" ]; then
        case "$glob" in
          *[*?]*) : ;;                         # glob matched nothing -> vacuous pass
          *)      report "$msg [required file missing: $glob]" ;;
        esac
        continue
      fi
      printf '%s\n' "$files" | while IFS= read -r f; do
        [ -f "$f" ] || continue
        present "$f" "$regex" "$mode" || echo "$f"
      done > "$HC_TMP" 2>/dev/null || true
      if [ -s "$HC_TMP" ]; then
        while IFS= read -r miss; do report "$msg [required pattern absent in $miss]"; done < "$HC_TMP"
      fi
      rm -f "$HC_TMP"
      ;;
    *)
      report "unknown constraint kind '$kind' (use forbid|require)"
      ;;
  esac
done < "$CFILE"

if [ "$VIOL" -eq 0 ]; then
  echo "hard-constraints: all configured invariants hold."
  exit 0
fi
echo "hard-constraints: FAIL — $VIOL violation(s). These are intentional design boundaries; fix the" >&2
echo "  code, or if the constraint itself changed, update $CFILE in the same PR with the rationale." >&2
exit 1
