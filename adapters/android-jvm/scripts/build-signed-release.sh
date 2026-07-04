#!/bin/sh
# [Android-JVMアダプタ] 署名済みリリースビルド（APK/AAB 選択可）
# Interactive wrapper: prompts for keystore passwords and builds signed APK/AAB.
#
# Required env vars (set in harness.config.sh or environment):
#   APP_RELEASE_KEYSTORE  — path to keystore (default: $HOME/AndroidDev/keys/app-release.jks)
#   APP_RELEASE_KEY_ALIAS — key alias (default: app-release)
#   BUNDLETOOL_JAR        — path to bundletool.jar (required for aab/all)
#
# Usage: sh scripts/build-signed-release.sh [apk|aab|all]
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
TARGET="${1:-aab}"

case "$TARGET" in
  apk|aab|all)
    ;;
  *)
    echo "Usage: scripts/build-signed-release.sh [apk|aab|all]" >&2
    exit 2
    ;;
esac

export APP_RELEASE_KEYSTORE="${APP_RELEASE_KEYSTORE:-$HOME/AndroidDev/keys/app-release.jks}"
export APP_RELEASE_KEY_ALIAS="${APP_RELEASE_KEY_ALIAS:-app-release}"
export BUNDLETOOL_JAR="${BUNDLETOOL_JAR:-$HOME/AndroidDev/tools/bundletool.jar}"

if [ ! -f "$APP_RELEASE_KEYSTORE" ]; then
  echo "Missing release keystore: $APP_RELEASE_KEYSTORE" >&2
  exit 1
fi

if [ "$TARGET" = "aab" ] || [ "$TARGET" = "all" ]; then
  if [ ! -f "$BUNDLETOOL_JAR" ]; then
    echo "Missing bundletool jar: $BUNDLETOOL_JAR" >&2
    exit 1
  fi
fi

cleanup() {
  stty echo 2>/dev/null || true
  unset APP_RELEASE_STORE_PASS
  unset APP_RELEASE_KEY_PASS
}
trap cleanup EXIT INT TERM

printf "Keystore password: "
stty -echo
read -r APP_RELEASE_STORE_PASS
stty echo
printf "\nKey password: "
stty -echo
read -r APP_RELEASE_KEY_PASS
stty echo
printf "\n"
export APP_RELEASE_STORE_PASS
export APP_RELEASE_KEY_PASS

case "$TARGET" in
  apk)
    sh "$ROOT/scripts/build-release-apk.sh"
    ;;
  aab)
    sh "$ROOT/scripts/build-release-aab.sh"
    ;;
  all)
    sh "$ROOT/scripts/build-release-apk.sh"
    sh "$ROOT/scripts/build-release-aab.sh"
    ;;
esac
