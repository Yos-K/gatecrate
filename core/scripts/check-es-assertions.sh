#!/bin/sh
# [汎用コア] .es 意味的主張の実行可能化ゲート（prevention） — スタック非依存
# gatecrate-type: prevention
#
# WHY: 文法ゲート（es-lint）と evidence 実在検証は「形」を守るが、decide=/invariant= の**意味的主張**が
# 実挙動と一致するかは守れない（実害: 因果が逆流したモデルが全ゲート green のまま存在した）。意味は直接
# 判定できないので、gatecrate 流に**機械判定可能な表現へ降ろす**——ノードに `test=` 属性でマイクロ検証
# スクリプト（主張どおりに動くかを固定入力で確かめる characterization）を添付させ、本ゲートは
# 「存在し・実行して exit 0」だけを強制する。「1ルール=2反映」（spec-rules）のモデル版。
#
# 意味的正しさ4層の第1層（最強・適用は主張ごとに漸進）。第2層=三角測量(es-lint-info R11/R12)、
# 第3層=反証記録の鮮度(check-model-refuted)、第4層=レビュー工程への probe(probe-semantic-liveness)。
#
# 形式: N 行に `| test=<path>[,<path>…]`（repo root 相対）。test= の無いノードには何も要求しない
# （採用は漸進的）。ただし decide= を持つのに test= が無いノード数を「未ピン主張」として報告する
# （非ブロック・作業キューの可視化）。
#
# Config (env):
#   ES_ASSERT_ROOT — test= パスの解決根（既定: 本スクリプトの git root）。テスト/多リポ用シーム。
# Usage: sh check-es-assertions.sh <model.es>   （不在・失敗する assertion があれば exit 1）
set -eu

MODEL="${1:?usage: check-es-assertions.sh <model.es>}"
[ -f "$MODEL" ] || { echo "check-es-assertions: model not found: $MODEL" >&2; exit 2; }

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd))"
AROOT="${ES_ASSERT_ROOT:-$ROOT}"

# N 行から id \t test= 値 / decide 有無を射影
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
awk '
  /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
  $1=="N" {
    id=$2; t=""; d=0
    if (match($0, /\|[[:space:]]*test=[^|]*/)) {
      t=substr($0, RSTART, RLENGTH); sub(/^\|[[:space:]]*test=/,"",t)
      gsub(/^[[:space:]]+|[[:space:]]+$/,"",t)
    }
    if (index($0, "decide=") > 0) d=1
    # 空の test= は "-" プレースホルダ（TAB は IFS 空白扱いで連続すると read がフィールドを潰すため）
    if (t == "") t = "-"
    printf "%s\t%s\t%d\n", id, t, d
  }
' "$MODEL" > "$WORK/nodes"

echo "=== check-es-assertions: $MODEL (assert root: $AROOT) ==="
fails=0; pinned=0; unpinned=0
while IFS="$(printf '\t')" read -r id tval hasdec; do
  if [ "$tval" = "-" ]; then
    [ "$hasdec" = "1" ] && unpinned=$((unpinned + 1))
    continue
  fi
  # test= はカンマ/セミコロン/空白区切りで複数可。全てが存在し exit 0 であること。
  for p in $(printf '%s\n' "$tval" | tr ',;' '  '); do
    [ -n "$p" ] || continue
    f="$AROOT/$p"
    if [ ! -f "$f" ]; then
      echo "  [ERROR] $id の test= \"$p\" が $AROOT 配下に存在しない（実行できない検証で主張を飾れない）"
      fails=$((fails + 1)); continue
    fi
    if out="$(sh "$f" 2>&1)"; then
      echo "  OK    $id — $p"
      pinned=$((pinned + 1))
    else
      echo "  [ERROR] $id の主張が検証に失敗: $p — モデルの decide=/invariant= と実挙動が一致しない"
      printf '%s\n' "$out" | sed 's/^/          /'
      fails=$((fails + 1))
    fi
  done
done < "$WORK/nodes"

echo "---- pinned=$pinned / 未ピン主張(decide= あり test= なし)=$unpinned / ERROR=$fails ----"
if [ "$unpinned" -gt 0 ]; then
  echo "  (未ピンは非ブロック。重要な主張から test= を足していく——ホットスポット優先)"
fi
[ "$fails" -eq 0 ] || exit 1
exit 0
