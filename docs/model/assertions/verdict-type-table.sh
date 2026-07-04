#!/bin/sh
# assertion: harness-meta.es pol_verdict の decide=
#   「prevention は発火0でも keep。detection は高コスト×発火0のみ removal-candidate」
# を gate-roi-verdict.sh の実挙動で固定する（反事実の罠回避＝判定表の核）。
set -eu
ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"
VERDICT="$ROOT/core/scripts/gate-roi-verdict.sh"
TAB="$(printf '\t')"

# prevention（レジストリ在籍）× 発火0 → keep（発火0=無駄、で予防層を消させない）
out="$(printf 'check-no-committed-secrets.sh%s50%s0%s0%s5%s0.1\n' "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" | sh "$VERDICT")"
printf '%s\n' "$out" | grep -q '^keep check-no-committed-secrets' || {
  echo "主張違反: prevention×発火0 が keep にならない: $out"; exit 1; }

# detection × 発火0 × 高コスト → removal-candidate（提案のみ）
out="$(printf 'check-test-compiles.sh%s50%s0%s0%s999%s19.9\n' "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" | sh "$VERDICT")"
printf '%s\n' "$out" | grep -q '^removal-candidate check-test-compiles' || {
  echo "主張違反: detection×発火0×高コスト が removal-candidate にならない: $out"; exit 1; }

echo "pol_verdict decide= の型別判定表は実挙動と一致"
