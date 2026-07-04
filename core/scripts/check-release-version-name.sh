#!/bin/sh
# [汎用core] リリース版名の再利用拒否ゲート — スタック非依存
#
# WHY: ユーザーに見える版名（VERSION_NAME）を前回リリースのタグと同じまま公開すると、
# 「別の中身を同じ版として出す」ことになり、変更追跡・サポート・ロールバックが破綻する。
# 本ゲートは VERSION_NAME が最新リリースタグと等しい場合にリリースを拒否し、版名の
# bump を促す（ストアによっては内部ビルド番号だけ上げれば通るが、版名据え置きは別問題）。
#
# 設定（環境変数）:
#   ALLOW_VERSION_NAME_REUSE=true — 版名据え置きを明示的に許可（内部番号のみ更新する場合）
#   ROOT                          — 検査対象リポジトリのルート（既定: スクリプトから自動解決）
#
# 版名は scripts/version-env.sh が VERSION ファイルから読み込む（VERSION_NAME を期待）。
# タグ形式は semver の `v<major>.<minor>.<patch>` を前提とする。
set -eu

SCRIPT_ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/.." && pwd))"
ROOT="${ROOT:-$SCRIPT_ROOT}"
. "$SCRIPT_ROOT/scripts/version-env.sh"

if [ "${ALLOW_VERSION_NAME_REUSE:-false}" = "true" ]; then
  echo "VERSION_NAME reuse allowed by ALLOW_VERSION_NAME_REUSE=true"
  exit 0
fi

latest_tag="$(git -C "$ROOT" tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | sed -n '1p')"

if [ -z "$latest_tag" ]; then
  echo "No release tag found; VERSION_NAME=$VERSION_NAME is acceptable"
  exit 0
fi

latest_version="${latest_tag#v}"
if [ "$VERSION_NAME" = "$latest_version" ]; then
  echo "VERSION_NAME=$VERSION_NAME has already been released as $latest_tag" >&2
  echo "Bump VERSION_NAME (patch or minor) before the next release." >&2
  exit 1
fi

echo "VERSION_NAME=$VERSION_NAME is newer than latest release tag $latest_tag"
