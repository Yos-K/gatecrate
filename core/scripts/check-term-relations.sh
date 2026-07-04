#!/bin/sh
# [汎用core] BC ドメイン知識文書の「用語間のルール」強制ゲート — スタック非依存
# gatecrate-type: prevention  (用語間ルールの欠落を reject する予防ゲート。注入器なし＝人間マーカー)
#
# WHY: 深さゲート check-bc-domain は用語ごとの不変条件しか強制しない。だから**用語間のルール**——包含・多重度・
# ペア・整合・コンテキスト間の同一性——が抜ける（実走で観測: TAKT 生成の BC 文書に用語間ルールの節が無く、
# 関係は処理フローの記述に留まった）。ゲートが強制しない次元は agent が手を抜く（捏造ゲーミングと同型）。本ゲートは
# 「用語間のルール」節と、**型付き(包含/多重度/ペア/整合/同一性/依存)＋evidence** のルールを規定数以上含むことを強制する。
# ＝ check-bc-domain(用語の深さ) / check-evidence-resolves(真実性) / 本ゲート(用語間ルール) の三点で対を成す。
#
# 合格条件:
#   1. 「用語間のルール / 用語間の関係 / term relationships」等の節がある。
#   2. その節内に、**型キーワード(包含|多重度|ペア|整合|同一性|依存 / containment|multiplicity|pair|consistency|identity|requires|
#      shared kernel)** と **evidence 参照(file.ext:locator)** を**両方**含むルール行が >= TERM_REL_MIN 個。
#
# Config (env):
#   TERM_REL_MIN — 必要な用語間ルール数（既定 4。中核BCは多め）。
#
# Usage: sh check-term-relations.sh <bc-domain-doc.md>
set -eu

DOC="${1:?usage: check-term-relations.sh <bc-domain-doc.md>}"
MIN="${TERM_REL_MIN:-4}"
[ -f "$DOC" ] || { echo "term-relations: ERROR — file not found: $DOC" >&2; exit 2; }

result="$(awk '
  function low(s){ return tolower(s) }
  # 用語間ルールの節見出しか
  function is_rel_heading(s,   l){ l=low(s)
    if (index(s,"用語間")) return 1
    if (l ~ /term[ ._-]*relation/) return 1
    if (index(l,"relationship")) return 1
    if (l ~ /inter[ ._-]*term/) return 1
    return 0 }
  # 型キーワードを含むか（JP は index、EN は tolower+index。BSD awk の多バイト == を避ける）
  function has_type(s,   l){ l=low(s)
    if (index(s,"包含")||index(s,"多重度")||index(s,"ペア")||index(s,"整合")||index(s,"同一性")||index(s,"依存")) return 1
    if (index(l,"containment")||index(l,"multiplicity")||index(l,"pair")||index(l,"consistency")) return 1
    if (index(l,"identity")||index(l,"requires")||index(l,"shared kernel")||index(l,"shared-kernel")) return 1
    return 0 }
  # evidence 参照(file.ext:locator)を含むか
  function has_ref(s){ return (s ~ /[A-Za-z0-9_]+\.[A-Za-z]+:[0-9A-Za-z_(]/) }
  /^#+[ ]/ { insec = is_rel_heading($0) ? 1 : 0; if (insec) seen=1; next }
  insec && has_type($0) && has_ref($0) { count++ }
  END { print (seen+0) " " (count+0) }
' "$DOC")"
seen="${result%% *}"; count="${result#* }"

if [ "$seen" -ne 1 ]; then
  echo "term-relations: FAIL — 「用語間のルール」節がありません（${DOC}）。" >&2
  echo "  包含/多重度/ペア/整合/コンテキスト間の同一性 等の用語間ルールを、型キーワード＋evidence で節に書いてください。" >&2
  exit 1
fi
if [ "$count" -lt "$MIN" ]; then
  echo "term-relations: FAIL — 型付き＋evidence の用語間ルールが ${count}/${MIN}（${DOC}）。" >&2
  echo "  各ルールに型(包含|多重度|ペア|整合|同一性|依存)と evidence(file:line/method)を付けて ${MIN} 個以上に。" >&2
  exit 1
fi
echo "term-relations: $DOC は用語間ルール ${count}>=${MIN}（型付き＋evidence）。pass."
