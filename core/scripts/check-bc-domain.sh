#!/bin/sh
# [汎用core] BC ドメイン知識文書の深さゲート — スタック非依存
# gatecrate-type: prevention  (規定の深さに満たない分析文書を reject する予防ゲート。注入器なし＝人間マーカー)
#
# WHY: レガシーのドメイン知識抽出をエージェントに任せると「深さ」がぶれる——浅すぎて使えない、または止まらず無限に掘る。
# スキルの注意書き（判断層）では制御できない。本ゲートは「1つの境界付けられたコンテキスト(BC)のドメイン知識文書が、
# 規定の深さに達したか」を機械判定し、TAKT の command ゲートとして「これ以上掘るべきか/もう十分か」を強制する。
# ＝ legacy-domain-extraction の「どこまで」を機械化する核。
#
# 規定の深さ（合格条件・全て満たすこと）:
#   1. 用語集に >= BC_MIN_TERMS 個の用語。各用語に「定義・不変条件・evidence」が**全て非空**（"-"/"—"/"未"/"TBD"/"?" は空扱い）。
#   2. ユースケース/流れ の節がある（見出しに ユースケース|流れ|use case|flow）。
#   3. hotspot の節がある（見出しに hotspot）。
#
# 用語集の契約: ヘッダ行が `|` 区切りで 用語|term・定義|definition・不変条件|invariant・evidence|根拠 の4語を含むこと。
# その下の `|` データ行を用語行として、上記3列が非空な行を数える。
#
# Config (env):
#   BC_MIN_TERMS — 必要な用語数（既定 12。中核BCは15・支援BCは8 等、呼び側=TAKTが渡す）
#
# Usage: sh check-bc-domain.sh <bc-domain-doc.md>
set -eu

DOC="${1:?usage: check-bc-domain.sh <bc-domain-doc.md>}"
MIN="${BC_MIN_TERMS:-12}"
[ -f "$DOC" ] || { echo "bc-domain: ERROR — file not found: $DOC" >&2; exit 2; }

# 1) 用語集の評価（ヘッダ検出 → 定義/不変条件/evidence 列の非空行を数える）。
valid="$(awk -v OFS='\t' '
  function low(s){ return tolower(s) }
  function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  # ph(s): 空 or プレースホルダ（空白/"-"/"—"/"?"/"未..."/"TBD"/"n/a"）なら 1。
  # 注: BSD awk は em-dash 等の多バイト literal の `==` 比較が誤マッチするので、多バイトは regex で判定する
  # （regex マッチは多バイトでも正常）。ASCII literal の `==` のみ使う。
  function ph(s){
    if (s=="") return 1
    if (s ~ /^[ \t-]+$/) return 1            # 空白/ASCIIハイフンのみ
    if (s ~ /^—+$/) return 1                 # em-dash のみ
    if (s=="?"||s=="TBD"||s=="tbd"||s=="n/a"||s=="N/A") return 1
    if (s ~ /^未/) return 1
    return 0
  }
  # ヘッダ候補: パイプ行に4語が揃う
  /\|/ && !hdr {
    h = low($0)
    if (index(h,"用語")||index(h,"term")) if (index(h,"定義")||index(h,"definition")) \
       if (index(h,"不変条件")||index(h,"invariant")) if (index(h,"evidence")||index(h,"根拠")) {
      n = split($0, c, "|")
      for (i=1;i<=n;i++) {
        ci = low(trim(c[i]))
        if (index(ci,"定義")||index(ci,"definition")) def=i
        if (index(ci,"不変条件")||index(ci,"invariant")) inv=i
        if (index(ci,"evidence")||index(ci,"根拠")) ev=i
      }
      hdr=1; next
    }
  }
  # ヘッダ確定後、パイプ行をデータ行として評価（区切り行 |---| は除外）
  hdr && /\|/ {
    if ($0 ~ /\|[ \t]*:?-+:?[ \t]*\|/) next     # markdown 区切り行
    n = split($0, c, "|")
    if (n < 3) { hdr=0; next }                  # 表が終わった
    d=trim(c[def]); i2=trim(c[inv]); e=trim(c[ev])
    if (!ph(d) && !ph(i2) && !ph(e)) count++
    next
  }
  hdr && $0 !~ /\|/ { hdr=0 }                    # 空行等で表終わり
  END { print count+0 }
' "$DOC")"

# 2) ユースケース節・3) hotspot 節
has_uc=0; has_hot=0
grep -qiE '^#+.*(ユースケース|流れ|use.?case|flow)' "$DOC" && has_uc=1
grep -qiE '^#+.*(hotspot|ホットスポット)' "$DOC" && has_hot=1

miss=""
[ "$valid" -ge "$MIN" ] || miss="$miss 用語(完全な定義/不変条件/evidence を持つ用語が ${valid}/${MIN})"
[ "$has_uc" -eq 1 ] || miss="$miss ユースケース/流れ節"
[ "$has_hot" -eq 1 ] || miss="$miss hotspot節"

if [ -n "$miss" ]; then
  echo "bc-domain: FAIL — $DOC は規定の深さに未達:$miss" >&2
  echo "  各用語に『定義・不変条件(実値)・evidence(コード行)』を埋め、ユースケース/流れ と hotspot 節を足してください。" >&2
  exit 1
fi
echo "bc-domain: $DOC は規定の深さ（用語 ${valid}>=${MIN}・ユースケース有・hotspot有）。pass."
