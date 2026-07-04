#!/bin/sh
# assertion: harness-meta.es pol_triage の decide=
#   「収束ループ(repairable-only)は escalation-only を probe の前にマーカーで構造的に除外して回る。
#    人間所有ゲートの DEAD は既定モード(全数生存証明)でのみ現れる」
# を probe-gate-liveness.sh の実挙動で固定する（exp3 対策＝probe 前の構造トリアージが本体）。
set -eu
ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT
git -C "$D" init -q
mkdir -p "$D/scripts"
cp "$ROOT/core/scripts/probe-gate-liveness.sh" "$D/scripts/"
# escalation-only マーカー付きの人間所有ゲート（違反は棄却する＝生きている）
printf '#!/bin/sh\n# gatecrate-scope: escalation-only\nexit 1\n' > "$D/scripts/governed-gate.sh"

# 収束ループの視界（--repairable-only）: probe されず SKIP＝ループは一度も見ない
out="$(cd "$D" && PROBE_GATES="scripts/governed-gate.sh:posix" sh scripts/probe-gate-liveness.sh --repairable-only 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || { echo "主張違反: repairable-only が escalation-only の除外で失敗した (rc=$rc): $out"; exit 1; }
printf '%s' "$out" | grep -q 'SKIP.*governed-gate' || { echo "主張違反: escalation-only が probe 前に除外されない: $out"; exit 1; }
printf '%s' "$out" | grep -q 'ALIVE governed-gate\|DEAD  governed-gate' && { echo "主張違反: ループが人間所有ゲートを probe してしまった: $out"; exit 1; }

# 既定モード（全数生存証明）: 同じゲートが probe され、壊れていれば人間に見える
out="$(cd "$D" && PROBE_GATES="scripts/governed-gate.sh:posix" sh scripts/probe-gate-liveness.sh 2>&1)" && rc=0 || rc=$?
printf '%s' "$out" | grep -q 'ALIVE governed-gate' || { echo "主張違反: 既定モードが人間所有ゲートを probe しない: $out"; exit 1; }

echo "pol_triage decide=（probe 前の構造的除外・既定モードは全数）は実挙動と一致"
