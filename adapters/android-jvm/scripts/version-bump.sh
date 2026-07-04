#!/bin/sh
# [Android-JVMアダプタ] バージョン番号インクリメント（patch または minor）
# Bumps VERSION file and patches AndroidManifest.xml.
#
# Usage: sh scripts/version-bump.sh patch|minor
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
. "$ROOT/scripts/version-env.sh"

PART="${1:-}"
case "$PART" in
  patch|minor) ;;
  *)
    echo "Usage: scripts/version-bump.sh patch|minor" >&2
    exit 2
    ;;
esac

major=${VERSION_NAME%%.*}
rest=${VERSION_NAME#*.}
minor=${rest%%.*}
patch=${rest#*.}

case "$PART" in
  patch)
    patch=$((patch + 1))
    ;;
  minor)
    minor=$((minor + 1))
    patch=0
    ;;
esac

VERSION_CODE=$((VERSION_CODE + 1))
VERSION_NAME="$major.$minor.$patch"

cat > "$ROOT/VERSION" <<EOF
VERSION_NAME=$VERSION_NAME
VERSION_CODE=$VERSION_CODE
EOF

tmp="$ROOT/build/AndroidManifest.version-bump.xml"
mkdir -p "$ROOT/build"
sh "$ROOT/scripts/version-apply-manifest.sh" "$ROOT/src/main/AndroidManifest.xml" "$tmp"
mv "$tmp" "$ROOT/src/main/AndroidManifest.xml"

echo "Bumped version to $VERSION_NAME ($VERSION_CODE)"
