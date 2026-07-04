#!/bin/sh
# [汎用コア] 作業ブランチ作成（mainから最新を取得してブランチを切る） — スタック非依存
set -eu

if [ "$#" -ne 1 ]; then
  echo "Usage: sh scripts/start-work.sh <branch-name>" >&2
  exit 2
fi

BRANCH="$1"
case "$BRANCH" in
  main|master)
    echo "Refusing to create a work branch named '$BRANCH'." >&2
    exit 2
    ;;
esac

git fetch origin main
git switch main
git pull --ff-only origin main
git switch -c "$BRANCH"

echo "Created work branch: $BRANCH"
