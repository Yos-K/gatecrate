#!/bin/sh
# [Android-JVMアダプタ] Play Store アイコン生成（Java / AWT）
# Compiles and runs ExportPlayStoreIcon.java to generate a 512x512 PNG icon.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
BUILD="$ROOT/build/play-store-icon"
OUT="${1:-$ROOT/play-store/icon-512.png}"

mkdir -p "$BUILD" "$(dirname -- "$OUT")"

javac -d "$BUILD" "$ROOT/scripts/ExportPlayStoreIcon.java"
java -cp "$BUILD" ExportPlayStoreIcon "$OUT"

echo "Exported Play Store icon: $OUT"
