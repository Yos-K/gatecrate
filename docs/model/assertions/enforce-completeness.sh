#!/bin/sh
# assertion: harness-meta.es cmd_enforce の decide=
#   「untyped のゲートを PR ごとに reject（check-gate-classified）」
# を消費者と同じ形（scripts/ にコピーした消費可能形）の実挙動で固定する。
set -eu
ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT
git -C "$D" init -q
mkdir -p "$D/scripts"
cp "$ROOT/core/scripts/check-gate-classified.sh" "$ROOT/core/scripts/classify-gate-type.sh" \
   "$ROOT/core/scripts/probe-gate-liveness.sh" "$D/scripts/"

# untyped なゲート（exit 1 経路あり・マーカー無し・レジストリ外）→ reject されること
printf '#!/bin/sh\nif [ -f bad ]; then exit 1; fi\nexit 0\n' > "$D/scripts/check-foo.sh"
out="$(cd "$D" && sh scripts/check-gate-classified.sh 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 1 ] || { echo "主張違反: untyped ゲートが reject されない (rc=$rc): $out"; exit 1; }
printf '%s' "$out" | grep -q 'check-foo' || { echo "主張違反: untyped の名指しが無い: $out"; exit 1; }

# 型マーカーを付ければ通ること（分類の促し＝出口がある）
printf '#!/bin/sh\n# gatecrate-type: detection\nif [ -f bad ]; then exit 1; fi\nexit 0\n' > "$D/scripts/check-foo.sh"
( cd "$D" && sh scripts/check-gate-classified.sh >/dev/null 2>&1 ) \
  || { echo "主張違反: 分類済みゲートまで reject された"; exit 1; }

echo "cmd_enforce decide=（untyped を reject・分類すれば通る）は実挙動と一致"
