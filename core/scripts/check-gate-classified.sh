#!/bin/sh
# [汎用core] ゲート → 型分類のメタゲート — スタック非依存
# gatecrate-type: prevention
#
# WHY (ROADMAP P4 / docs/probe-scope-and-gate-classification-decision.md §3 step2): ROI 剪定は各ゲートの型
# （prevention=発火0が正常・detection=発火で価値・advisory=ブロックしない）を要する。型の無い（untyped）
# ゲートは「分類し忘れ」で、剪定ロジックがどの軸で価値を測ればよいか決められない。本メタゲートは untyped を
# 機械検出して PR を止め、人間に分類（`# gatecrate-type:` マーカー付与 or reject レジストリ登録）を促す。
#
# できないこと（意図的・docs §3.2/§1）: 「意味的に誤分類されたラベルの検出」は **しない**。それは「空虚テストの
# 検出」と同じく機械では不能で、是正は人間の escalation。本ゲートが叱るのは untyped（穴）だけ——advisory /
# not-a-gate は正当な終端で叱らない（さもないと誤警報か見逃しになる）。
#
# 人間への委ね方（docs §3.2）: 失敗時は classify-gate-type.sh --explain の判断材料（派生証拠＋推論のはしご・
# 未検証の段は [UNVERIFIED] と明示）を載せる。判断材料なしの丸投げ（「untyped。直せ」だけ）は当て推量を招くので避ける。
#
# 判定: GATE_DIR の全 *.sh を classify --one にかけ、untyped が一つでもあれば fail(exit 1)。
#       prevention/detection/advisory（分類済み）と not-a-gate（ハーネスのツール）は許容。
#
# Config (env):
#   GATE_CLASSIFIED_DIR — ゲートの在処（既定: core/scripts が在ればそれ、無ければ scripts）
#
# Usage: sh check-gate-classified.sh
# Consumption model: repo root を git で解決するので kit(core/scripts/)でも消費者(scripts/)でも動く。
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd))"
GATE_DIR="${GATE_CLASSIFIED_DIR:-}"
if [ -z "$GATE_DIR" ]; then
  if [ -d "$ROOT/core/scripts" ]; then GATE_DIR="core/scripts"; else GATE_DIR="scripts"; fi
fi
CLASSIFY="$ROOT/$GATE_DIR/classify-gate-type.sh"
if [ ! -f "$CLASSIFY" ]; then
  echo "gate-classified: classify-gate-type.sh not in $GATE_DIR; nothing to verify, skipping (advisory)."
  exit 0
fi

untyped=""
for g in "$ROOT/$GATE_DIR"/*.sh; do
  [ -f "$g" ] || continue
  verdict="$(sh "$CLASSIFY" --one "$g" | awk '{print $1}')"
  [ "$verdict" = untyped ] && untyped="$untyped $g"
done

if [ -n "$untyped" ]; then
  echo "gate-classified: FAIL — unclassified gate(s). Add a '# gatecrate-type:' marker (or register a reject" >&2
  echo "  injector). Verify the type against the evidence below, then mark by hand (never auto-applied):" >&2
  for g in $untyped; do
    echo "" >&2
    sh "$CLASSIFY" --explain "$g" >&2
  done
  exit 1
fi
echo "gate-classified: every gate has a type (prevention/detection/advisory) or is not-a-gate."
