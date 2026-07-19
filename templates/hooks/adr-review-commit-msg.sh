#!/bin/sh
# templates/hooks/adr-review-commit-msg.sh — commit-msg フック: ADR レビュー宣言の即時検査
#
# CI（check-adr-review.sh の範囲モード）が最終防衛線だが、コミット時点で欠落を知らせた方が
# 手戻りが小さい。ロジックはゲート本体の `--message` モードに一本化する——フック側に検査を
# 重複実装すると本体と黙ってドリフトするため、このフックは薄い委譲だけを持つ。
#
# インストール（消費者リポで）:
#   cp templates/hooks/adr-review-commit-msg.sh .git/hooks/commit-msg
#   chmod +x .git/hooks/commit-msg
#   （core.hooksPath 運用ならその配下に commit-msg として配置）
set -eu

ROOT="$(git rev-parse --show-toplevel)"
for dir in scripts core/scripts; do
  if [ -f "$ROOT/$dir/check-adr-review.sh" ]; then
    exec sh "$ROOT/$dir/check-adr-review.sh" --message "$1"
  fi
done
echo "adr-review commit-msg hook: check-adr-review.sh not found (scripts/ or core/scripts/)." >&2
echo "Adopt the gate via sync, or remove this hook." >&2
exit 1
