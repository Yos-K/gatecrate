#!/bin/sh
# [Android-JVMアダプタ] versionCode のみインクリメント（versionName 据え置き）
# Bumps VERSION file (versionCode only) and patches AndroidManifest.xml.
#
# Guarded by default: a version-code-only bump leaves VERSION_NAME unchanged, so
# two store uploads can share a user-visible version — confusing for release
# tracking. Normal releases should use version-bump.sh (patch/minor) so the name
# changes too. Set ALLOW_VERSION_CODE_ONLY=true only for a documented emergency
# rebuild (e.g. re-upload of an identical release with a new code).
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
. "$ROOT/scripts/version-env.sh"

if [ "${ALLOW_VERSION_CODE_ONLY:-false}" != "true" ]; then
  echo "version-code-only bump is disabled for normal releases." >&2
  echo "Use version-bump.sh patch or version-bump.sh minor so VERSION_NAME changes too." >&2
  echo "Set ALLOW_VERSION_CODE_ONLY=true only for an explicitly documented emergency rebuild." >&2
  exit 1
fi

VERSION_CODE=$((VERSION_CODE + 1))

cat > "$ROOT/VERSION" <<EOF
VERSION_NAME=$VERSION_NAME
VERSION_CODE=$VERSION_CODE
EOF

tmp="$ROOT/build/AndroidManifest.version-code-bump.xml"
mkdir -p "$ROOT/build"
sh "$ROOT/scripts/version-apply-manifest.sh" "$ROOT/src/main/AndroidManifest.xml" "$tmp"
mv "$tmp" "$ROOT/src/main/AndroidManifest.xml"

echo "Bumped versionCode to $VERSION_CODE for versionName $VERSION_NAME"
