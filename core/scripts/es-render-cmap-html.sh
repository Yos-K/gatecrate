#!/bin/sh
# [汎用コア] es-render-cmap-html.sh — 横断コンテキストマップのハブHTML生成（ツール・非ゲート）
#
# WHY: 複数リポを束ねて ES モデリングすると、複数の AS-IS が同一の TO-BE に収束する。BC別ビューア
# （es-render-html の AS-IS/TO-BE タブ）だけでは TO-BE が各ページに重複して見える——これは表示でなく
# 「TO-BE の源泉が複数箇所にある」構造の問題で、解は横断 `.cmap` 1つへの一本化。本ツールはその `.cmap` を
# 源泉として「全体コンテキストマップ1枚」の自己完結HTMLへ決定論射影する。各BCノードのクリックで
# そのBCの ES ビューアへ遷移する（click 行は es= 属性から機械生成。AI が座標も click も手書きしない）。
#
# `.cmap` の追加属性（本ツールが読む・es-cmap-lint は未知属性を許容）:
#   BC 行 | domain=<ドメイン群名>  … 同じ値の BC を subgraph（枠）にまとめる
#   BC 行 | es=<相対href>          … クリック遷移先（そのBCの ES ビューア html）。無い BC は
#                                    クリック不可で「ESモデル未作成（次に作る対象）」として一覧される
#
# Usage: sh es-render-cmap-html.sh <map.cmap> [タイトル] > hub.html
#   推奨: sh es-cmap-lint.sh map.cmap && sh es-render-cmap-html.sh map.cmap "CPS 全体コンテキストマップ" > hub.html
# 注意: Mermaid ライブラリのみ CDN(jsdelivr) から読む（es-render-html と同じ方針）。マップデータは HTML に内蔵。
set -eu

CMAP="${1:?usage: es-render-cmap-html.sh <map.cmap> [title]}"
TITLE="${2:-全体コンテキストマップ}"
[ -f "$CMAP" ] || { echo "es-render-cmap-html: cmap not found: $CMAP" >&2; exit 2; }

