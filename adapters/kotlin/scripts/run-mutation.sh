#!/bin/sh
# [Kotlinアダプタ] pitest ミューテーションゲート（consumable form）
set -eu
ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
cd "$ROOT"

# A+B 戦略（docs/mutation-strategy.md）: PIT のネイティブ per-line diff は arcmutate/pitest-git plugin が要るため
# 本アダプタは schedule-first（B=nightly フルが主軸）。diff モードでは「変更 production source 無しなら SKIP」の
# 床だけ適用する（docs/config/test だけの PR はミューテーションを丸ごと省ける）。production 変更があれば従来どおり全 PIT。
SCOPE="$(dirname -- "$0")/mutation-scope.sh"
if [ -f "$SCOPE" ] && [ "$(sh "$SCOPE" mode)" = diff ]; then
  [ -n "$(sh "$SCOPE" changed 'src/main/*.kt' 'src/main/*.java' '*/src/main/*.kt' '*/src/main/*.java')" ] \
    || { echo "run-mutation: no changed production kt/java vs base — skipping (diff scope; PIT is schedule-first)"; exit 0; }
fi
# pitest は mutationThreshold（build.gradle.kts）未満だと非0で終了する。
./gradlew --no-daemon pitest
