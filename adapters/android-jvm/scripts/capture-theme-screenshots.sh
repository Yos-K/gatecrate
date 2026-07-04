#!/bin/sh
# [Android-JVMアダプタ] テーマ別スクリーンショット取得（エミュレータ/ADB）
# Captures per-theme screenshots from a connected Android emulator/device via adb.
#
# Required env vars (set in harness.config.sh):
#   APP_PACKAGE         — application package ID (pro debug variant)
#   APP_OPEN_ACTION     — intent action for opening documents
#   APP_EXTRA_TITLES    — intent extra key for document titles
#   APP_EXTRA_SOURCES   — intent extra key for document sources
#   APP_EXTRA_TEXTS     — intent extra key for base64-encoded texts
#   APP_THEMES          — space-separated list of theme names (e.g. "light dark amoled")
#   APP_THEME_PREF_KEY  — SharedPreferences key for the theme setting (e.g. viewer_theme)
#
# Optional env vars:
#   APP_PRO_DEBUG_SUFFIX — pro debug package suffix (default: .pro.debug)
#   THEME_SHOT_DIR       — output directory for screenshots (default: $ROOT/theme-screenshots)
#   MENU_TAP_X           — toolbar menu button X coordinate (default: 150)
#   MENU_TAP_Y           — toolbar menu button Y coordinate (default: 215)
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
APP_PACKAGE="${APP_PACKAGE:?APP_PACKAGE must be set in harness.config.sh}"
APP_OPEN_ACTION="${APP_OPEN_ACTION:?APP_OPEN_ACTION must be set in harness.config.sh}"
APP_EXTRA_TITLES="${APP_EXTRA_TITLES:?APP_EXTRA_TITLES must be set in harness.config.sh}"
APP_EXTRA_SOURCES="${APP_EXTRA_SOURCES:?APP_EXTRA_SOURCES must be set in harness.config.sh}"
APP_EXTRA_TEXTS="${APP_EXTRA_TEXTS:?APP_EXTRA_TEXTS must be set in harness.config.sh}"
APP_THEMES="${APP_THEMES:?APP_THEMES must be set in harness.config.sh (space-separated)}"
APP_THEME_PREF_KEY="${APP_THEME_PREF_KEY:?APP_THEME_PREF_KEY must be set in harness.config.sh}"

PKG="${1:-${APP_PACKAGE}${APP_PRO_DEBUG_SUFFIX:-.pro.debug}}"
MAIN_ACTIVITY="${APP_MAIN_ACTIVITY:-${APP_PACKAGE}.presentation.MainActivity}"
ACTIVITY="$PKG/$MAIN_ACTIVITY"

FIXTURE="$ROOT/scripts/smoke-fixtures/theme-showcase.md"
ART_DIR="${THEME_SHOT_DIR:-$ROOT/theme-screenshots}"
THEMES="$APP_THEMES"

mkdir -p "$ART_DIR"

fail() {
  echo "Theme screenshot capture failed: $1" >&2
  adb logcat -d -v time > "$ART_DIR/logcat.txt" 2>/dev/null || true
  exit 1
}

write_theme_pref() {
  printf '%s\n' "<?xml version='1.0' encoding='utf-8' standalone='yes' ?><map><string name=\"$APP_THEME_PREF_KEY\">$1</string></map>" \
    > "$ART_DIR/.viewer_settings.xml"
  adb push "$ART_DIR/.viewer_settings.xml" /data/local/tmp/viewer_settings.xml >/dev/null
  adb shell run-as "$PKG" sh -c \
    "'mkdir -p shared_prefs && cp /data/local/tmp/viewer_settings.xml shared_prefs/viewer_settings.xml'" \
    || fail "writing prefs for theme $1 (is the build debuggable?)"
}

MENU_TAP_X="${MENU_TAP_X:-150}"
MENU_TAP_Y="${MENU_TAP_Y:-215}"

# Fixed sleeps, not a dumpsys-based foreground poll: on CI software-renderer
# emulators the mResumedActivity / mCurrentFocus greps proved unreliable (they
# failed to match while the app was visibly up), whereas plain sleeps captured
# every theme. dump_focus_diagnostics() below only records dumpsys output for
# later analysis — it does not gate the run.
# Cold start on the software renderer needs the longer first wait; later launches
# reuse warmed caches. 30s (was 25): flaky analysis showed "app did not reach
# foreground" failures on cold start; the extra 5s covers CI runner variance.
FIRST_LAUNCH_WAIT=30
NEXT_LAUNCH_WAIT=15
launch_wait="$FIRST_LAUNCH_WAIT"

wait_for_foreground() {
  sleep "$launch_wait"
  launch_wait="$NEXT_LAUNCH_WAIT"
  adb shell pidof "$PKG" >/dev/null 2>&1 || fail "app not running for theme $1"
}

