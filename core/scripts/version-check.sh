#!/bin/sh
# [汎用コア] VERSIONファイルとマニフェストの一致検証 — スタック非依存
# Verifies VERSION_NAME/VERSION_CODE match the manifest file.
# Required env: MANIFEST_PATH (path to manifest file containing version declarations)
#   For Android: src/main/AndroidManifest.xml
#   For other stacks: any file containing version declarations
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
. "$ROOT/scripts/version-env.sh"

MANIFEST="${MANIFEST_PATH:-}"

if [ -z "$MANIFEST" ]; then
  echo "MANIFEST_PATH not set — skipping manifest version consistency check" >&2
  echo "Version loaded: $VERSION_NAME ($VERSION_CODE)"
  exit 0
fi

if [ ! -f "$MANIFEST" ]; then
  echo "Manifest file not found: $MANIFEST" >&2
  exit 1
fi

if ! grep -q "versionName.*$VERSION_NAME\|android:versionName=\"$VERSION_NAME\"" "$MANIFEST"; then
  echo "Manifest versionName does not match VERSION_NAME=$VERSION_NAME" >&2
  exit 1
fi

if ! grep -q "versionCode.*$VERSION_CODE\|android:versionCode=\"$VERSION_CODE\"" "$MANIFEST"; then
  echo "Manifest versionCode does not match VERSION_CODE=$VERSION_CODE" >&2
  exit 1
fi

echo "Version is consistent: $VERSION_NAME ($VERSION_CODE)"
