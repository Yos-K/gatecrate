#!/bin/sh
# [Android-JVMアダプタ] Android SDK依存ライブラリのダウンロード
# Downloads Android dependencies (billing library etc.) to the local deps directory.
#
# Optional env vars:
#   APP_ANDROID_DEPS_DIR         — cache directory (default: .android-deps)
#   GOOGLE_PLAY_BILLING_VERSION  — billing library version (default: 9.0.0)
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
ANDROID_DEPS_DIR="${APP_ANDROID_DEPS_DIR:-$ROOT/.android-deps}"
BILLING_VERSION="${GOOGLE_PLAY_BILLING_VERSION:-9.0.0}"

python3 "$ROOT/scripts/prepare_android_dependencies.py" \
  --deps-dir "$ANDROID_DEPS_DIR" \
  --billing-version "$BILLING_VERSION"