dump_focus_diagnostics() {
  {
    echo "== dumpsys window (focus lines) =="
    adb shell dumpsys window 2>/dev/null | grep -inE "focus" | head -20
    echo "== dumpsys activity activities (resumed lines) =="
    adb shell dumpsys activity activities 2>/dev/null | grep -inE "resumed" | head -20
  } > "$ART_DIR/focus-diagnostics.txt" || true
}

assert_menu_open() {
  # The contentDescription flips to "Close menu" when open, so the UI dump
  # proves the tap actually worked. Re-tap on each retry — the original tap
  # may land while the UI is still rendering (assert_document_open returning
  # does not guarantee the layout pass is complete). 4 retries × re-tap
  # covers transient layout jank.
  tries=0
  while [ "$tries" -lt 4 ]; do
    if [ "$tries" -gt 0 ]; then
      adb shell input tap "$MENU_TAP_X" "$MENU_TAP_Y"
      sleep 2
    fi
    adb shell rm -f /sdcard/ui-dump.xml
    adb shell uiautomator dump /sdcard/ui-dump.xml >/dev/null 2>&1 || true
    if adb shell cat /sdcard/ui-dump.xml 2>/dev/null | grep -q "Close menu"; then
      return 0
    fi
    tries=$((tries + 1))
    sleep 2
  done
  adb shell cat /sdcard/ui-dump.xml > "$ART_DIR/menu-fail-ui-dump.xml" 2>/dev/null || true
  adb exec-out screencap -p > "$ART_DIR/menu-fail-screen.png" 2>/dev/null || true
  fail "menu did not open for theme $1 (evidence: menu-fail-ui-dump.xml / menu-fail-screen.png)"
}

launch_app() {
  adb shell am start -n "$ACTIVITY" -a "$APP_OPEN_ACTION" --activity-single-top \
    --esa "$APP_EXTRA_TITLES" "theme-showcase.md" \
    --esa "$APP_EXTRA_SOURCES" "$FIXTURE" \
    --esa "$APP_EXTRA_TEXTS" "$fixture_b64" >/dev/null
}

assert_document_open() {
  # The OPEN_TEXTS intent may not be honored on the very first cold launch
  # (the app may display its welcome/empty state before onNewIntent fires).
  # Re-send at the top of every retry so each re-sent intent is always
  # followed by a dump+check. tries 3→4 and sleep 5→8: flaky CI runs showed
  # "fixture did not open" on cold-start because the layout was still settling
  # after wait_for_foreground returned; longer retry wait covers that gap.
  tries=0
  while [ "$tries" -lt 4 ]; do
    if [ "$tries" -gt 0 ]; then
      launch_app
      sleep 8
    fi
    adb shell rm -f /sdcard/ui-dump.xml
    adb shell uiautomator dump /sdcard/ui-dump.xml >/dev/null 2>&1 || true
    if adb shell cat /sdcard/ui-dump.xml 2>/dev/null | grep -q "theme-showcase.md"; then
      return 0
    fi
    tries=$((tries + 1))
  done
  adb shell cat /sdcard/ui-dump.xml > "$ART_DIR/document-fail-ui-dump.xml" 2>/dev/null || true
  adb exec-out screencap -p > "$ART_DIR/document-fail-screen.png" 2>/dev/null || true
  fail "fixture did not open for theme $1 (evidence: document-fail-ui-dump.xml / document-fail-screen.png)"
}

fixture_b64="$(base64 < "$FIXTURE" | tr -d '\n')"

for theme in $THEMES; do
  adb shell am force-stop "$PKG"
  write_theme_pref "$theme"
  launch_app
  wait_for_foreground "$theme"
  [ -f "$ART_DIR/focus-diagnostics.txt" ] || dump_focus_diagnostics
  assert_document_open "$theme"
  # Brief settle wait: uiautomator dump is available before the final layout
  # pass completes; without this pause the menu tap can land during an ongoing
  # transition and be swallowed.
  sleep 2
  adb exec-out screencap -p > "$ART_DIR/$theme-document.png" || fail "screencap for theme $theme"

  adb shell input tap "$MENU_TAP_X" "$MENU_TAP_Y"
  sleep 2
  assert_menu_open "$theme"
  adb exec-out screencap -p > "$ART_DIR/$theme-menu.png" || fail "menu screencap for theme $theme"
  echo "captured: $theme"
done

adb shell am force-stop "$PKG"
write_theme_pref "$(echo "$THEMES" | cut -d' ' -f1)"
launch_app
wait_for_foreground "menu-animation"
assert_document_open "menu-animation"
adb shell screenrecord --time-limit 8 /data/local/tmp/menu-animation.mp4 &
record_pid=$!
sleep 1
adb shell input tap "$MENU_TAP_X" "$MENU_TAP_Y"
sleep 2
adb shell input tap 900 1200
sleep 2
wait "$record_pid" || true
adb pull /data/local/tmp/menu-animation.mp4 "$ART_DIR/menu-animation.mp4" >/dev/null \
  || echo "warning: menu animation recording could not be pulled" >&2

rm -f "$ART_DIR/.viewer_settings.xml"
echo "Theme screenshots written to $ART_DIR"
