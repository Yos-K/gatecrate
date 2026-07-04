#!/bin/sh
# [汎用コア] .es evidence ドリフト検証ゲート（prevention） — スタック非依存
# gatecrate-type: prevention
#
# WHY: 生きたモデルの .es は `evidence=path:line` で実コードに紐づく（証拠駆動）。コードが動くと参照が腐る
# （ドリフト）し、AIは捏造 evidence を書く。これをプロンプトに置くと再発するので機械ゲートで弾く。
# es-render-html(描画) と es-lint-info(情報完全性) の対として、本ゲートが evidence の**真実性**を担保する。
# 合格条件: `.es` の各 evidence= に含まれる「コードファイル参照」が EVIDENCE_CODE_ROOT 配下に最低1つ実在すること。
#   - ファイル参照 = 拡張子つきトークン（例 Foo.java:12 / a/b/Bar.kt）。basename / パス suffix で発見。
#   - 拡張子のないトークン（設計 / AS-IS:… / hypothesis）はコードでないので検査対象外（スキップ）。
# EVIDENCE_CODE_ROOT — 解決先コード根（既定: .es のあるgitリポ、無ければ "."）。
# Usage: EVIDENCE_CODE_ROOT=<code> sh check-es-evidence.sh <model.es>
set -eu
MODEL="${1:?usage: check-es-evidence.sh <model.es>}"
[ -f "$MODEL" ] || { echo "check-es-evidence: not found: $MODEL" >&2; exit 2; }
ROOT="${EVIDENCE_CODE_ROOT:-$(git -C "$(dirname -- "$MODEL")" rev-parse --show-toplevel 2>/dev/null || echo .)}"

# 各 N 行の evidence= から「拡張子つきファイル参照」を抽出（id\tfileref を1行ずつ）
refs="$(awk '
  /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
  $1=="N"{
    id=$2; line=$0
    if(match(line,/\|[[:space:]]*evidence=/)){
      v=substr(line,RSTART+RLENGTH); sub(/[[:space:]]*\|.*$/,"",v)
      nt=split(v,toks,/[,; ]+/)
      for(i=1;i<=nt;i++){ t=toks[i]; sub(/:.*$/,"",t)            # path:line -> path
        if(t ~ /\.[A-Za-z][A-Za-z0-9]+$/) print id "\t" t }      # 拡張子つきだけ
    }
  }' "$MODEL")"

miss="$(mktemp)"; checked=0
# IFS=tab で id と ref を分ける
OLDIFS="$IFS"; IFS='	'
printf '%s\n' "$refs" | while read -r id ref; do
  [ -n "$ref" ] || continue
  checked=$((checked+1))
  base="$(basename -- "$ref")"
  if ! find "$ROOT" -name .git -prune -o -type f -name "$base" -print 2>/dev/null | grep -q .; then
    echo "  [ERROR] evidence未解決: $id の \"$ref\" は $ROOT 配下に見つからない（ドリフト/捏造の疑い）" >> "$miss"
  fi
done
IFS="$OLDIFS"

echo "=== check-es-evidence: $MODEL (code root: $ROOT) ==="
if [ -s "$miss" ]; then
  cat "$miss"
  n=$(wc -l < "$miss" | tr -d ' ')
  echo "---- ERROR=$n ----"
  rm -f "$miss"; exit 1
fi
echo "  OK: evidence のファイル参照は全て解決"
echo "---- ERROR=0 ----"
rm -f "$miss"
