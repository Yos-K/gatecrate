#!/bin/sh
# [汎用コア] ADR レビュー宣言ゲート — スタック非依存
# gatecrate-type: prevention
#
# WHY (issue #25): 設計判断が旧コード・過去PR・アーカイブ議論にしか残っていないと、feat/fix コミットが
# その判断を「知らずに」覆す。ADR ファイルの構造検査だけでは「作者が変更前に関連判断をレビューした」
# ことは証明できない。本ゲートは対象タイプの各コミットに `ADR-Review:` トレーラを **ちょうど1つ** 要求し、
# 参照 ADR が「宣言コミット時点で」実在し必須セクションを備えることを機械強制する。
#
# 検査すること: レビュー宣言の存在と、参照先の構造的妥当性。
# 検査できないこと（意図的）: 意味的な遵守・不誠実な none 理由の検出。それは設計レビュー・モデル検査・
# 挙動テストの仕事。none の乱用は観測可能なので、繰り返されたらリポ方針を厳格化する（コア側の
# ヒューリスティック解析は足さない）。
#
# Config (optional, from harness.config.sh in the consumer repo root, or env):
#   ADR_REVIEW_COMMIT_TYPES         — 宣言必須のコミットタイプ（空白区切り・既定: "feat fix"）
#   ADR_DIRECTORY                   — ADR の置き場（既定: docs/adr）
#   ADR_CANONICAL_SUFFIX            — 正典のサフィックス（既定: .md）
#   ADR_COMPANION_SUFFIXES          — 対訳等の随伴文書サフィックス（空白区切り・既定: ".ja.md"・空で不要）
#   ADR_ALLOW_REASONED_NONE         — "none (<理由>)" を許すか（既定: true。false なら ADR パス必須）
#   ADR_REQUIRED_SECTIONS           — 正典の必須 "## " セクション（'|' 区切り）
#   ADR_REQUIRED_COMPANION_SECTIONS — 随伴文書の必須セクション（'|' 区切り）
#   ADR_REVIEW_BASE                 — 比較元 ref（既定: origin/main。第1引数でも指定可）
#
# Usage: sh check-adr-review.sh [<base-ref>]          # base..HEAD の対象コミットを検査
#        sh check-adr-review.sh --message <msg-file>  # commit-msg フック用: メッセージ1件を検査
# Exit:  0=pass  1=違反（宣言欠落・参照不正・セクション欠落）  2=setup（git 外・base 解決不能・引数不正）
# Consumption model: cwd の git ルートを解決して動く（kit でも消費者リポでも同じファイルが動く）。
set -eu

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$ROOT" ]; then
  echo "adr-review: not inside a Git repository" >&2
  exit 2
fi
cd "$ROOT"
[ -f harness.config.sh ] && . ./harness.config.sh

ADR_REVIEW_COMMIT_TYPES="${ADR_REVIEW_COMMIT_TYPES:-feat fix}"
ADR_DIRECTORY="${ADR_DIRECTORY:-docs/adr}"
ADR_CANONICAL_SUFFIX="${ADR_CANONICAL_SUFFIX:-.md}"
ADR_COMPANION_SUFFIXES="${ADR_COMPANION_SUFFIXES-.ja.md}"
ADR_ALLOW_REASONED_NONE="${ADR_ALLOW_REASONED_NONE:-true}"
ADR_REQUIRED_SECTIONS="${ADR_REQUIRED_SECTIONS:-Decision|Alternatives Considered|Why This Decision|Why Alternatives Were Rejected|Reconsider When}"
ADR_REQUIRED_COMPANION_SECTIONS="${ADR_REQUIRED_COMPANION_SECTIONS:-決定事項|検討した選択肢|選択理由|選択しなかった理由|決定を見直す契機}"

TYPES_RE=""
for t in $ADR_REVIEW_COMMIT_TYPES; do TYPES_RE="${TYPES_RE:+$TYPES_RE|}$t"; done

failures=0
err() { echo "adr-review: $1" >&2; failures=$((failures + 1)); }

# doc_exists <ref> <path> / doc_content <ref> <path> — ref=WORKTREE なら作業ツリー、他は当該コミット
doc_exists() {
  if [ "$1" = "WORKTREE" ]; then [ -f "$2" ]; else git cat-file -e "$1:$2" 2>/dev/null; fi
}
doc_content() {
  if [ "$1" = "WORKTREE" ]; then cat "$2" 2>/dev/null || true; else git show "$1:$2" 2>/dev/null || true; fi
}

# validate_sections <ref> <path> <'|'区切りセクション> — 各 "## X" 行の存在を要求
validate_sections() {
  vs_content="$(doc_content "$1" "$2")"
  vs_ok=0
  old_ifs="$IFS"; IFS='|'
  for section in $3; do
    if ! printf '%s\n' "$vs_content" | grep -qFx "## $section"; then
      echo "adr-review: $2 is missing required section: ## $section" >&2
      vs_ok=1
    fi
  done
  IFS="$old_ifs"
  return "$vs_ok"
}

