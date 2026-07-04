#!/bin/sh
# [汎用core] mutation エスカレーション検出ゲート — スタック非依存
#
# WHY: spec-test の Stop hook（templates/hooks/spec-test-mutation-gate.sh）は、生存ミュータントを
# 消せないまま MAX_BLOCKS に達すると force-pass する。だがそれは「通過」ではなく、可視記録
# `.kiro/.gatecrate-mutation-escalated`（理由＋survivor 一覧）への ESCALATION。本ゲート（一次層・PR/CI）
# がその記録を検出して PR を fail させ、人が生存を消して記録を消すまで進ませない。
# = 「ローカルの Stop hook で粘って黙って抜ける」経路を多層防御で塞ぐ（Stop hook=即時層 / 本ゲート=CI層）。
#
# 記録は gitignore しない（コミットされて CI まで届く必要がある）。pending マーカー
# `.kiro/.gatecrate-mutation-pending` は transient なので gitignore 済み（別物）。
#
# Usage: sh check-mutation-escalation.sh
# Consumption model: repo root を git で解決するので kit(core/scripts/)でも消費者(scripts/)でも動く。
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd))"

ESCALATED="$ROOT/.kiro/.gatecrate-mutation-escalated"
if [ -f "$ESCALATED" ]; then
  echo "mutation-escalation: FAIL — an unresolved mutation escalation exists." >&2
  echo "The spec-test Stop hook force-passed surviving mutants. Record:" >&2
  sed 's/^/  /' "$ESCALATED" >&2
  echo "  Kill the surviving mutants (do not lower the floor), then delete $ESCALATED in the same PR." >&2
  exit 1
fi
echo "mutation-escalation: no unresolved escalation."
exit 0
