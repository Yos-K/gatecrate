#!/bin/sh
# [汎用コア] VERSION表示 — スタック非依存
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
. "$ROOT/scripts/version-env.sh"

echo "versionName=$VERSION_NAME"
echo "versionCode=$VERSION_CODE"
