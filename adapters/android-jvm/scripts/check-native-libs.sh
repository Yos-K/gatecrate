#!/bin/sh
# [Android-JVMアダプタ] APK 内の native lib 同梱検証（NDK/CMake ビルド向け）
#
# なぜ: NDK/CMake で native バイナリ（.so）をビルドする Android アプリは、AGP が実際に APK の
# lib/<abi>/ 配下へ同梱できているかを、実機 sideload より前に CI で一次検証したい（gatecrate#25
# Gap2）。パッケージング設定（abiFilters / packaging）のミスは実機で初めて ENOENT として現れ、
# デバッグが高コストになる。だから「期待 ABI × 期待 .so 名」を APK の zip エントリで assert し、
# 同梱漏れをパッケージング段階で落とす。
#
# Required env vars (CI では GitHub repository variables → ci.yml の env 経由で供給。
# ローカル実行時は export して渡す):
#   NATIVE_LIB_APK    — 検証対象 APK のパス（例: app/build/outputs/apk/debug/app-debug.apk）
#   NATIVE_LIB_NAMES  — 期待する .so 名（スペース区切り・例: "libprobe.so libfoo.so"）
#
# Optional env vars:
#   NATIVE_LIB_ABIS   — 期待する ABI（スペース区切り・default: "arm64-v8a x86_64"）
#                       arm64-v8a=実機 / x86_64=エミュレータ、が既定の検証 ABI。
set -eu

APK="${NATIVE_LIB_APK:?NATIVE_LIB_APK must be set (path to the APK to inspect)}"
NAMES="${NATIVE_LIB_NAMES:?NATIVE_LIB_NAMES must be set (e.g. \"libprobe.so\")}"
ABIS="${NATIVE_LIB_ABIS:-arm64-v8a x86_64}"

if [ ! -f "$APK" ]; then
  echo "ERROR: APK not found: $APK" >&2
  exit 1
fi

LISTING="$(unzip -l "$APK")"
missing=0
for abi in $ABIS; do
  for name in $NAMES; do
    entry="lib/$abi/$name"
    if printf '%s\n' "$LISTING" | grep -q "[[:space:]]$entry\$"; then
      echo "OK:      $entry"
    else
      echo "MISSING: $entry not packaged in $APK" >&2
      missing=1
    fi
  done
done

if [ "$missing" -ne 0 ]; then
  echo "Native lib packaging check failed. Verify abiFilters / externalNativeBuild / packaging settings." >&2
  exit 1
fi
echo "Native lib packaging check passed (all expected .so present for: $ABIS)."
