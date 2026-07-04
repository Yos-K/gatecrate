#!/bin/sh
# [汎用コア] 用語の平易さ検査ゲート（prevention） — スタック非依存
# gatecrate-type: prevention
#
# WHY: CLAUDE.md Documentation Writing Rule §1「記号の単独使用禁止・初出時に日本語の説明を併記」。
# Tx-ID・p50・SLI 等の専門用語/記号を裸で使うと読み手の認知負荷が上がり、レビューが内容判断でなく
# 「これ何？」に費やされる。これをプロンプト（注意書き）に置くと再発するので、機械ゲートで強制する。
# 合格条件: 既知ジャーゴンが本文に現れるなら、その日本語説明(gloss)も**同じファイル内に最低1回**現れること
#   （＝初出で平易化していれば通る）。gloss が無ければ「説明なしの裸利用」として reject。
#
# マップ書式: 用語~gloss正規表現(|で言い換え列挙)~提案。追加は JARGON_EXTRA に同書式を改行/「;」区切りで。
# Usage: sh check-jargon.sh <file>   ( 違反があれば exit 1 )
set -eu
F="${1:?usage: check-jargon.sh <file>}"
[ -f "$F" ] || { echo "check-jargon: not found: $F" >&2; exit 2; }

JARGON="$(cat <<'MAP'
Tx-ID~取引ID|取引を識別~取引ID(取引を一意に識別する番号)
p50~中央値~p50=中央値
p99~遅い方|上位|1%~p99=遅い方から1%(ほぼ最悪値)
SLI~サービス品質|品質指標~サービス品質指標(SLI)
SLO~サービスレベル目標|目標値~サービスレベル目標(SLO)
histogram~分布|ヒストグラム~分布をとる
MAP
)"
[ -n "${JARGON_EXTRA:-}" ] && JARGON="$JARGON
$(printf '%s\n' "$JARGON_EXTRA" | tr ';' '\n')"

VIOL="$(mktemp)"
trap 'rm -f "$VIOL"' EXIT
printf '%s\n' "$JARGON" | while IFS= read -r rule; do
  [ -n "$rule" ] || continue
  term="${rule%%~*}"; tmp="${rule#*~}"; gloss="${tmp%%~*}"; sugg="${tmp#*~}"
  grep -Fq -- "$term" "$F" || continue          # 用語が本文に無ければ対象外
  grep -Eq -- "$gloss" "$F" && continue          # 説明(gloss)が在れば説明済
  echo "  [ERROR] 説明なしの専門用語: \"${term}\" を使用しているが説明（${gloss}）が本文に無い → 初出で「${sugg}」のように併記" >> "$VIOL"
done

echo "=== check-jargon: $F ==="
if [ -s "$VIOL" ]; then
  cat "$VIOL"
  echo "---- ERROR=$(wc -l < "$VIOL" | tr -d ' ') ----"
  exit 1
fi
echo "  OK: 説明なしの裸ジャーゴンなし"
echo "---- ERROR=0 ----"
