#!/bin/sh
# assertion: harness-meta.es agg_hist の invariant= / cmd_collect の decide=
#   「集計は取得済み履歴の純関数（同一入力なら同一出力）」「fetch(非決定論)と aggregate(純関数)を分離」
# を collect-gate-history.sh --aggregate の実挙動で固定する（gh 不要＝分離の証明でもある）。
set -eu
ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"
COLLECT="$ROOT/core/scripts/collect-gate-history.sh"
TAB="$(printf '\t')"

records() {
  printf 'secrets%ssuccess%s3\nsecrets%sfailure%s4\ntitle%ssuccess%s1\n' \
    "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB"
}

# gh の無い環境でも --aggregate は動く（fetch との分離）
o1="$(records | PATH=/usr/bin:/bin sh "$COLLECT" --aggregate)" || { echo "主張違反: aggregate が fetch 無しで動かない"; exit 1; }
# 純関数: 同一入力 → 同一出力
o2="$(records | sh "$COLLECT" --aggregate)"
[ "$o1" = "$o2" ] || { echo "主張違反: 同一入力から出力が揺れた（純関数でない）"; exit 1; }
# 集計値: secrets は runs=2 fires=1
printf '%s\n' "$o1" | grep -q "^secrets${TAB}2${TAB}1" || { echo "主張違反: 集計値が期待と不一致: $o1"; exit 1; }

echo "agg_hist invariant= / cmd_collect decide=（分離・純関数）は実挙動と一致"