# validate_reference <ref> <path> — 参照 ADR の形式・実在・随伴文書・セクションを検査
validate_reference() {
  ref="$1"; path="$2"
  for suf in $ADR_COMPANION_SUFFIXES; do
    case "$path" in
      *"$suf")
        echo "adr-review: reference the canonical ADR ($ADR_CANONICAL_SUFFIX), not its companion: $path" >&2
        return 1 ;;
    esac
  done
  case "$path" in
    "$ADR_DIRECTORY"/[0-9][0-9][0-9][0-9]-*"$ADR_CANONICAL_SUFFIX") ;;
    *)
      echo "adr-review: invalid ADR reference '$path' (expected $ADR_DIRECTORY/NNNN-*$ADR_CANONICAL_SUFFIX)" >&2
      return 1 ;;
  esac
  if ! doc_exists "$ref" "$path"; then
    echo "adr-review: referenced ADR does not exist at $ref: $path" >&2
    return 1
  fi
  vr_ok=0
  validate_sections "$ref" "$path" "$ADR_REQUIRED_SECTIONS" || vr_ok=1
  for suf in $ADR_COMPANION_SUFFIXES; do
    companion="${path%"$ADR_CANONICAL_SUFFIX"}$suf"
    if ! doc_exists "$ref" "$companion"; then
      echo "adr-review: ADR companion does not exist at $ref: $companion" >&2
      vr_ok=1
      continue
    fi
    validate_sections "$ref" "$companion" "$ADR_REQUIRED_COMPANION_SECTIONS" || vr_ok=1
  done
  return "$vr_ok"
}

# check_message <label> <ref> <subject> <full-message> — 1コミット（または msg ファイル）の宣言を検査
check_message() {
  label="$1"; ref="$2"; subject="$3"; msg="$4"
  if ! printf '%s\n' "$subject" | grep -Eq "^($TYPES_RE)(\([^)]*\))?!?: "; then
    return 0
  fi
  reviews="$(printf '%s\n' "$msg" | sed -n 's/^ADR-Review:[[:space:]]*//p')"
  count="$(printf '%s\n' "$reviews" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [ "$count" -ne 1 ]; then
    err "$label '$subject' must have exactly one ADR-Review trailer (found $count)"
    return 0
  fi
  review="$(printf '%s\n' "$reviews" | sed -n '1p')"
  if printf '%s\n' "$review" | grep -Eq '^none \(.+\)$'; then
    if [ "$ADR_ALLOW_REASONED_NONE" = "true" ]; then return 0; fi
    err "$label: reasoned none is disabled (ADR_ALLOW_REASONED_NONE=false); reference an ADR path"
    return 0
  fi
  if printf '%s\n' "$review" | grep -Eq '^none[[:space:]]*$'; then
    err "$label must explain why no ADR applies: ADR-Review: none (<reason>)"
    return 0
  fi
  old_ifs="$IFS"; IFS=','
  for raw_path in $review; do
    path="$(printf '%s' "$raw_path" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    validate_reference "$ref" "$path" || failures=$((failures + 1))
  done
  IFS="$old_ifs"
}

guidance_and_exit() {
  if [ "$failures" -ne 0 ]; then
    cat >&2 <<EOF

Every configured commit ($ADR_REVIEW_COMMIT_TYPES) must confirm ADR review with one trailer:
  ADR-Review: $ADR_DIRECTORY/0001-example$ADR_CANONICAL_SUFFIX
or, only when no decision applies:
  ADR-Review: none (explain why no architectural decision is affected)
EOF
    exit 1
  fi
  echo "adr-review: every checked commit declares a valid ADR review."
  exit 0
}

# --- --message モード（commit-msg フック用・作業ツリーに対して検査） ---
if [ "${1:-}" = "--message" ]; then
  MSG_FILE="${2:-}"
  if [ -z "$MSG_FILE" ] || [ ! -f "$MSG_FILE" ]; then
    echo "adr-review: --message requires a readable message file" >&2
    exit 2
  fi
  msg="$(cat "$MSG_FILE")"
  subject="$(printf '%s\n' "$msg" | sed -n '1p')"
  check_message "commit message" WORKTREE "$subject" "$msg"
  guidance_and_exit
fi

# --- 範囲モード: base..HEAD の対象コミットと、HEAD の ADR コーパス全体を検査 ---
BASE="${1:-${ADR_REVIEW_BASE:-origin/main}}"
if ! git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null 2>&1; then
  echo "adr-review: base '$BASE' is not resolvable; refusing to skip ADR review." >&2
  exit 2
fi

for path in "$ADR_DIRECTORY"/[0-9][0-9][0-9][0-9]-*"$ADR_CANONICAL_SUFFIX"; do
  [ -e "$path" ] || continue
  skip=0
  for suf in $ADR_COMPANION_SUFFIXES; do
    case "$path" in *"$suf") skip=1 ;; esac
  done
  [ "$skip" -eq 1 ] && continue
  validate_reference HEAD "$path" || failures=$((failures + 1))
done

for commit in $(git rev-list --reverse "$BASE..HEAD"); do
  subject="$(git show -s --format='%s' "$commit")"
  msg="$(git show -s --format='%B' "$commit")"
  check_message "$commit" "$commit" "$subject" "$msg"
done

guidance_and_exit
