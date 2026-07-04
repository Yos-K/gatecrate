#!/bin/sh
# [汎用コア] Play Storeスクリーンショット準備（メタデータ除去ラッパ） — スタック非依存
# Usage: sh scripts/prepare-play-store-screenshot.sh <input> <output>
# Depends on: scripts/StripImageMetadata.java (compiled at runtime)
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INPUT="${1:?Usage: scripts/prepare-play-store-screenshot.sh <input> <output>}"
OUTPUT="${2:?Usage: scripts/prepare-play-store-screenshot.sh <input> <output>}"
BUILD="$ROOT/build/strip-image-metadata"

mkdir -p "$BUILD" "$(dirname -- "$OUTPUT")"

javac -d "$BUILD" "$ROOT/scripts/StripImageMetadata.java"
java -cp "$BUILD" StripImageMetadata "$INPUT" "$OUTPUT"

echo "Prepared screenshot: $OUTPUT"
