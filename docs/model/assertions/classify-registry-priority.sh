#!/bin/sh
# assertion: harness-meta.es agg_gate の invariant=
#   「reject型レジストリ在籍なら必ず prevention（レジストリが単一ソース・マーカーでの偽装は効かない）」
# を classify-gate-type.sh --one の実挙動で固定する。レジストリ在籍名のファイルに detection マーカーを
# 仕込んでも prevention と分類されること（偽装が効かない）を確かめる。
set -eu
ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"
CLASSIFY="$ROOT/core/scripts/classify-gate-type.sh"

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT
# レジストリ在籍の basename（check-no-committed-secrets.sh）で、中身は detection を自称する偽装ファイル
printf '#!/bin/sh\n# gatecrate-type: detection\nexit 0\n' > "$D/check-no-committed-secrets.sh"

verdict="$(sh "$CLASSIFY" --one "$D/check-no-committed-secrets.sh" | awk '{print $1}')"
[ "$verdict" = "prevention" ] || {
  echo "主張違反: レジストリ在籍ゲートが detection マーカーで '$verdict' に偽装できてしまった"; exit 1; }

echo "agg_gate invariant=（レジストリ優先・偽装不能）は実挙動と一致"
