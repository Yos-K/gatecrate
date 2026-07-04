#!/bin/sh
# [Android-JVMアダプタ] AndroidManifest.xml にバージョン情報をパッチ適用
# Writes versionCode and versionName from VERSION file into a manifest copy.
#
# Usage: sh scripts/version-apply-manifest.sh INPUT_MANIFEST OUTPUT_MANIFEST
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
. "$ROOT/scripts/version-env.sh"

INPUT="${1:?Usage: scripts/version-apply-manifest.sh INPUT_MANIFEST OUTPUT_MANIFEST}"
OUTPUT="${2:?Usage: scripts/version-apply-manifest.sh INPUT_MANIFEST OUTPUT_MANIFEST}"

sed \
  -e "s/android:versionCode=\"[^\"]*\"/android:versionCode=\"$VERSION_CODE\"/" \
  -e "s/android:versionName=\"[^\"]*\"/android:versionName=\"$VERSION_NAME\"/" \
  "$INPUT" > "$OUTPUT"
