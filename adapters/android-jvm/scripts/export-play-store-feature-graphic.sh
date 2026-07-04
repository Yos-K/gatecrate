#!/bin/sh
# [Android-JVMアダプタ] Play Store フィーチャーグラフィック生成（Java / AWT）
# Compiles and runs ExportPlayStoreFeatureGraphic.java to generate a 1024x500 PNG.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
BUILD="$ROOT/build/play-store-feature-graphic"
OUT="${1:-$ROOT/play-store/feature-graphic-1024x500.png}"

mkdir -p "$BUILD" "$(dirname -- "$OUT")"

javac -d "$BUILD" "$ROOT/scripts/ExportPlayStoreFeatureGraphic.java"
java -cp "$BUILD" ExportPlayStoreFeatureGraphic "$OUT"

echo "Exported Play Store feature graphic: $OUT"
