#!/bin/sh
# [Android-JVMアダプタ] GitHub Actions のリリース用 Environment を作成する。
#
# WHY: 署名付きリリースビルドと Play Console アップロードは秘密情報（keystore・OIDC）を要するが、
# それらは「環境（environment）」スコープで保護したい（保護ルール・必須レビュアを掛けられる）。
# 本スクリプトは Environment を冪等に作成し、登録すべき secret / variable の手順を出力する。
#
# Android/Play 固有のため core ではなくアダプタに置く（release-build 環境・Play OIDC・
# 署名 keystore は Android-JVM のリリース経路に固有の概念）。
#
# 設定（harness.config.sh または環境変数）:
#   KEYSTORE_SECRET_PREFIX — 署名 secret 名のプレフィクス（既定: RELEASE）。
#                            例: RELEASE -> RELEASE_KEYSTORE_BASE64 など
#
# Usage: sh setup-github-actions-repo.sh [owner/repo]
#   owner/repo 未指定なら gh が解決する現在のリポジトリを使う。
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"

REPO="${1:-}"
if [ -z "$REPO" ]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
fi
PREFIX="${KEYSTORE_SECRET_PREFIX:-RELEASE}"

gh api --method PUT "repos/$REPO/environments/release-build" --input /dev/null > /dev/null
gh api --method PUT "repos/$REPO/environments/play-console" --input /dev/null > /dev/null

echo "Configured GitHub Actions environments for $REPO:"
echo "- release-build"
echo "- play-console"
echo
echo "Register environment secrets with:"
for env in release-build play-console; do
  echo "  gh secret set ${PREFIX}_KEYSTORE_BASE64 --env $env --repo $REPO"
  echo "  gh secret set ${PREFIX}_KEY_ALIAS --env $env --repo $REPO"
  echo "  gh secret set ${PREFIX}_STORE_PASS --env $env --repo $REPO"
  echo "  gh secret set ${PREFIX}_KEY_PASS --env $env --repo $REPO"
done
echo
echo "Register OIDC environment variables (Play Console upload) with:"
echo "  gh variable set GCP_WORKLOAD_IDENTITY_PROVIDER --env play-console --repo $REPO"
echo "  gh variable set GCP_SERVICE_ACCOUNT --env play-console --repo $REPO"
