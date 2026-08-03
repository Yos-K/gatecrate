#!/bin/sh
# [汎用core] 意図された反例に理由を強制するゲート（Alloy spec）— スタック非依存
# gatecrate-type: prevention  (無言の expect 格下げを reject する予防ゲート)
#
# WHY: `.als` の `check ... expect 1` は「意図された反例（deliberate gap）」を表す規約
# （templates/spec/models/example.als.example が示す）。だがその意図が**書かれているか**は
# 誰も検査していなかった。これは収束ループにとって致命的な穴になる——反例の出たアサートを
# `expect 0` から `expect 1` へ書き換えるだけで緑にでき、「設計意図でした」という名目で
# ルール退行を静かに飲み込める。characterization trap（バグを仕様として凍結する罠）の Alloy 版であり、
# 「緑になるまで押し続ける」構造的圧力の下では必ず起きる。
#
# 本ゲートは expect N (N>0) に理由の明記を要求する。**格下げを禁止するのではなく、宣言と理由を
# 強制する**——このリポの `ADR-Review: none (<reason>)` と同じ思想。理由が要れば無言では通せず、
# 差分レビューで人間の目に入る。
#
# 検査すること: 意図された反例に理由が添えられているか（機械的に検査できるのはここまで）。
# 検査できないこと（意図的）: その理由が誠実か。不誠実な理由の検出は設計レビューの仕事であり、
# 乱用は差分に残るので観測可能である。
#
# 合格条件: 各 `check ... expect <N>`（N>0・コメント行でない）が、同一行の末尾コメントか
# 直前のコメント行に理由マーカー（既定 `intended:`）を持つこと。
#
# Config (env):
#   MODEL_PATHS      — 探索パス（既定: docs/domain/models）。空白区切りで複数可
#   INTENT_MARKER    — 理由マーカー（既定: intended:）
#
# Usage: sh check-intended-counterexample.sh [<model.als> ...]
# Consumption model: repo root を git で解決するので kit でも消費者でもそのまま動く。
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
MODEL_PATHS="${MODEL_PATHS:-docs/domain/models}"
INTENT_MARKER="${INTENT_MARKER:-intended:}"

# 引数指定が無ければ既定パスを探索する（.als が無いのは検査不能であって違反ではない）
if [ "$#" -ge 1 ]; then
  set -- "$@"
else
  set --
  for d in $MODEL_PATHS; do
    [ -d "$ROOT/$d" ] || continue
    for f in "$ROOT/$d"/*.als; do [ -f "$f" ] && set -- "$@" "$f"; done
  done
fi
if [ "$#" -eq 0 ]; then
  echo "intended-counterexample: no .als models found — nothing to check."
  exit 0
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT INT TERM
: > "$TMP"

for model in "$@"; do
  [ -f "$model" ] || continue
  awk -v marker="$INTENT_MARKER" -v file="$model" '
    # 直前行がコメントで理由を含むか覚えておく（理由は同一行末でも直前行でもよい）
    {
      line = $0
      is_comment = (line ~ /^[[:space:]]*\/\//)
      # コメント行の check は例示（テンプレが解説で使う）。対象外
      if (!is_comment && line ~ /(^|[[:space:]])check[[:space:]]/ && line ~ /expect[[:space:]]+[1-9]/) {
        has_here = (index(line, marker) > 0)
        if (!has_here && !prev_has_marker) {
          name = line
          sub(/^.*[[:space:]]check[[:space:]]+/, "", name)
          sub(/^check[[:space:]]+/, "", name)
          sub(/[[:space:]].*$/, "", name)
          printf "%s:%d:%s\n", file, NR, name
        }
      }
      prev_has_marker = (is_comment && index(line, marker) > 0)
    }
  ' "$model" >> "$TMP"
done

n="$(wc -l < "$TMP" | tr -d ' ')"
if [ "$n" -eq 0 ]; then
  echo "intended-counterexample: every expect>0 documents its intent."
  exit 0
fi

echo "intended-counterexample: FAIL — an intended counterexample must say WHY:" >&2
while IFS=: read -r f l name; do
  echo "  $f:$l  check $name ... expect>0 has no '$INTENT_MARKER' reason" >&2
done < "$TMP"
cat >&2 <<MSG

  `expect 0` -> `expect 1` は「保証を諦める」変更です。理由なしに通すと、収束ループが
  ルール退行を「設計意図」と偽って緑にできます。同一行末か直前行にこう書いてください:
      check FooIsInjective for 5 expect 1  // $INTENT_MARKER <なぜ意図的か>
  保証を取り戻すなら expect 0 に戻し、モデルか実装を直してください。
MSG
exit 1
