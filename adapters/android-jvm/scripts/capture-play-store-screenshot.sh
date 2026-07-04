#!/bin/sh
# [Android-JVMアダプタ] Play Storeスクリーンショット取得（Termux/ADB）
# Captures a named screenshot for Play Store submission from a connected device.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
NAME="${1:?Usage: scripts/capture-play-store-screenshot.sh <name>}"
OUT="$ROOT/play-store/screenshots/$NAME.png"

mkdir -p "$(dirname -- "$OUT")"
screencap -p "$OUT"

echo "Captured screenshot: $OUT"
