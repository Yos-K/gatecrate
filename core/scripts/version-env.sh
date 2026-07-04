#!/bin/sh
# [汎用コア] VERSIONファイル読み込み・検証・エクスポート — スタック非依存
# Reads VERSION file (semver format) and exports VERSION_NAME and VERSION_CODE.
# Required env: ROOT (default: auto-detected from script location)
set -eu

ROOT="${ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
VERSION_FILE="$ROOT/VERSION"

if [ ! -f "$VERSION_FILE" ]; then
  echo "Missing VERSION file: $VERSION_FILE" >&2
  exit 1
fi

. "$VERSION_FILE"

case "${VERSION_NAME:-}" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *)
    echo "Invalid VERSION_NAME: ${VERSION_NAME:-}" >&2
    exit 1
    ;;
esac

case "${VERSION_CODE:-}" in
  ''|*[!0-9]*)
    echo "Invalid VERSION_CODE: ${VERSION_CODE:-}" >&2
    exit 1
    ;;
esac

export VERSION_NAME VERSION_CODE
