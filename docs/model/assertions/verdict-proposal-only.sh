#!/bin/sh
# assertion: harness-meta.es cmd_verdict の decide=
#   「提案のみ。安全制約はメトリクスで自動撤去しない——削除は常に人間が PR で行う」
# を gate-roi-verdict.sh の実挙動で固定する: removal-candidate ですら「提案」であり
# （PROPOSAL・human の明記）、対象ゲートのファイルには一切触れないこと。
set -eu
ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"
VERDICT="$ROOT/core/scripts/gate-roi-verdict.sh"
TAB="$(printf '\t')"

TARGET="$ROOT/core/scripts/check-test-compiles.sh"   # detection ゲート（removal-candidate を出させる）
before="$(git hash-object "$TARGET")"

out="$(printf 'check-test-compiles.sh%s50%s0%s0%s999%s19.9\n' "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" | sh "$VERDICT")"

printf '%s\n' "$out" | grep -q 'removal-candidate check-test-compiles' \
  || { echo "主張違反: removal-candidate が出ない前提が崩れた: $out"; exit 1; }
printf '%s\n' "$out" | grep -qi 'PROPOSAL' || { echo "主張違反: 提案（PROPOSAL）と明記されない: $out"; exit 1; }
printf '%s\n' "$out" | grep -qi 'human' || { echo "主張違反: 人間承認の明記が無い: $out"; exit 1; }

after="$(git hash-object "$TARGET")"
[ "$before" = "$after" ] || { echo "主張違反: verdict が対象ゲートのファイルを変更した（自動撤去の芽）"; exit 1; }

echo "cmd_verdict decide=（提案のみ・ファイル無変更・人間承認明記）は実挙動と一致"
