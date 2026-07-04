#!/bin/sh
# [汎用core] マージ整合性の検査（PR の最終 head がマージ結果に含まれるか）— スタック非依存
#
# WHY: auto-merge レースの機械検知。全チェック緑+未解決スレッドのみの PR に対応コミットを push し、
# 直後にスレッドを解決すると、新コミットの CI 完了を待たず「旧 head」でマージが発火し、最後のコミットが
# 既定ブランチから漏れることがある（GitHub の仕様上ブランチ保護では防げない）。レビュー対応の往復が
# 多い AI 駆動開発では現実に踏みやすい。本ガードはマージ後に「PR の最終 head がマージコミットの祖先か」を
# 機械検証し、漏れを赤で知らせる（予防は不可能なので検出層。復旧＝漏れコミットの cherry-pick 再提出）。
#
# 責務分離: 本スクリプトは「検出」だけ（純 git・決定論・テスト可能）。issue 起票・通知は消費者の
# ワークフロー側（gh + issues:write + 文面ポリシーは消費者ごとに違う）に残す。失敗時 exit 1 を返すので、
# 呼び出し側が赤化 + 復旧手順の案内を行う。
#
# squash / rebase マージでは head SHA は履歴に残らず ancestor 検証が構造上できない。誤検知を出さない
# ため、マージコミットの親が2未満なら SKIP(exit 0・警告のみ)。
#
# Usage: sh check-merge-integrity.sh <pr_head_sha> <merge_commit_sha>
#   exit 0 = ok もしくは検証不能(squash/rebase)で SKIP
#   exit 1 = レース検知（最終 head がマージに含まれない・漏れコミットを stdout に列挙）
#   exit 2 = 引数不足/解決不能
# Consumption model: 他の core ゲートと違い、本スクリプトは「呼び出し元(CI checkout)のリポ」の履歴を
# 見るので、スクリプト自身の場所ではなく CWD から repo root を解決する（SHA はその checkout の commit）。
set -u

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

HEAD_SHA="${1:-}"
MERGE_SHA="${2:-}"
if [ -z "$HEAD_SHA" ] || [ -z "$MERGE_SHA" ]; then
  echo "merge-integrity: usage: check-merge-integrity.sh <pr_head_sha> <merge_commit_sha>" >&2
  exit 2
fi

# Both SHAs must resolve to a commit in this checkout (the caller fetches the PR head first,
# since the branch may be auto-deleted). Unresolvable -> exit 2 (cannot verify; not a silent pass).
for sha in "$HEAD_SHA" "$MERGE_SHA"; do
  if ! git rev-parse --verify --quiet "$sha^{commit}" >/dev/null 2>&1; then
    echo "merge-integrity: '$sha' is not a resolvable commit (fetch the PR head first?)." >&2
    exit 2
  fi
done

# squash/rebase merges keep no parent link to the PR head -> ancestor check is structurally
# impossible. Skip (warn only) so it never false-positives on a legitimate squash merge.
PARENT_COUNT="$(git cat-file -p "$MERGE_SHA" | grep -c '^parent ' || true)"
if [ "$PARENT_COUNT" -lt 2 ]; then
  echo "merge-integrity: squash/rebase merge detected (parents=$PARENT_COUNT); ancestor check skipped."
  exit 0
fi

if git merge-base --is-ancestor "$HEAD_SHA" "$MERGE_SHA"; then
  echo "merge-integrity: ok — PR head $HEAD_SHA is contained in merge $MERGE_SHA."
  exit 0
fi

echo "merge-integrity: FAIL — auto-merge race: final head $HEAD_SHA is NOT in merge $MERGE_SHA." >&2
echo "Commits that did not make it into the merge:" >&2
git log --oneline "$MERGE_SHA..$HEAD_SHA" | head -50 | sed 's/^/  /' >&2
echo "Recovery: cherry-pick the missing commit(s) onto a fresh branch and re-open the PR." >&2
exit 1
