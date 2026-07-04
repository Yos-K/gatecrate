#!/bin/sh
# [汎用core] ドメイン知識文書の evidence 実在検証ゲート — スタック非依存
# gatecrate-type: prevention  (捏造 evidence を reject する予防ゲート。注入器なし＝人間マーカー)
#
# WHY: 深さゲート check-bc-domain は「evidence セルが非空か」しか見ない。ソースを読めないエージェントが
# もっともらしい file:method を**捏造**して埋めれば素通りする（実走で観測——TAKT 内 agent が実ファイルに
# アクセスできず `Foo.java:validateAccountCd()` 等の実在しないメソッドを書いてゲームした）。本ゲートは
# evidence の file:line / file:method 参照が**実コードに解決するか**を機械検証し捏造を弾く。
# ＝ check-bc-domain(深さ) と check-evidence-resolves(真実性) で対を成す。
#
# 合格条件: 用語集の各データ行の evidence セルが、解決する file 参照を**最低1つ**含むこと。解決とは:
#   - file が EVIDENCE_CODE_ROOT 配下に実在（basename / パス suffix で発見）。
#   - locator が行番号(数字)なら、ファイルの行数 >= その行。
#   - locator がメソッド名(英字+括弧 等)なら、その名がファイル中に出現。
#   - locator 無し（ファイル名のみ）なら、ファイル実在で可。
#
# Config (env):
#   EVIDENCE_CODE_ROOT — 解決先のコードベース根（既定: カレントの git リポ、無ければ "."）。
#
# Usage: sh check-evidence-resolves.sh <bc-domain-doc.md>
set -eu

DOC="${1:?usage: check-evidence-resolves.sh <bc-domain-doc.md>}"
[ -f "$DOC" ] || { echo "evidence: ERROR — file not found: $DOC" >&2; exit 2; }
ROOTC="${EVIDENCE_CODE_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"

# 用語集の evidence セルを1行ずつ取り出す（check-bc-domain と同じヘッダ検出）。
cells="$(awk '
  function low(s){ return tolower(s) }
  function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  /\|/ && !hdr {
    h = low($0)
    if (index(h,"用語")||index(h,"term")) if (index(h,"定義")||index(h,"definition")) \
       if (index(h,"不変条件")||index(h,"invariant")) if (index(h,"evidence")||index(h,"根拠")) {
      n = split($0, c, "|")
      for (i=1;i<=n;i++){ ci=low(trim(c[i])); if (index(ci,"evidence")||index(ci,"根拠")) ev=i }
      hdr=1; next } }
  hdr && /\|/ {
    if ($0 ~ /\|[ \t]*:?-+:?[ \t]*\|/) next
    n = split($0, c, "|"); if (n < 3) { hdr=0; next }
    print trim(c[ev]); next }
  hdr && $0 !~ /\|/ { hdr=0 }
' "$DOC")"

[ -n "$cells" ] || { echo "evidence: 用語集の evidence 列が見つかりません（check-bc-domain を先に通してください）。" >&2; exit 1; }

# 1参照を解決する。 resolve "<path>" "<locator>" -> 0 if ok
resolve_ref() {
  rp="$1"; loc="$2"
  base="$(basename "$rp")"
  f="$(find "$ROOTC" -type f -path "*/$rp" 2>/dev/null | head -1)"
  [ -n "$f" ] || f="$(find "$ROOTC" -type f -name "$base" 2>/dev/null | head -1)"
  [ -n "$f" ] || return 1                              # ファイル未発見
  [ -n "$loc" ] || return 0                            # ファイルのみ＝実在で可
  if printf '%s' "$loc" | grep -qE '^[0-9]+$'; then    # 行番号
    n="$(wc -l < "$f" | tr -d ' ')"; [ "$n" -ge "$loc" ] && return 0 || return 1
  fi
  name="$(printf '%s' "$loc" | sed 's/().*$//; s/(.*$//')"   # メソッド名（括弧前）
  [ -n "$name" ] || return 0
  grep -q "$name" "$f" && return 0 || return 1
}

# 各 evidence セルを評価（サブシェルでの集計消失を避けるため一時ファイル経由）。
tmp="$(mktemp)"; printf '%s\n' "$cells" > "$tmp"
unresolved=""; norow=""
while IFS= read -r cell; do
  [ -n "$cell" ] || continue
  # file 参照を抽出: <path>.<ext> 任意で :<locator>
  refs="$(printf '%s\n' "$cell" | grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z]+(:[0-9A-Za-z_()]+)?' || true)"
  if [ -z "$refs" ]; then
    norow="$norow | $cell"; continue
  fi
  rowok=0
  for ref in $refs; do
    rp="${ref%%:*}"; loc=""
    case "$ref" in *:*) loc="${ref#*:}";; esac
    if resolve_ref "$rp" "$loc"; then rowok=1; else unresolved="$unresolved $ref"; fi
  done
  [ "$rowok" -eq 1 ] || norow="$norow | $cell"
done < "$tmp"
rm -f "$tmp"

if [ -n "$unresolved" ] || [ -n "$norow" ]; then
  echo "evidence: FAIL — 解決しない/捏造の疑いがある evidence があります（root: ${ROOTC}）:" >&2
  [ -n "$unresolved" ] && echo "  未解決の参照:$unresolved" >&2
  [ -n "$norow" ] && echo "  解決可能な file 参照を含まない行:$norow" >&2
  echo "  各用語の evidence を実在する file:line または file:method に直してください（捏造は不可）。" >&2
  exit 1
fi
echo "evidence: 全ての evidence 参照が実コードに解決しました（root: ${ROOTC}）。pass."
