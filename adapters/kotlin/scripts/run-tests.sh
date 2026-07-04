#!/bin/sh
# [Kotlinアダプタ] test + coverage ゲート（consumable form）
# `./gradlew test koverVerify` を実行する。JUnit5 でテストし、kover の verify ルール
# （build.gradle.kts の minBound）でカバレッジ下限を強制する。下限未満なら非0で終了する。
set -eu
ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
cd "$ROOT"
./gradlew --no-daemon test koverVerify
