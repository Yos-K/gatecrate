#!/bin/sh
# [汎用core] 既定ブランチの分岐保護ポリシーを再現可能に適用する — スタック非依存
#
# WHY: 分岐保護を GitHub UI で手作業設定すると、必須チェック名や規則がレビュー不能・
# 再現不能になる（誰がいつ何を必須にしたか履歴に残らない）。本スクリプトは意図した
# ポリシーをコード化し、再適用・監査できるようにする（Infrastructure as Code）。
#
# 適用するポリシー:
#   - 必須ステータスチェック（strict / up-to-date 必須）: REQUIRED_CHECKS で設定
#   - 管理者にも強制（bypass 不可）
#   - マージ前に PR 必須（既定 0 approvals = ソロ開発で self-approval に詰まらないが、
#     ブランチへの直接 push は拒否される）
#   - マージ前に会話スレッドの解決を必須
#   - force push 不可・ブランチ削除不可
#
# 設定（harness.config.sh またはコマンド引数 / 環境変数で上書き可能）:
#   REQUIRED_CHECKS  — 必須ステータスチェック名（空白区切り）。
#                      未設定なら必須チェックは課されない（保護の他要素のみ適用）。
#                      例: "fitness test build mutation"
#   PR_APPROVALS     — マージに必要な承認数（既定: 0）
#
# Usage: sh setup-branch-protection.sh [owner/repo] [branch]
#   owner/repo 未指定なら gh が解決する現在のリポジトリを使う。
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"

REPO="${1:-}"
if [ -z "$REPO" ]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
fi
BRANCH="${2:-main}"
REQUIRED_CHECKS="${REQUIRED_CHECKS:-}"
PR_APPROVALS="${PR_APPROVALS:-0}"

# Build the required_status_checks JSON. With no checks configured, set the field
# to null so protection is applied without requiring any named status.
if [ -n "$REQUIRED_CHECKS" ]; then
  contexts=""
  for c in $REQUIRED_CHECKS; do
    if [ -z "$contexts" ]; then
      contexts="\"$c\""
    else
      contexts="$contexts, \"$c\""
    fi
  done
  status_checks="{ \"strict\": true, \"contexts\": [$contexts] }"
else
  status_checks="null"
fi

gh api --method PUT "repos/$REPO/branches/$BRANCH/protection" --input - > /dev/null <<JSON
{
  "required_status_checks": $status_checks,
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": $PR_APPROVALS,
    "dismiss_stale_reviews": false,
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "required_conversation_resolution": true,
  "required_linear_history": false,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false
}
JSON

echo "Applied branch protection to $REPO@$BRANCH:"
if [ -n "$REQUIRED_CHECKS" ]; then
  echo "- required status checks (strict): $REQUIRED_CHECKS"
else
  echo "- required status checks: none configured (set REQUIRED_CHECKS to require them)"
fi
echo "- enforce for admins: true"
echo "- require conversation resolution: true"
echo "- force pushes / branch deletion: disabled"
echo "- pull request required before merge ($PR_APPROVALS approvals; direct pushes refused)"