# --- HTML シェル（ヘッダ） ---
cat <<HTML
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${TITLE}</title>
<style>
  :root{--bg:#0d1117;--ink:#e6edf3;--muted:#8b97a3;--line:#243040;--core:#4ea1ff;}
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--ink);
       font-family:-apple-system,BlinkMacSystemFont,"Hiragino Sans","Noto Sans JP",sans-serif;line-height:1.6}
  header{padding:22px 24px 14px;border-bottom:1px solid var(--line)}
  h1{margin:0 0 6px;font-size:21px}
  .sub{color:var(--muted);font-size:13px;max-width:1000px}
  .legend{margin-top:8px;font-size:12px;color:var(--muted)}
  .legend b{color:var(--ink)}
  .wrap{max-width:1280px;margin:0 auto;padding:14px 18px 40px}
  .mapbox{background:#0f1620;border:1px solid var(--line);border-radius:12px;padding:10px;overflow:auto}
  .mermaid{min-width:1100px}
  .hint{color:var(--muted);font-size:12px;margin:10px 2px}
</style>
<script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
</head>
<body>
<header>
  <h1>${TITLE}</h1>
  <div class="sub">境界づけられたコンテキスト（BC）と関係の全体像。<b>BC（箱）をクリックすると、
  そのコンテキストのイベントストーミング図が開きます</b>（クリック可否は es= 属性の有無）。
  矢印のラベルは「関係種別と連結キー」。
  <div class="legend"><b style="color:#3fb950">緑</b>=core（注力）／<b style="color:#4ea1ff">青</b>=supporting／
  <b style="color:#b083f0">紫</b>=generic／<b style="color:#9aa4b0">灰</b>=外部システム</div></div>
</header>
<div class="wrap">
  <div class="mapbox">
    <pre class="mermaid">
HTML

# --- .cmap -> Mermaid（決定論射影） ---
awk '
  function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/,"",s); return s }
  function attr(line, name,   v) {
    if (match(line, "\\|[[:space:]]*" name "=[^|]*")) {
      v = substr(line, RSTART, RLENGTH); sub("^\\|[[:space:]]*" name "=", "", v); return trim(v)
    }
    return ""
  }
  function namepart(line, tag,   nm) {
    nm = line
    sub("^[[:space:]]*" tag "[[:space:]]+[^[:space:]]+[[:space:]]*", "", nm)
    sub(/[[:space:]]*\|.*$/, "", nm)
    gsub(/"/, "", nm)
    return trim(nm)
  }
  /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
  $1=="BC" {
    id=$2; nb++; bid[nb]=id
    bname[id]=namepart($0, "BC")
    k=attr($0, "kind"); bkind[id]=(k=="core"||k=="generic") ? k : "supporting"
    bdom[id]=attr($0, "domain"); bes[id]=attr($0, "es")
    if (bdom[id] != "" && !(bdom[id] in domseen)) { domseen[bdom[id]]=1; nd++; dom[nd]=bdom[id] }
    next
  }
  $1=="EXT" {
    id=$2; nx++; xid[nx]=id
    xname[id]=namepart($0, "EXT")
    next
  }
  $1=="REL" {
    nr++; rf[nr]=$2; rt[nr]=$3; rto[nr]=$4
    rkey[nr]=attr($0, "key")
    next
  }
  END {
    print "flowchart LR"
    print "  classDef core fill:#13241b,stroke:#3fb950,color:#bfe9cb;"
    print "  classDef supporting fill:#13233a,stroke:#2d4f73,color:#cfe3ff;"
    print "  classDef generic fill:#1b1726,stroke:#8a63d2,color:#cbbce9;"
    print "  classDef ext fill:#1a1f26,stroke:#39424d,color:#9aa4b0;"
    print ""
    # ドメイン群 subgraph（domain= の初出順）
    for (d=1; d<=nd; d++) {
      print "  subgraph SG" d "[\"" dom[d] "\"]"
      for (i=1; i<=nb; i++) { id=bid[i]; if (bdom[id]==dom[d])
        print "    " id "[\"" bname[id] "\"]:::" bkind[id] }
      print "  end"
    }
    # domain= の無い BC はトップレベル
    for (i=1; i<=nb; i++) { id=bid[i]; if (bdom[id]=="")
      print "  " id "[\"" bname[id] "\"]:::" bkind[id] }
    # 外部システム
    for (i=1; i<=nx; i++) { id=xid[i]
      print "  " id "([\"" xname[id] "\"]):::ext" }
    print ""
    # 関係（種別 + 連結キー のラベル）
    for (r=1; r<=nr; r++) {
      lbl = rt[r]; if (rkey[r] != "") lbl = lbl ": " rkey[r]
      print "  " rf[r] " -->|\"" lbl "\"| " rto[r]
    }
    print ""
    # クリック配線（es= を持つ BC だけ。href は源泉の属性から機械生成）
    for (i=1; i<=nb; i++) { id=bid[i]; if (bes[id] != "")
      print "  click " id " \"" bes[id] "\" \"" bname[id] " ES\"" }
  }
' "$CMAP"

# --- フッタ: ESモデル未作成の BC 一覧（次に作る対象の可視化） ---
cat <<'HTML'
    </pre>
  </div>
HTML

MISSING="$(awk '
  function attr(line, name,   v) {
    if (match(line, "\\|[[:space:]]*" name "=[^|]*")) {
      v = substr(line, RSTART, RLENGTH); sub("^\\|[[:space:]]*" name "=", "", v)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); return v
    }
    return ""
  }
  /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
  $1=="BC" && attr($0, "es")=="" {
    nm=$0; sub(/^[[:space:]]*BC[[:space:]]+[^[:space:]]+[[:space:]]*/,"",nm); sub(/[[:space:]]*\|.*$/,"",nm)
    printf "%s（%s）、", $2, nm
  }
' "$CMAP")"
if [ -n "$MISSING" ]; then
  printf '  <div class="hint">ESモデル未作成（クリック不可・次に作る対象）: %s</div>\n' "${MISSING%、}"
fi

cat <<'HTML'
</div>
<script>
  mermaid.initialize({startOnLoad:true, securityLevel:'loose', theme:'dark',
    flowchart:{curve:'basis', nodeSpacing:45, rankSpacing:70}});
</script>
</body>
</html>
HTML
