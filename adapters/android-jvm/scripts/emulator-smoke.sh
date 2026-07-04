#!/bin/sh
# [Android-JVMアダプタ] エミュレータスモークテスト（CI/ADB）
# Drive an install-free smoke test against a connected Android emulator via adb.
# Walks the smoke ladder (L2 launch → L3 single file → L4 multiple files).
#
# Required env vars (set in harness.config.sh):
#   APP_PACKAGE        — base application package ID (e.g. com.example.app)
#   APP_OPEN_ACTION    — intent action for opening documents (e.g. com.example.app.action.OPEN_TEXTS)
#   APP_EXTRA_TITLES   — intent extra key for document titles
#   APP_EXTRA_SOURCES  — intent extra key for document sources
#   APP_EXTRA_TEXTS    — intent extra key for base64-encoded document texts
#
# Optional env vars:
#   APP_DEBUG_SUFFIX   — debug package suffix (default: .debug)
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
APP_PACKAGE="${APP_PACKAGE:?APP_PACKAGE must be set in harness.config.sh}"
APP_OPEN_ACTION="${APP_OPEN_ACTION:?APP_OPEN_ACTION must be set in harness.config.sh}"
APP_EXTRA_TITLES="${APP_EXTRA_TITLES:?APP_EXTRA_TITLES must be set in harness.config.sh}"
APP_EXTRA_SOURCES="${APP_EXTRA_SOURCES:?APP_EXTRA_SOURCES must be set in harness.config.sh}"
APP_EXTRA_TEXTS="${APP_EXTRA_TEXTS:?APP_EXTRA_TEXTS must be set in harness.config.sh}"

PKG="${1:-${APP_PACKAGE}${APP_DEBUG_SUFFIX:-.debug}}"
MAIN_ACTIVITY="${APP_MAIN_ACTIVITY:-${APP_PACKAGE}.presentation.MainActivity}"
ACTIVITY="$PKG/$MAIN_ACTIVITY"

FIXTURE_ONE="$ROOT/scripts/smoke-fixtures/smoke-one.md"
FIXTURE_TWO="$ROOT/scripts/smoke-fixtures/smoke-two.md"

ART_DIR="${SMOKE_ARTIFACT_DIR:-$ROOT/smoke-artifacts}"
mkdir -p "$ART_DIR"

capture_evidence() {
  adb logcat -d -v time > "$ART_DIR/logcat.txt" 2>/dev/null || true
  adb exec-out screencap -p > "$ART_DIR/screen.png" 2>/dev/null || true
}

fail() {
  echo "Emulator smoke failed: $1" >&2
  capture_evidence
  grep -F "FATAL EXCEPTION" -A 8 "$ART_DIR/logcat.txt" >&2 2>/dev/null || true
  exit 1
}

b64() {
  # Read from stdin and strip newlines so it works on both GNU and BSD base64.
  base64 < "$1" | tr -d '\n'
}

assert_alive() {
  sleep 2
  if ! adb shell pidof "$PKG" >/dev/null 2>&1; then
    fail "$1 (process $PKG is not running)"
  fi
  # AndroidRuntime's "FATAL EXCEPTION" line does not carry the package; the
  # crashing package is on the following "Process: <pkg>" line. Matching the
  # FATAL line against $PKG never hits, so correlate the crash block (FATAL plus
  # a few lines) against "Process:.*$PKG" to catch this app's crashes.
  if adb logcat -d -v brief 2>/dev/null | grep -A3 -F "FATAL EXCEPTION" | grep -q "Process:.*$PKG"; then
    fail "$1 (FATAL EXCEPTION for $PKG in logcat)"
  fi
}

open_texts() {
  adb shell am start -n "$ACTIVITY" -a "$APP_OPEN_ACTION" --activity-single-top \
    --esa "$APP_EXTRA_TITLES" "$1" \
    --esa "$APP_EXTRA_SOURCES" "$2" \
    --esa "$APP_EXTRA_TEXTS" "$3" >/dev/null
}

adb logcat -c 2>/dev/null || true

# L2: launch
adb shell am start -W -n "$ACTIVITY" >/dev/null
assert_alive "launch"
echo "L2 launch: ok"

# L3: open one Markdown by intent
one_b64="$(b64 "$FIXTURE_ONE")"
open_texts "smoke-one.md" "$FIXTURE_ONE" "$one_b64"
assert_alive "open single Markdown by intent"
echo "L3 single-file intent: ok"

# L4: open multiple Markdown files as tabs
two_b64="$(b64 "$FIXTURE_TWO")"
open_texts "smoke-one.md,smoke-two.md" "$FIXTURE_ONE,$FIXTURE_TWO" "$one_b64,$two_b64"
assert_alive "open multiple Markdown tabs by intent"
echo "L4 multiple-file intent: ok"

capture_evidence
echo "Emulator smoke passed"
