#!/bin/sh
# [Android-JVMアダプタ] デバッグスクリーンショット取得（Termux/ADB）
# Captures a screenshot from a connected Android device via Termux screencap.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
NAME="${1:-app-debug}"
OUT="$ROOT/build/debug-screenshots/$NAME.png"

mkdir -p "$(dirname -- "$OUT")"
if ! screencap -p "$OUT"; then
  echo "Failed to capture screenshot from Termux." >&2
  echo "Use the device screenshot feature and place the image under Download when Termux lacks capture permission." >&2
  exit 1
fi

echo "Captured screenshot: $OUT"
