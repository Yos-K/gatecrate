#!/bin/sh
# assertion: harness-meta.es cmd_probe の decide=
#   「ゲートが exit 1=違反を棄却=ALIVE。exit 0=受理=DEAD。他は setup error（ALIVE と報告しない）」
# を probe-gate-liveness.sh --one の実挙動で固定するマイクロ characterization。
set -eu
ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"
PROBE="$ROOT/core/scripts/probe-gate-liveness.sh"

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT
printf '#!/bin/sh\nexit 1\n' > "$D/rejecting-gate.sh"   # 違反を棄却するゲート
printf '#!/bin/sh\nexit 0\n' > "$D/accepting-gate.sh"   # 違反を受理する（壊れた）ゲート
printf '#!/bin/sh\nexit 5\n' > "$D/weird-gate.sh"       # 想定外の exit code

out="$(sh "$PROBE" --one "$D/rejecting-gate.sh" filesize 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || { echo "主張違反: exit 1 のゲートが ALIVE(rc=0) にならない (rc=$rc)"; exit 1; }
printf '%s' "$out" | grep -q 'ALIVE' || { echo "主張違反: ALIVE が報告されない: $out"; exit 1; }

out="$(sh "$PROBE" --one "$D/accepting-gate.sh" filesize 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 1 ] || { echo "主張違反: exit 0 のゲートが DEAD(rc=1) にならない (rc=$rc)"; exit 1; }
printf '%s' "$out" | grep -q 'DEAD' || { echo "主張違反: DEAD が報告されない: $out"; exit 1; }

out="$(sh "$PROBE" --one "$D/weird-gate.sh" filesize 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 2 ] || { echo "主張違反: 想定外 exit がsetup error(rc=2) にならない (rc=$rc)"; exit 1; }
printf '%s' "$out" | grep -q 'ALIVE' && { echo "主張違反: setup error が ALIVE を騙った: $out"; exit 1; }

echo "cmd_probe decide= の exit 解釈は実挙動と一致"
