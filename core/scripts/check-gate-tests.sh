#!/bin/sh
# [汎用core] ゲート → 挙動テスト存在のメタゲート — スタック非依存
# gatecrate-type: prevention  (テスト無しゲートを reject するメタゲート；発火0=全ゲートにテスト在=正常)
#
# WHY: テストの無いゲートは「黙って壊れても気づけない」。これは実害として観測された——file-line ゲートが
# SCAN_NAMES の glob 展開バグでサブディレクトリを丸ごと走査漏れしていたのに、挙動テストが無かったため
# 緑のまま長期間気づかれなかった。本メタゲートは「出荷する reject 型ゲートは必ず挙動テストを持つ」を機械
# 強制し、testless なゲートの出荷・採用を構造で止める（probe の生存証明・file-line の回帰テストと同じ精神）。
#
# 判定: 各 reject 型ゲート `check-X.sh`（または probe-gate-liveness.sh）が在れば、`tests/test-check-X.sh`
# もしくは `tests/test-X.sh`（check- を除いた名・doc-currency 等の命名ゆれ対応）のどちらかが存在すること。
#
# Config (env):
#   GATE_TESTS_GATE_DIR — ゲートの在処（既定: core/scripts が在ればそれ、無ければ scripts）
#   GATE_TESTS_DIR      — テストの在処（既定: tests）。無ければ skip(exit 0・advisory)
#   GATE_TESTS_LIST     — テスト必須ゲートの一覧（空白/改行区切り・test seam）。既定は下記の curated list
#
# Usage: sh check-gate-tests.sh
# Consumption model: repo root を git で解決するので kit(core/scripts/)でも消費者(scripts/)でも動く。
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd))"

GATE_DIR="${GATE_TESTS_GATE_DIR:-}"
if [ -z "$GATE_DIR" ]; then
  if [ -d "$ROOT/core/scripts" ]; then GATE_DIR="core/scripts"; else GATE_DIR="scripts"; fi
fi
TESTS_DIR="${GATE_TESTS_DIR:-tests}"
if [ ! -d "$ROOT/$TESTS_DIR" ]; then
  echo "gate-tests: no tests directory ($TESTS_DIR); nothing to verify, skipping (advisory)."
  exit 0
fi

# reject 型ゲート（テスト必須）。計測 advisory（measure-*）・ユーティリティ（version-*/start-work/
# collect-gate-history/prepare-*/setup-branch-protection/pr-preflight）は対象外。
MUST_TEST="${GATE_TESTS_LIST:-check-conventional-title check-no-committed-secrets check-file-line-limit
check-hard-constraints check-posix-portability check-mutation-escalation check-doc-currency
check-rule-doc-currency check-merge-integrity check-release-version-name check-third-party-notices
check-domain-model check-gate-tests check-gate-classified probe-gate-liveness es-lint
check-diff-coverage check-no-received-approvals check-bc-domain check-evidence-resolves check-term-relations
check-modularity-ratchet check-es-assertions check-model-refuted probe-semantic-liveness
check-adr-review}"

missing=""
for g in $MUST_TEST; do
  [ -f "$ROOT/$GATE_DIR/$g.sh" ] || continue   # not adopted by this consumer
  if [ -f "$ROOT/$TESTS_DIR/test-$g.sh" ] || [ -f "$ROOT/$TESTS_DIR/test-${g#check-}.sh" ]; then
    continue
  fi
  missing="$missing $g"
done

if [ -n "$missing" ]; then
  echo "gate-tests: FAIL — shipped reject-type gate(s) with no behavior test:$missing" >&2
  echo "  Add $TESTS_DIR/test-<gate>.sh. A gate with no test can break silently (the file-line blind spot)." >&2
  exit 1
fi
echo "gate-tests: every shipped reject-type gate has a behavior test."
