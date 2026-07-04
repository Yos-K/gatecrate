#!/bin/sh
# [Android-JVMアダプタ] Android リリース用キーストア生成
# Generates a new release keystore via keytool (RSA 4096, 10000-day validity).
#
# Optional env vars:
#   APP_RELEASE_KEYSTORE  — output keystore path (default: $HOME/AndroidDev/keys/app-release.jks)
#   APP_RELEASE_KEY_ALIAS — key alias (default: app-release)
set -eu

KEYSTORE="${APP_RELEASE_KEYSTORE:-$HOME/AndroidDev/keys/app-release.jks}"
ALIAS="${APP_RELEASE_KEY_ALIAS:-app-release}"

if [ -f "$KEYSTORE" ]; then
  echo "Release keystore already exists: $KEYSTORE" >&2
  exit 1
fi

mkdir -p "$(dirname -- "$KEYSTORE")"

keytool -genkeypair \
  -v \
  -keystore "$KEYSTORE" \
  -alias "$ALIAS" \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000

echo "Created release keystore: $KEYSTORE"
echo "Release key alias: $ALIAS"
