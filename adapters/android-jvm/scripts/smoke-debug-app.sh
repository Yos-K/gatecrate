#!/bin/sh
# [Android-JVMアダプタ] デバッグアプリのスモークテスト（Termux/ADB直接実行）
# Opens a fixture file and exercises scroll/menu on a connected Android device.
# Uses ADB input injection — requires Termux with appropriate permissions.
#
# Required env vars (set in harness.config.sh):
#   APP_PACKAGE — application package ID (e.g. com.example.app)
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
PACKAGE="${APP_PACKAGE:?APP_PACKAGE must be set in harness.config.sh}"
FIXTURE="${1:-/sdcard/Download/debug-fixture.md}"

screen_size() {
  size=$(PATH=/system/bin:/system/xbin wm size 2>/dev/null | sed -n 's/.*: \([0-9][0-9]*\)x\([0-9][0-9]*\).*/\1 \2/p' || true)
  if [ -n "$size" ]; then
    echo "$size"
    return
  fi
  echo "1080 2400"
}

sleep_short() {
  sleep 1
}

fail() {
  echo "Smoke test failed: $1" >&2
  exit 1
}

clear_logcat() {
  logcat -c 2>/dev/null || true
}

assert_no_app_crash() {
  if logcat -d -v brief 2>/dev/null | grep -A 8 -B 3 "Process: $PACKAGE" | grep -F "FATAL EXCEPTION" > /dev/null; then
    logcat -d -v brief 2>/dev/null | grep -A 12 -B 4 "Process: $PACKAGE" >&2
    fail "app crashed"
  fi
}

tap() {
  PATH=/system/bin:/system/xbin input tap "$1" "$2"
}

swipe() {
  PATH=/system/bin:/system/xbin input swipe "$1" "$2" "$3" "$4" "${5:-250}"
}

can_inject_input() {
  PATH=/system/bin:/system/xbin input keyevent 0 >/dev/null 2>&1
}

open_menu_by_edge_swipe() {
  set -- $(screen_size)
  height="$2"
  y=$((height / 2))
  swipe 4 "$y" 360 "$y" 350
}

exercise_menu() {
  set -- $(screen_size)
  width="$1"
  height="$2"
  menu_x=$((width / 5))
  settings_y=$((height / 2))

  open_menu_by_edge_swipe
  sleep_short
  tap "$menu_x" "$settings_y"
  sleep_short
  assert_no_app_crash
  PATH=/system/bin:/system/xbin input keyevent 4
  sleep_short
}

exercise_document_scroll() {
  set -- $(screen_size)
  width="$1"
  height="$2"
  x=$((width / 2))
  top=$((height / 4))
  bottom=$(((height * 3) / 4))

  swipe "$x" "$bottom" "$x" "$top" 350
  sleep_short
  swipe "$x" "$top" "$x" "$bottom" 350
  sleep_short
  assert_no_app_crash
}

echo "Opening debug fixture..."
clear_logcat
sh "$ROOT/scripts/open-debug-fixture.sh" "$FIXTURE" > /dev/null
sleep_short
assert_no_app_crash

if ! can_inject_input; then
  echo "Input injection is not permitted on this device from Termux."
  echo "Limited smoke test passed: launch, fixture open intent, and app crash check."
  exit 0
fi

echo "Exercising document scroll..."
exercise_document_scroll

echo "Exercising menu..."
exercise_menu

echo "Smoke test passed."
