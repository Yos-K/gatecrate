#!/bin/sh
# [汎用core] 未承認 golden-master スナップショット（*.received.*）のコミットを reject — スタック非依存
# gatecrate-type: prevention  (まだ probe 注入器の無い reject ゲート。発火0=未承認スナップショット混入なし=正常)
#
# WHY: characterization（golden-master / approval）テストは現挙動を <name>.approved.txt に固定し、比較に失敗すると
# 実測を <name>.received.txt に書く。received は「まだ人間がレビュー＝承認していない挙動」で、これがコミットされると
# 「未レビューの挙動を仕様として紛れ込ませた」穴になる（characterization の罠の入口）。本ゲートはリポに入るのは必ず
# 承認済み approved だけ、を機械強制する（check-no-committed-secrets と同じ「禁止物の混入を止める」予防ゲート）。
#
# 判定: tracked（git 管理下）の *.received.* が1つでも在れば fail。untracked（ローカルの未コミット）は対象外
# ——それは characterization 実行の正常な中間生成物で、コミットされたものだけが穴。
#
# Config (env, from harness.config.sh):
#   RECEIVED_APPROVAL_GLOB — 検出する git pathspec（既定 "*.received.*"。例: 画像のみなら "*.received.png"）
#   RECEIVED_SCAN_DIR      — 走査対象リポのルート（既定: カレントの git リポ。test seam / 他リポ検査用）
#
# Usage: sh check-no-received-approvals.sh
# Consumption model: repo root を git で解決するので kit(core/scripts/)でも消費者(scripts/)でも動く。
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"

GLOB="${RECEIVED_APPROVAL_GLOB:-*.received.*}"
# 走査は「いま検査する作業ツリー」＝カレントのリポに対して行う（config 解決用の ROOT＝スクリプト自身のリポとは別物。
# 消費側では scripts/ に同梱されるので両者は一致するが、kit から他リポを検査する場合は別）。
SCAN_DIR="${RECEIVED_SCAN_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$ROOT")}"

# tracked ファイルだけを対象にする（untracked の received は正常な中間生成物）。
matches="$(git -C "$SCAN_DIR" ls-files -- "$GLOB" 2>/dev/null || true)"

if [ -n "$matches" ]; then
  echo "no-received-approvals: FAIL — committed un-approved golden-master snapshot(s) (matching '$GLOB'):" >&2
  printf '%s\n' "$matches" | sed 's/^/  /' >&2
  echo "  received は未レビューの挙動です。中身を確認し、正しければ approve（mv <name>.received.txt <name>.approved.txt" >&2
  echo "  または sh scripts/approve-characterization.sh <name>）、誤りなら実装を直してから再生成してください。" >&2
  echo "  コミットからは外す（.gitignore に '$GLOB' を追加すると再発を防げます）。" >&2
  exit 1
fi
echo "no-received-approvals: no committed *.received.* snapshots (matching '$GLOB'). pass."
