#!/bin/sh
# [汎用コア] イベントストーミング HTML ビューア生成器（ツール・非ゲート） — スタック非依存
#
# WHY: es-render.sh は .es を Mermaid へ決定論射影するが出力は静的。「図からドメインを読み取る」には、
# ノードをクリックして仕様(入力/処理/出力)・不変条件・根拠を読め、AS-IS(コードの流れ)と TO-BE(あるべき設計)を
# 切り替えて比較できる必要がある。本ツールは es-render と同じ「.es が source、図は射影、AIは座標を書かない」原則のまま、
# .es(+任意の .spec) を自己完結HTML(1枚)へ決定論射影する。第2引数に TO-BE モデルを渡すとタブ切替が出る。
#
# Usage: sh es-render-html.sh <asis.es> [tobe.es] > model.html
#   各モデルの隣に <name>.spec があれば「箱の内側(入力→処理→出力)」として自動的に読む。
#   推奨: sh es-lint.sh m.es && sh es-render-html.sh m.es > m.html
# 注意: Mermaid ライブラリのみ CDN(jsdelivr) から読む。ノードデータ・仕様は HTML に内蔵。
set -eu

# 引数を走査: .es は AS-IS/TO-BE、.cmap はコンテキストマップ
MODEL=""; TOBE=""; CMAP=""; CLD=""; ANALYSIS=""
for a in "$@"; do
  case "$a" in
    *.cmap) CMAP="$a" ;;
    *.cld) CLD="$a" ;;
    *.md) ANALYSIS="${ANALYSIS:+$ANALYSIS }$a" ;;
    *.es) if [ -z "$MODEL" ]; then MODEL="$a"; elif [ -z "$TOBE" ]; then TOBE="$a"; fi ;;
  esac
done
[ -n "$MODEL" ] || { echo "usage: es-render-html.sh <asis.es> [tobe.es] [map.cmap] [loops.cld] [analysis.md ...]" >&2; exit 1; }
for d in $ANALYSIS; do [ -f "$d" ] || { echo "es-render-html: analysis md not found: $d" >&2; exit 2; }; done
[ -f "$MODEL" ] || { echo "es-render-html: model not found: $MODEL" >&2; exit 2; }
[ -z "$TOBE" ] || [ -f "$TOBE" ] || { echo "es-render-html: tobe not found: $TOBE" >&2; exit 2; }
[ -z "$CMAP" ] || [ -f "$CMAP" ] || { echo "es-render-html: cmap not found: $CMAP" >&2; exit 2; }
[ -z "$CLD" ] || [ -f "$CLD" ] || { echo "es-render-html: cld not found: $CLD" >&2; exit 2; }
ASIS_SPEC="${MODEL%.es}.spec"; [ -f "$ASIS_SPEC" ] || ASIS_SPEC=""
TOBE_SPEC=""; [ -n "$TOBE" ] && { TOBE_SPEC="${TOBE%.es}.spec"; [ -f "$TOBE_SPEC" ] || TOBE_SPEC=""; }

# Mermaid 本体（flowchart + classDef + ノード + エッジ + クリック配線）を1モデル分出力
mermaid_body(){
  awk '
  function esc(s){ gsub(/"/,"",s); return s }
  BEGIN{
    so["actor"]="(["; sc["actor"]="])"; so["command"]="[/"; sc["command"]="/]"
    so["aggregate"]="{{"; sc["aggregate"]="}}"; so["event"]="["; sc["event"]="]"
    so["errorevent"]="["; sc["errorevent"]="]"; so["policy"]="[["; sc["policy"]="]]"
    so["readmodel"]="("; sc["readmodel"]=")"; so["external"]=">"; sc["external"]="]"; so["hotspot"]="["; sc["hotspot"]="]"
    print "flowchart LR"
    print "    classDef actor fill:#FFE8CC,stroke:#D9480F,color:#000"
    print "    classDef command fill:#4DABF7,stroke:#1971C2,color:#000"
    print "    classDef aggregate fill:#FFE066,stroke:#F08C00,color:#000"
    print "    classDef event fill:#FFA94D,stroke:#E8590C,color:#000"
    print "    classDef errorevent fill:#FFA8A8,stroke:#E03131,color:#000"
    print "    classDef policy fill:#DA77F2,stroke:#9C36B5,color:#fff"
    print "    classDef readmodel fill:#B2F2BB,stroke:#2F9E44,color:#000"
    print "    classDef external fill:#FFD8A8,stroke:#D9480F,color:#000"
    print "    classDef hotspot fill:#FF6B6B,stroke:#C92A2A,color:#fff"
  }
  /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
  $1=="N"{ id=$2; t=$3; line=$0; sub(/^N[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+/,"",line)
    lbl=line; sub(/[[:space:]]*\|.*$/,"",lbl); ty=t; o=so[ty]; c=sc[ty]; if(o==""){o="[";c="]"}
    print "    " id o "\"" esc(lbl) "\"" c ":::" ty; ids[++ni]=id; next }
  $1=="E"{ f=$2; r=$3; t=$4; g=""; if(match($0,/\|[[:space:]]*when=/)){ g=substr($0,RSTART+RLENGTH); sub(/[[:space:]]*$/,"",g); gsub(/["\[\]]/,"",g) }
    lab=r; if(g!="") lab=g "のとき"; arrow="-->|\"" lab "\"|"; if(r=="marks") arrow="-.->|?|"; if(r=="feeds") arrow="-.->|feeds|"
    print "    " f " " arrow " " t; next }
  END{ for(i=1;i<=ni;i++) print "    click " ids[i] " esNode" }
  ' "$1"
}

# ノードデータ(構造化 in/out + 仕様 spec) を JS オブジェクトリテラルで出力
nodes_json(){
  SPEC="$2"; [ -f "$SPEC" ] || SPEC=""
  awk -v SPEC="$SPEC" '
  function jesc(s){ gsub(/\\/,"",s); gsub(/"/,"\\\"",s); return s }
  BEGIN{ if(SPEC!=""){ while((getline ln < SPEC)>0){
      if(ln ~ /^[[:space:]]*#/ || ln ~ /^[[:space:]]*$/) continue
      s=ln; sub(/^[[:space:]]+/,"",s); sid=s; sub(/[[:space:]].*$/,"",sid)
      r=s; sub(/^[^[:space:]]+[[:space:]]+/,"",r); kind=r; sub(/[[:space:]].*$/,"",kind)
      txt=r; sub(/^[^[:space:]]+[[:space:]]+/,"",txt)
      if(kind=="in"){ specIn[sid,++cIn[sid]]=txt } else if(kind=="out"){ specOut[sid,++cOut[sid]]=txt } else if(kind=="step"){ specStep[sid,++cStep[sid]]=txt }
    } close(SPEC) } }
  /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
  $1=="N"{ id=$2; t=$3; line=$0; sub(/^N[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+/,"",line)
    lbl=line; sub(/[[:space:]]*\|.*$/,"",lbl); inv="";ev="";fl="";st="";tr="";bi="";bo="";de="";bh="";nt="";rl="";di="";bz="";ms="";cp="";cu="";bm=""; rest=line
    while(match(rest,/\|[[:space:]]*[a-zA-Z]+=/)){ seg=substr(rest,RSTART); rest=substr(rest,RSTART+RLENGTH)
      key=seg; sub(/^\|[[:space:]]*/,"",key); sub(/=.*$/,"",key); val=rest
      if(match(val,/\|[[:space:]]*[a-zA-Z]+=/)) val=substr(val,1,RSTART-1); gsub(/^[[:space:]]+|[[:space:]]+$/,"",val)
      if(key=="invariant") inv=val; else if(key=="evidence") ev=val; else if(key=="fields") fl=val; else if(key=="states") st=val; else if(key=="transitions") tr=val; else if(key=="in") bi=val; else if(key=="out") bo=val; else if(key=="decide") de=val; else if(key=="behaviors") bh=val; else if(key=="note") nt=val; else if(key=="role") rl=val; else if(key=="discuss") di=val; else if(key=="biz") bz=val; else if(key=="measure") ms=val; else if(key=="capture") cp=val; else if(key=="compute") cu=val; else if(key=="becomes") bm=val }
    type[id]=t; label[id]=lbl; invv[id]=inv; evv[id]=ev; fldA[id]=fl; stsA[id]=st; trnA[id]=tr; binA[id]=bi; boutA[id]=bo; decA[id]=de; bhvA[id]=bh; ntA[id]=nt; rlA[id]=rl; diA[id]=di; bizA[id]=bz; msA[id]=ms; cpA[id]=cp; cuA[id]=cu; bmA[id]=bm; order[++n]=id; next }
  $1=="E"{ ef[++m]=$2; er[m]=$3; et[m]=$4; ew[m]=""; if(match($0,/\|[[:space:]]*when=/)){ g=substr($0,RSTART+RLENGTH); sub(/[[:space:]]*$/,"",g); ew[m]=g } next }
  END{ print "{"
    for(i=1;i<=n;i++){ id=order[i]
      printf "  \"%s\":{\"type\":\"%s\",\"label\":\"%s\",\"invariant\":\"%s\",\"evidence\":\"%s\",\"fields\":\"%s\",\"states\":\"%s\",\"transitions\":\"%s\",\"bin\":\"%s\",\"bout\":\"%s\",\"decide\":\"%s\",\"behaviors\":\"%s\",\"note\":\"%s\",\"role\":\"%s\",\"discuss\":\"%s\",\"biz\":\"%s\",\"measure\":\"%s\",\"capture\":\"%s\",\"compute\":\"%s\",\"becomes\":\"%s\",\"out\":[", id, type[id], jesc(label[id]), jesc(invv[id]), jesc(evv[id]), jesc(fldA[id]), jesc(stsA[id]), jesc(trnA[id]), jesc(binA[id]), jesc(boutA[id]), jesc(decA[id]), jesc(bhvA[id]), jesc(ntA[id]), jesc(rlA[id]), jesc(diA[id]), jesc(bizA[id]), jesc(msA[id]), jesc(cpA[id]), jesc(cuA[id]), jesc(bmA[id])
      f=1; for(j=1;j<=m;j++){ if(ef[j]==id){ printf "%s{\"rel\":\"%s\",\"to\":\"%s\",\"when\":\"%s\"}",(f?"":","),er[j],et[j],jesc(ew[j]); f=0 } }
      printf "],\"in\":["
      f=1; for(j=1;j<=m;j++){ if(et[j]==id){ printf "%s{\"rel\":\"%s\",\"from\":\"%s\",\"when\":\"%s\"}",(f?"":","),er[j],ef[j],jesc(ew[j]); f=0 } }
      printf "],\"spec\":{\"in\":["
      for(k=1;k<=cIn[id];k++) printf "%s\"%s\"",(k>1?",":""),jesc(specIn[id,k])
      printf "],\"steps\":["
      for(k=1;k<=cStep[id];k++){ ss=specStep[id,k]; lab=ss; rule=""; p=index(ss,"|"); if(p>0){ lab=substr(ss,1,p-1); rule=substr(ss,p+1) } gsub(/^[[:space:]]+|[[:space:]]+$/,"",lab); gsub(/^[[:space:]]+|[[:space:]]+$/,"",rule); printf "%s{\"label\":\"%s\",\"rule\":\"%s\"}",(k>1?",":""),jesc(lab),jesc(rule) }
      printf "],\"out\":["
      for(k=1;k<=cOut[id];k++) printf "%s\"%s\"",(k>1?",":""),jesc(specOut[id,k])
      print "]}}" (i<n?",":"")
    }
    print "}" }
  ' "$1"
}

# コンテキストマップ(.cmap: BC/EXT/REL) → Mermaid
cmap_mermaid(){
  awk '
  function esc(s){ gsub(/"/,"",s); return s }
  BEGIN{ print "flowchart LR"
    print "    classDef bc fill:#D0EBFF,stroke:#1971C2,color:#0d47a1"
    print "    classDef ext fill:#F1F3F5,stroke:#868E96,color:#343a40,stroke-dasharray:4 3" }
  /^[[:space:]]*#/||/^[[:space:]]*$/{next}
  $1=="BC"{ id=$2; l=$0; sub(/^BC[[:space:]]+[^[:space:]]+[[:space:]]+/,"",l); sub(/[[:space:]]*\|.*$/,"",l); print "    " id "[\"" esc(l) "\"]:::bc"; ids[++ni]=id; next }
  $1=="EXT"{ id=$2; l=$0; sub(/^EXT[[:space:]]+[^[:space:]]+[[:space:]]+/,"",l); sub(/[[:space:]]*\|.*$/,"",l); print "    " id ">\"" esc(l) "\"]:::ext"; ids[++ni]=id; next }
  $1=="REL"{ f=$2; r=$3; t=$4; sub(/\|.*$/,"",t); sub(/\|.*$/,"",f); k=""; if(match($0,/\|[[:space:]]*key=/)){ k=substr($0,RSTART+RLENGTH); sub(/[[:space:]]*\|.*$/,"",k); sub(/[[:space:]]*$/,"",k); gsub(/["\[\]]/,"",k) } lab=r; if(k!="") lab=r " 〔" k "〕"; print "    " f " -->|\"" esc(lab) "\"| " t; next }
  END{ for(i=1;i<=ni;i++) print "    click " ids[i] " esNode" }
  ' "$1"
}
cmap_nodes(){
  awk '
  function jesc(s){ gsub(/\\/,"",s); gsub(/"/,"\\\"",s); return s }
  function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/,"",s); return s }
  function kv(line,  r,seg,key,v){ r=line; delete KV; while(match(r,/\|[[:space:]]*[a-zA-Z]+=/)){ seg=substr(r,RSTART); r=substr(r,RSTART+RLENGTH); key=seg; sub(/^\|[[:space:]]*/,"",key); sub(/=.*$/,"",key); v=r; if(match(v,/\|[[:space:]]*[a-zA-Z]+=/)) v=substr(v,1,RSTART-1); KV[key]=trim(v) } }
  /^[[:space:]]*#/||/^[[:space:]]*$/{next}
  $1=="BC"||$1=="EXT"{ id=$2; ty=($1=="BC")?"bc":"ext"; l=$0; sub(/^(BC|EXT)[[:space:]]+[^[:space:]]+[[:space:]]+/,"",l); lbl=l; sub(/[[:space:]]*\|.*$/,"",lbl); kv(l); type[id]=ty; label[id]=trim(lbl); summ[id]=KV["summary"]; repo[id]=KV["repos"]; disc[id]=KV["discuss"]; agg[id]=KV["aggregates"]; knd[id]=KV["kind"]; order[++n]=id; next }
  $1=="REL"{ ff=$2; sub(/\|.*$/,"",ff); tt=$4; sub(/\|.*$/,"",tt); ef[++m]=ff; er[m]=$3; et[m]=tt; kv($0); ek[m]=KV["key"]; ez[m]=KV["reason"]; next }
  END{ print "{"
    for(i=1;i<=n;i++){ id=order[i]
      printf "  \"%s\":{\"type\":\"%s\",\"label\":\"%s\",\"summary\":\"%s\",\"repos\":\"%s\",\"discuss\":\"%s\",\"aggregates\":\"%s\",\"kind\":\"%s\",\"out\":[", id, type[id], jesc(label[id]), jesc(summ[id]), jesc(repo[id]), jesc(disc[id]), jesc(agg[id]), jesc(knd[id])
      f=1; for(j=1;j<=m;j++){ if(ef[j]==id){ printf "%s{\"rel\":\"%s\",\"to\":\"%s\",\"key\":\"%s\",\"reason\":\"%s\"}",(f?"":","),er[j],et[j],jesc(ek[j]),jesc(ez[j]); f=0 } }
      printf "],\"in\":["
      f=1; for(j=1;j<=m;j++){ if(et[j]==id){ printf "%s{\"rel\":\"%s\",\"from\":\"%s\",\"key\":\"%s\",\"reason\":\"%s\"}",(f?"":","),er[j],ef[j],jesc(ek[j]),jesc(ez[j]); f=0 } }
      print "]}" (i<n?",":"")
    } print "}" }
  ' "$1"
}

# 因果ループ図(.cld: V 変数 / L 符号付き因果 / LOOP 強化R・バランスB) → Mermaid
# ＋=同方向(実線), －=逆方向(破線)。ループはJS凡例(cld_loops)で説明する。
cld_mermaid(){
  awk '
  function esc(s){ gsub(/"/,"",s); return s }
  BEGIN{ print "flowchart LR"
    print "    classDef v fill:#E7F5FF,stroke:#1971C2,color:#0d3b66" }
  /^[[:space:]]*#/||/^[[:space:]]*$/{next}
  $1=="V"{ id=$2; l=$0; sub(/^V[[:space:]]+[^[:space:]]+[[:space:]]+/,"",l); sub(/[[:space:]]*\|.*$/,"",l); print "    " id "((\"" esc(l) "\")):::v"; next }
  $1=="L"{ from=$2; to=$3; pol=$4
    if(pol=="-") print "    " from " -.->|\"－\"| " to; else print "    " from " -->|\"＋\"| " to; next }
  ' "$1"
}
# .cld の LOOP 行 → JS配列（凡例用）
cld_loops(){
  awk '
  function jesc(s){ gsub(/\\/,"",s); gsub(/"/,"\\\"",s); return s }
  BEGIN{ printf "[" }
  /^[[:space:]]*#/||/^[[:space:]]*$/{next}
  $1=="LOOP"{ id=$2; kind=$3; vars=$4; d=$0; sub(/^LOOP[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+/,"",d)
    printf "%s{\"id\":\"%s\",\"kind\":\"%s\",\"vars\":\"%s\",\"desc\":\"%s\"}", (c++?",":""), id, kind, jesc(vars), jesc(d) }
  END{ printf "]" }
  ' "$1"
}

# markdown(分析ドキュメント) → HTML 決定論変換（POSIX awk）。対応: # ## ###, 表, - 箇条書き, 1. 番号, ```code, **太字**, `code`, [t](u), 段落(ハードラップ吸収)
md_to_html(){
  awk '
  function esc(s){ gsub(/&/,"\\&amp;",s); gsub(/</,"\\&lt;",s); gsub(/>/,"\\&gt;",s); return s }
  function inline(s,  out,pre,mid,seg,t){
    s=esc(s)
    out=""; while(match(s,/\*\*[^*]+\*\*/)){ pre=substr(s,1,RSTART-1); mid=substr(s,RSTART+2,RLENGTH-4); out=out pre "<b>" mid "</b>"; s=substr(s,RSTART+RLENGTH) } s=out s
    out=""; while(match(s,/`[^`]+`/)){ pre=substr(s,1,RSTART-1); mid=substr(s,RSTART+1,RLENGTH-2); out=out pre "<code>" mid "</code>"; s=substr(s,RSTART+RLENGTH) } s=out s
    out=""; while(match(s,/\[[^]]+\]\([^)]+\)/)){ pre=substr(s,1,RSTART-1); seg=substr(s,RSTART,RLENGTH); t=seg; sub(/\]\(.*/,"",t); sub(/^\[/,"",t); out=out pre "<u>" t "</u>"; s=substr(s,RSTART+RLENGTH) } s=out s
    return s
  }
  function emit(){ if(cur==""){return} if(curtype=="li"){ print "<li>" inline(cur) "</li>" } else { print "<p>" inline(cur) "</p>" } cur=""; curtype="" }
  function closelist(){ emit(); if(inul){ print "</ul>"; inul=0 } if(inol){ print "</ol>"; inol=0 } }
  function closetab(){ if(intab){ if(thead){ print "</thead><tbody>" } print "</tbody></table>"; intab=0; thead=0 } }
  BEGIN{ infence=0; intab=0; inul=0; inol=0; cur=""; curtype="" }
  {
    line=$0
    if(line ~ /^```/){ closelist(); closetab(); if(infence){ print "</pre>"; infence=0 } else { print "<pre class=\"code\">"; infence=1 } next }
    if(infence){ print esc(line); next }
    if(line ~ /^[[:space:]]*$/){ closelist(); closetab(); next }
    if(line ~ /^#{1,6} /){ closelist(); closetab(); n=0; while(substr(line,n+1,1)=="#"){n++} t=substr(line,n+2); h=(n>3?3:n); printf "<h%d>%s</h%d>\n", h, inline(t), h; next }
    if(line ~ /^\|/){
      closelist()
      if(line ~ /-/ && line ~ /^\|[[:space:]:|-]+$/){ if(intab && thead){ print "</thead><tbody>"; thead=0 } next }
      if(!intab){ print "<table>"; print "<thead>"; intab=1; thead=1 }
      nf=split(line, cells, "|"); tag=(thead?"th":"td"); printf "<tr>"
      for(i=2;i<nf;i++){ c=cells[i]; gsub(/^[[:space:]]+|[[:space:]]+$/,"",c); printf "<%s>%s</%s>", tag, inline(c), tag }
      print "</tr>"; next
    }
    closetab()
    if(line ~ /^- /){ emit(); if(inol){print "</ol>";inol=0} if(!inul){ print "<ul>"; inul=1 } cur=substr(line,3); curtype="li"; next }
    if(line ~ /^[0-9]+\. /){ emit(); if(inul){print "</ul>";inul=0} if(!inol){ print "<ol>"; inol=1 } sub(/^[0-9]+\. /,"",line); cur=line; curtype="li"; next }
    g=line; sub(/^[[:space:]]+/,"",g)
    if(cur!=""){ cur=cur " " g } else { cur=g; curtype="p" }
  }
  END{ closelist(); closetab(); if(infence) print "</pre>" }
  ' "$1"
}

# ---- HTML 組み立て ----
cat <<'HEAD'
<!DOCTYPE html><html lang="ja"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Event Storming — domain view</title>
<style>
  :root{--actor:#FFE8CC;--command:#4DABF7;--aggregate:#FFE066;--event:#FFA94D;--errorevent:#FFA8A8;--policy:#DA77F2;--readmodel:#B2F2BB;--external:#FFD8A8;--hotspot:#FF6B6B;--bc:#D0EBFF;--ext:#F1F3F5}
  *{box-sizing:border-box} body{margin:0;font-family:system-ui,"Hiragino Sans",sans-serif;color:#212529}
  header{padding:10px 16px;background:#1864ab;color:#fff} header b{font-size:15px}
  #wrap{display:flex;height:calc(100vh - 44px)}
  #left{flex:1;display:flex;flex-direction:column;padding:8px;min-width:0}
  #side{width:400px;flex:0 0 auto;min-width:240px;max-width:80vw;overflow:auto;padding:14px;background:#f8f9fa}
  #divider{flex:0 0 7px;cursor:col-resize;background:#dee2e6;border-left:1px solid #ced4da} #divider:hover{background:#adb5bd}
  #search{width:100%;padding:7px;margin-bottom:8px;border:1px solid #ced4da;border-radius:6px}
  .legend{display:flex;flex-wrap:wrap;gap:6px;margin-bottom:8px;font-size:11px}
  .legend span{padding:2px 7px;border-radius:10px;border:1px solid #00000022}
  #toolbar{display:flex;gap:6px;margin-bottom:6px;align-items:center;flex-wrap:wrap}
  #toolbar button{padding:4px 10px;border:1px solid #ced4da;background:#fff;border-radius:6px;cursor:pointer;font-size:13px}
  #toolbar button:hover{background:#e7f5ff}
  #toolbar button.tab.on, #toolbar button.tab.on:hover{background:#1864ab;color:#fff;border-color:#1864ab}
  g.node.es-hl > rect, g.node.es-hl > polygon, g.node.es-hl > path, g.node.es-hl > circle{stroke:#e8590c !important;stroke-width:6px !important}
  svg.has-hl g.node:not(.es-hl){opacity:.3;transition:opacity .2s} svg.has-hl .edgePath,svg.has-hl .edgeLabel{opacity:.35}
  @keyframes espulse{0%,100%{filter:drop-shadow(0 0 6px rgba(232,89,12,.7))}50%{filter:drop-shadow(0 0 18px rgba(232,89,12,1))}}
  g.node.es-hl{animation:espulse 1s ease-in-out 3}
  .tlink{cursor:pointer;border-bottom:1px dotted #1864ab;color:#1864ab}
  .lk{cursor:pointer;text-decoration:underline dotted 1px;text-underline-offset:2px}
  .loc{font-size:11px;color:#e8590c;font-weight:normal;margin-left:8px}
  #side h2 .loc{font-size:11px;color:#868e96;font-weight:normal;margin-left:6px}
  .sep{width:1px;align-self:stretch;background:#dee2e6;margin:0 4px}
  .view{display:flex;flex:1;min-height:0;flex-direction:column} .view.hidden{display:none}
  .report{flex:1;overflow:auto;padding:14px 22px;line-height:1.7} .report h2{margin:.2em 0;font-size:18px} .report h3{margin:1.1em 0 .3em;font-size:15px} .bizrow{margin:6px 0} .bizcard{border:1px solid #dee2e6;border-radius:7px;padding:10px 12px;margin:9px 0;background:#fff}
  .obs{border-collapse:collapse;width:100%;font-size:12px;margin:8px 0} .obs th,.obs td{border:1px solid #dee2e6;padding:5px 7px;text-align:left;vertical-align:top} .obs th{background:#f1f3f5;white-space:nowrap} .cldwrap{border:1px solid #dee2e6;border-radius:7px;padding:6px;margin:6px 0;background:#fff;overflow:auto}
  /* 辞書カード（動詞の受理パネル＋状態の双対カード） */
  .cardgrid{display:grid;grid-template-columns:repeat(auto-fill,minmax(360px,1fr));gap:12px;margin:10px 0 18px}
  .dictcard{border:1px solid #dee2e6;border-radius:9px;padding:10px 13px;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.06)}
  .verbcard{border-top:4px solid var(--command)} .statecard{border-top:4px solid var(--aggregate)}
  .dch{font-weight:700;font-size:15px;margin-bottom:4px} .dctype{float:right;font-size:11px;font-weight:600;padding:1px 8px;border-radius:9px}
  .sig{font-family:ui-monospace,Menlo,monospace;font-size:12.5px;background:#f8f9fa;border:1px solid #e9ecef;border-radius:6px;padding:5px 8px;margin:5px 0}
  .acc{border-collapse:collapse;width:100%;font-size:12px;margin:7px 0} .acc td{border:1px solid #e9ecef;padding:4px 8px}
  .acc td:first-child{white-space:nowrap;font-weight:600} .accok{background:#ebfbee} .accng{background:#fff5f5;color:#666}
  .meaning{background:#fff9db;border-left:3px solid #fab005;padding:4px 9px;margin:5px 0;font-size:12.5px;border-radius:0 5px 5px 0}
  .report table{border-collapse:collapse;margin:8px 0;font-size:13px;width:100%} .report th,.report td{border:1px solid #dee2e6;padding:5px 8px;text-align:left;vertical-align:top} .report th{background:#f1f3f5} .report ul,.report ol{margin:6px 0;padding-left:1.5em} .report code{background:#f1f3f5;padding:1px 4px;border-radius:3px;font-size:12px} .report pre.code{background:#f8f9fa;border:1px solid #e9ecef;padding:8px;overflow:auto;font-size:12px;line-height:1.4} .report hr{border:0;border-top:2px dashed #ced4da;margin:24px 0}
  /* 分析レポート: 各docを中央寄せの紙カードにし、行長を制限して読みやすく */
  .report.analysis{background:#eef1f4;padding:26px 18px}
  .analysis .doc{max-width:880px;margin:0 auto 26px;background:#fff;border:1px solid #e3e6ea;border-radius:10px;padding:30px 42px;line-height:1.9;color:#3a4149;box-shadow:0 1px 4px rgba(0,0,0,.07)}
  .analysis .doc h1{font-size:22px;line-height:1.4;margin:0 0 18px;padding-bottom:12px;border-bottom:3px solid #339af0;color:#1864ab}
  .analysis .doc h2{font-size:17px;margin:30px 0 10px;padding:6px 0 6px 12px;border-left:4px solid #4dabf7;background:linear-gradient(90deg,#f1f8ff,transparent);color:#1971c2}
  .analysis .doc h3{font-size:14.5px;margin:20px 0 6px;color:#37404a;font-weight:700}
  .analysis .doc p{margin:11px 0}
  .analysis .doc ul,.analysis .doc ol{margin:10px 0;padding-left:1.5em} .analysis .doc li{margin:5px 0}
  .analysis .doc table{width:100%;border-collapse:collapse;margin:16px 0;font-size:13px;box-shadow:0 1px 2px rgba(0,0,0,.04)}
  .analysis .doc th,.analysis .doc td{border:1px solid #e3e6ea;padding:9px 11px;text-align:left;vertical-align:top}
  .analysis .doc th{background:#e7f5ff;color:#1864ab;font-weight:700;white-space:nowrap}
  .analysis .doc tbody tr:nth-child(even){background:#f8fafb}
  .analysis .doc code{background:#fff0f0;color:#c92a2a;padding:1px 5px;border-radius:3px;font-size:.88em}
  .analysis .doc pre.code{background:#262b33;color:#e9ecef;border:0;padding:14px 16px;border-radius:8px;overflow:auto;line-height:1.55;font-size:12px}
  .analysis .doc strong,.analysis .doc b{color:#15406b}
  .vp{flex:1;position:relative;overflow:hidden;border:1px solid #dee2e6;border-radius:6px;background:#fff;cursor:grab;touch-action:none}
  .stage{position:absolute;top:0;left:0;transform-origin:0 0} .mermaid{font-size:14px}
  #side h2{font-size:16px;margin:.2em 0} #side h3{font-size:12px;color:#868e96;margin:1em 0 .3em;text-transform:uppercase;letter-spacing:.04em}
  .badge{display:inline-block;padding:2px 9px;border-radius:10px;font-size:12px;border:1px solid #00000022}
  .chip{display:inline-block;padding:2px 9px;border-radius:11px;font-size:12px;border:1px solid #00000022;cursor:pointer;margin:1px} .chip:hover{outline:2px solid #1864ab55}
  .v{display:inline-block;font-size:10px;color:#fff;background:#868e96;border-radius:8px;padding:1px 6px;margin:0 5px;vertical-align:middle}
  .rel,.flowrow{margin:4px 0;line-height:2} .flowrow b{color:#868e96;margin-right:4px}
  .frow{margin:4px 0;line-height:2}
  .chg{border:1px solid #74c0fc;border-radius:6px;background:#e7f5ff;padding:6px 10px;margin:8px 0} .chgh{font-weight:600;color:#1971c2;margin-bottom:3px}
  .help-btn{background:#fff3bf;border-color:#ffd43b;font-weight:600}
  #help{position:fixed;inset:0;background:rgba(0,0,0,.45);display:flex;align-items:flex-start;justify-content:center;z-index:1000;padding:30px 16px;overflow:auto} #help.hidden{display:none}
  .help-card{background:#fff;max-width:760px;width:100%;border-radius:12px;padding:24px 32px;box-shadow:0 8px 40px rgba(0,0,0,.3);line-height:1.85} .help-card h2{margin:.1em 0 .3em;color:#1864ab} .help-card h3{margin:1.2em 0 .3em;color:#1971c2;border-left:4px solid #4dabf7;padding-left:10px;font-size:15px} .help-card ul{padding-left:1.4em} .help-card li{margin:5px 0} .help-card p{margin:8px 0}
  .help-x{float:right;background:#f1f3f5;border:1px solid #ced4da;border-radius:6px;padding:4px 10px;cursor:pointer}
  .legend{display:flex;flex-wrap:wrap;gap:6px 12px;margin:10px 0;align-items:center;font-size:13px;line-height:2}
  .lg{display:inline-block;border:1px solid;border-radius:5px;padding:2px 9px;font-size:12px;font-weight:600;color:#000}
  .lg2{display:inline-block;background:#e7f5ff;border:1px solid #74c0fc;border-radius:5px;padding:2px 9px;font-size:12px;font-weight:600;color:#1864ab}
  .opt{font-size:10px;background:#e9ecef;border-radius:8px;padding:0 6px;margin-left:5px;color:#495057}
  .orc{display:inline-block;background:#e7f5ff;border:1px solid #74c0fc;border-radius:9px;padding:1px 9px;margin:1px;font-size:12px}
  .stc{display:inline-block;background:#fff3bf;border:1px solid #ffd43b;border-radius:9px;padding:1px 9px;margin:1px;font-size:12px}
  .inc{display:inline-block;background:#f1f3f5;border:1px solid #ced4da;border-radius:9px;padding:1px 9px;margin:1px;font-size:12px}
  .smell{color:#e03131;font-size:11px;font-weight:bold}
  .arrow{color:#868e96;margin:0 4px}
  #side code{display:block;background:#fff;border:1px solid #dee2e6;padding:6px;border-radius:5px;font-size:12px;word-break:break-all}
  .hit{cursor:pointer;padding:4px 6px;border-radius:5px} .hit:hover{background:#e7f5ff} .muted{color:#868e96;font-size:12px}
</style></head><body>
<header><b>イベントストーミング — ドメインビュー</b> &nbsp;<span style="font-size:12px;opacity:.85">ノードをクリックで詳細（コマンド=入力/処理/出力 ・ 集約=構成）。AS-IS=コードの流れ / TO-BE=隠れた集約を表出</span></header>
<div id="wrap"><div id="left">
  <input id="search" placeholder="ノードを検索（名前・型）…" oninput="filter(this.value)">
  <div class="legend"><span style="background:var(--actor)">アクター</span><span style="background:var(--command)">コマンド</span><span style="background:var(--aggregate)">集約</span><span style="background:var(--event)">イベント</span><span style="background:var(--errorevent)">エラー</span><span style="background:var(--policy);color:#fff">ポリシー</span><span style="background:var(--readmodel)">リードモデル</span><span style="background:var(--external)">外部</span><span style="background:var(--hotspot);color:#fff">ホットスポット</span></div>
  <div id="toolbar">
HEAD

# タブ（TO-BE / コンテキストマップ / 分析 がある時のみ）
if [ -n "$TOBE" ] || [ -n "$CMAP" ] || [ -n "$ANALYSIS" ]; then
  printf '    <button id="tab_asis" class="tab on" onclick="setView(\x27asis\x27)">AS-IS（現状＝コードの流れ）</button>'
  [ -n "$TOBE" ] && printf '<button id="tab_tobe" class="tab" onclick="setView(\x27tobe\x27)">TO-BE（あるべき）</button>'
  [ -n "$CMAP" ] && printf '<button id="tab_cmap" class="tab" onclick="setView(\x27cmap\x27)">コンテキストマップ</button>'
  printf '<button id="tab_glossary" class="tab" onclick="setView(\x27glossary\x27)">用語集</button>'
  [ -n "$TOBE" ] && printf '<button id="tab_biz" class="tab" onclick="setView(\x27biz\x27)">ビジネス分析</button>'
  [ -n "$ANALYSIS" ] && printf '<button id="tab_analysis" class="tab" onclick="setView(\x27analysis\x27)">分析レポート</button>'
  printf '<span class="sep"></span>\n'
fi
printf '    <button class="help-btn" onclick="toggleHelp(1)">❓ このページの見方</button><button onclick="esZoom(1.2)">＋ 拡大</button><button onclick="esZoom(1/1.2)">－ 縮小</button><button onclick="esFit()">全体表示</button><span class="muted">Ctrl+ホイール / ピンチ=拡大縮小 ・ ホイール / スワイプ / ドラッグ=移動</span>\n'
printf '  </div>\n'

# このページの見方（ヘルプ・オーバーレイ）
cat <<'HELP'
  <div id="help" class="hidden" onclick="if(event.target===this)toggleHelp(0)">
    <div class="help-card">
      <button class="help-x" onclick="toggleHelp(0)">✕ 閉じる</button>
      <h2>このページの見方</h2>
      <p class="muted">コードから起こした「ドメインモデル（業務の仕組み）」を図で読むページです。上部のタブで、<b>現状(AS-IS)</b>・
      <b>あるべき姿(TO-BE)</b>・<b>境界(コンテキストマップ)</b>・<b>用語集</b>・<b>ビジネス分析</b>・<b>分析レポート</b>を切り替えます。
      図のカードを<b>クリック</b>すると右側に詳細が出ます。</p>

      <h3>1. イベントストーミングとは（AS-IS / TO-BE タブ）</h3>
      <p>業務を「<b>誰が</b>→<b>何を要求し</b>→<b>何の一貫性が保たれ</b>→<b>何が起きたか</b>」という出来事の流れで表す手法です。
      左から右へ時系列で読みます。色と形で種類が分かります：</p>
      <div class="legend">
        <span class="lg" style="background:#FFE8CC;border-color:#D9480F">アクター</span>＝業務の起点（誰が要求するか）
        <span class="lg" style="background:#4DABF7;border-color:#1971C2">コマンド</span>＝「〜せよ」という要求・意図
        <span class="lg" style="background:#FFE066;border-color:#F08C00">集約</span>＝一貫性を守る境界（状態と不変条件を持つ実体）
        <span class="lg" style="background:#FFA94D;border-color:#E8590C">イベント</span>＝起きた事実（過去形）
        <span class="lg" style="background:#DA77F2;border-color:#9C36B5;color:#fff">ポリシー</span>＝「〜なら〜する」条件判定
        <span class="lg" style="background:#B2F2BB;border-color:#2F9E44">リードモデル</span>＝参照用ビュー
        <span class="lg" style="background:#FFD8A8;border-color:#D9480F">外部システム</span>＝外部の権威
        <span class="lg" style="background:#FF6B6B;border-color:#C92A2A;color:#fff">ホットスポット</span>＝要オーナー判断の論点
      </div>
      <p class="muted">流れ: <b>アクター →（コマンド）→ 集約 →（イベント）→ …</b>。ポリシーからコマンドへ伸びる矢印のラベルは「どの条件のときに繋がるか」。
      <b>AS-IS</b>＝実コードの流れ（カードに実装評価あり）／<b>TO-BE</b>＝あるべき設計。AS-ISのカードには「🔄 TO-BEでの変化」が出ます。</p>

      <h3>2. コンテキストマップとは（コンテキストマップ タブ）</h3>
      <p>システムを、<b>独立した言葉とモデルを持つ領域＝境界づけられたコンテキスト(BC)</b>に分け、その<b>関係</b>を描いた地図です。
      四角=自社BC、角丸/灰=外部システム。矢印のラベルが関係の種類です：</p>
      <div class="legend">
        <span class="lg2">CS（顧客-供給）</span>＝下流が上流に依存（供給を受ける）
        <span class="lg2">Conformist（順応）</span>＝上流の型にそのまま従う
        <span class="lg2">ACL（腐敗防止層）</span>＝外部の型を自分の型へ変換して隔離
        <span class="lg2">SharedKernel</span>＝モデルを共有
        <span class="lg2">PL（公表言語）</span>＝公開フォーマットで連携
      </div>
      <p class="muted">矢印の「連結キー」は2つのBCを突き合わせる識別子。BCをクリックすると、その中の<b>コマンド→集約→イベントの流れ</b>と上流/下流関係が見えます。</p>

      <h3>3. 各タブ</h3>
      <ul>
        <li><b>AS-IS / TO-BE</b>: 現状のコードの流れ／あるべき設計（クリックで役割・不変条件・根拠・変化）</li>
        <li><b>コンテキストマップ</b>: BCの境界と関係（上記2）</li>
        <li><b>用語集</b>: モデルから自動射影したユビキタス言語（種別別の用語と定義）</li>
        <li><b>ビジネス分析</b>: イベントの収益/価値/UX分類・計測設計・因果ループ（強化R/バランスB）・施策</li>
        <li><b>分析レポート</b>: リファクタリング計画・永続化設計などの設計文書</li>
      </ul>

      <h3>4. 操作</h3>
      <p class="muted"><b>Ctrl+ホイール / ピンチ</b>=拡大縮小 ・ <b>ホイール / スワイプ / ドラッグ</b>=移動 ・ <b>クリック</b>=詳細表示 ・ <b>用語の下線</b>=定義元へジャンプ</p>
    </div>
  </div>
HELP

# AS-IS ビュー
printf '  <div class="view" id="view_asis"><div class="vp" id="vp_asis"><div class="stage" id="st_asis"><pre class="mermaid">\n'
mermaid_body "$MODEL"
printf '</pre></div></div></div>\n'

# TO-BE ビュー
if [ -n "$TOBE" ]; then
  printf '  <div class="view" id="view_tobe"><div class="vp" id="vp_tobe"><div class="stage" id="st_tobe"><pre class="mermaid">\n'
  mermaid_body "$TOBE"
  printf '</pre></div></div></div>\n'
fi

# コンテキストマップ ビュー
if [ -n "$CMAP" ]; then
  printf '  <div class="view" id="view_cmap"><div class="vp" id="vp_cmap"><div class="stage" id="st_cmap"><pre class="mermaid">\n'
  cmap_mermaid "$CMAP"
  printf '</pre></div></div></div>\n'
fi

# 用語集 ビュー（.es から JS で射影）
printf '  <div class="view" id="view_glossary"><div class="report" id="glossary_report"></div></div>\n'

# ビジネス分析 ビュー（分類・オブザーバビリティ表はJS、因果ループ図はMermaid静的）
if [ -n "$TOBE" ]; then
  printf '  <div class="view" id="view_biz"><div class="report">\n'
  printf '    <div id="biz_top"></div>\n'
  if [ -n "$CLD" ]; then
    printf '    <h3>システム思考：因果ループ図（＋=同方向 / －=逆方向、強化ループ R とバランスループ B）</h3>\n'
    printf '    <div class="cldwrap"><pre class="mermaid">\n'
    cld_mermaid "$CLD"
    printf '</pre></div>\n'
  fi
  printf '    <div id="biz_loops"></div>\n'
  printf '  </div></div>\n'
fi

# 分析レポート ビュー（リファクタ計画・永続化設計などの .md を決定論HTML射影）
if [ -n "$ANALYSIS" ]; then
  printf '  <div class="view" id="view_analysis"><div class="report analysis">\n'
  for d in $ANALYSIS; do
    printf '<article class="doc">\n'
    md_to_html "$d"
    printf '</article>\n'
  done
  printf '  </div></div>\n'
fi

cat <<'MID'
</div><div id="divider" title="ドラッグで幅を調整"></div><div id="side"><p class="muted">左の図のノードをクリックすると、ここに詳細が表示されます。</p></div></div>
<script>
var MODELS={};
MODELS.asis=
MID
nodes_json "$MODEL" "$ASIS_SPEC"
echo ";"
if [ -n "$TOBE" ]; then echo "MODELS.tobe="; nodes_json "$TOBE" "$TOBE_SPEC"; echo ";"; fi
if [ -n "$CMAP" ]; then echo "MODELS.cmap="; cmap_nodes "$CMAP"; echo ";"; fi
printf 'var CLD_LOOPS='; if [ -n "$CLD" ]; then cld_loops "$CLD"; else printf '[]'; fi; echo ";"

cat <<'TAIL'
var TYPEJA={"actor":"アクター","command":"コマンド","aggregate":"集約","event":"イベント","errorevent":"エラーイベント","policy":"ポリシー","readmodel":"リードモデル","external":"外部システム","hotspot":"ホットスポット(要確認)","bc":"境界づけBC","ext":"外部システム"};
var RELT={CS:"Customer-Supplier(顧客-供給)",Conformist:"順応(Conformist)",ACL:"腐敗防止層(ACL)",SharedKernel:"共有カーネル",PL:"公表言語(Published Language)"};
var KINDJA={core:"コアドメイン（競争力の源泉・最も注力）",supporting:"支援サブドメイン（コアを支える固有業務）",generic:"汎用サブドメイン（既製・共通で代替可）"};
function esModel(){ return MODELS.tobe||MODELS.asis||{}; }
function findByLabel(model,label){ var id; for(id in model){ if(model[id].label===label) return id; } for(id in model){ if(model[id].label.indexOf(label)>=0||label.indexOf(model[id].label)>=0) return id; } return null; }
function gotoEs(id){ setView(document.getElementById("view_tobe")?"tobe":"asis"); esNode(id); }
// 別タブ(AS-IS↔TO-BE)のノードへジャンプ＋強調
window.gotoCross=function(view,id){ if(!document.getElementById("view_"+view)) return; setView(view); var c=CENTERS["vp_"+view]; if(c) c(id); esNode(id); };
// becomes= の解析: "id1,id2 | 説明" → {ids:[...],desc:"..."}
function parseBecomes(v){ if(!v) return null; var i=v.indexOf("|"); var idspart=(i<0?v:v.slice(0,i)).trim(); var desc=(i<0?"":v.slice(i+1)).trim();
  var ids=idspart?idspart.split(",").map(function(s){return s.trim();}).filter(Boolean):[]; return {ids:ids,desc:desc}; }
// AS-IS→TO-BE 変化ブロック（AS-ISカードに表示）/ 逆引き（TO-BEカードに「AS-ISから」）
function changeBlock(id){
  if(ACTIVE==="asis"){ var n=NODES[id]; var b=parseBecomes(n&&n.becomes); if(!b) return "";
    var tb=MODELS.tobe||{}; var chips=b.ids.map(function(t){ return "<span class=\"orc lk\" onclick=\"gotoCross('tobe','"+t+"')\">"+(tb[t]?tb[t].label:t)+"</span>"; }).join(" ");
    return "<div class=\"chg\"><div class=\"chgh\">🔄 TO-BEでの変化</div>"+(chips?"<div class=\"rel\">→ "+chips+"</div>":"")+(b.desc?"<div class=\"muted\">"+linkify(b.desc)+"</div>":"")+"</div>"; }
  if(ACTIVE==="tobe"){ var as=MODELS.asis||{}, froms=[];
    for(var aid in as){ var b2=parseBecomes(as[aid].becomes); if(b2&&b2.ids.indexOf(id)>=0) froms.push(aid); }
    if(!froms.length) return "";
    var chips2=froms.map(function(a){ return "<span class=\"inc lk\" onclick=\"gotoCross('asis','"+a+"')\">"+as[a].label+"</span>"; }).join(" ");
    return "<div class=\"chg\"><div class=\"chgh\">← AS-IS からの由来</div><div class=\"rel\">"+chips2+" がこのTO-BEに変化</div></div>"; }
  return ""; }
// BCが含むES流れ: 所属する集約ごとに コマンド→集約→イベント を描く（同じ集約名のまとまり＝そのBCの中身）
function bcFlows(aggNames){ var em=esModel(), html="";
  aggNames.split(";").forEach(function(nm){ nm=nm.trim(); if(!nm) return; var aid=findByLabel(em,nm);
    if(!aid){ html+="<div class=\"frow\"><b>"+nm+"</b> <span class=\"muted\">（ESモデル未登録：この集約の.esは未作成）</span></div>"; return; }
    var a=em[aid];
    var cmds=(a.in||[]).filter(function(e){return e.rel==="handles";}).map(function(e){return "<span class=\"inc lk\" onclick=\"gotoEs('"+e.from+"')\">"+(em[e.from]?em[e.from].label:e.from)+"</span>";}).join("");
    var evs=(a.out||[]).filter(function(e){return e.rel==="emits";}).map(function(e){return "<span class=\"orc lk\" onclick=\"gotoEs('"+e.to+"')\">"+(em[e.to]?em[e.to].label:e.to)+"</span>";}).join(" ");
    html+="<div class=\"frow\">"+(cmds||"<span class=\"muted\">(コマンド無)</span>")+" <span class=\"arrow\">→</span> <span class=\"stc lk\" onclick=\"gotoEs('"+aid+"')\">"+a.label+"</span> <span class=\"arrow\">→</span> "+(evs||"<span class=\"muted\">(イベント無)</span>")+"</div>"; });
  return html; }
function cmapRel(e,isOut){ var other=isOut?e.to:e.from; var t=RELT[e.rel]||e.rel;
  return "<div class=\"rel\">"+(isOut?("<b>ここ</b> → "+chip(other)):(chip(other)+" → <b>ここ</b>"))+" <span class=\"v\">"+t+"</span>"+(e.key?" <span class=\"orc\">連結:"+e.key+"</span>":"")+(e.reason?"<div class=\"muted\" style=\"margin-left:1em\">"+linkify(e.reason)+"</div>":"")+"</div>"; }
var ACTIVE="asis"; var NODES=MODELS.asis;
var VERB={issues:"発行",handles:"処理",emits:"発生",triggers:"起動",feeds:"供給",marks:"指摘"};
var ROLE={
  actor:"システムにコマンドを発行する人/外部主体。業務の起点。ここから「何をしたいか」が入る。",
  command:"『〜せよ』という意図・要求。集約に渡され状態変更を試みる。命令は成功を保証しない（失敗もイベント）。評価軸: 入力検証はここか集約か／1コマンドは1集約だけを変える。",
  aggregate:"不変条件を守る一貫性の境界。状態と振る舞いを持つ実体で、トランザクションは1集約に閉じる。実装: 不変条件はコンストラクタ/メソッドで強制(AlwaysValid)、状態はフラグでなくOR型で。",
  event:"起きた事実（過去形）。他の文脈へ非同期に伝わり、後続の判断材料になる。伝える情報が薄いと後続が判定できない。",
  errorevent:"失敗の事実。フローの終端、または補償(取消等)の起点になる。",
  policy:"イベントに反応して次のコマンドを起こす業務ルール(when/if→then)。判断に使う言葉は behavior で定義せよ（未定義の述語はNG）。",
  readmodel:"問い合わせ専用のビュー。イベントから投影され、判断の入力に使う。書き込みはしない(CQRSのQ側)。",
  external:"境界の外のシステム。ACL(腐敗防止層)やConformistで接続し、相手のモデルを内部に漏らさない。",
  hotspot:"未決定・要確認の論点。コードだけでは決められず、業務オーナーの判断待ち。",
  bc:"境界づけられたコンテキスト。1つの一貫した用語体系(ユビキタス言語)が通用する範囲。中の集約・ポリシーはこの言語で書かれる。",
  ext:"本群の外のシステム。境界の外なので、ACL(腐敗防止層)やConformistで接続し相手のモデルを内部に持ち込まない。"
};
function fg(t){ return (t==="policy"||t==="hotspot")?"#fff":"#000"; }
function chip(id){ var n=NODES[id]; if(!n) return id; return "<span class=\"chip\" style=\"background:var(--"+n.type+");color:"+fg(n.type)+"\" onclick=\"esNode('"+id+"')\">"+n.label+"</span>"; }
function outOf(id,rel){ var n=NODES[id],a=[]; if(n&&n.out) n.out.forEach(function(e){ if(!rel||e.rel===rel) a.push(e); }); return a; }
function inOf(id,rel){ var n=NODES[id],a=[]; if(n&&n.in) n.in.forEach(function(e){ if(!rel||e.rel===rel) a.push(e); }); return a; }
function section(t,html){ return html?("<h3>"+t+"</h3>"+html):""; }
// 用語インデックス: 状態/項目/述語 が「どのノードで定義されているか」。クロスリンクの土台。
function buildTerms(model){ var T={};
  for(var id in model){ var n=model[id];
    if(n.label && n.label.length>=2 && !T[n.label]) T[n.label]={id:id,kind:(TYPEJA[n.type]||"カード"),of:n.label};
    if(n.states) n.states.split("|").forEach(function(s){ s=s.split("//")[0].trim(); if(s&&!T[s]) T[s]={id:id,kind:"状態",of:n.label}; });
    if(n.fields) n.fields.split(";").forEach(function(f){ f=f.trim(); if(!f)return; var nm=f.replace(/:.*$/,"").replace(/\?$/,"").trim(); if(nm&&!T[nm]) T[nm]={id:id,kind:"項目",of:n.label}; });
    if(n.behaviors) n.behaviors.split(";").forEach(function(b){ var nm=(b.split(":")[0]||"").trim(); if(nm&&!T[nm]) T[nm]={id:id,kind:"述語",of:n.label}; });
    if(n.transitions) n.transitions.split(";").forEach(function(tr){ var nm=(tr.split(":")[0]||"").trim(); if(nm&&!T[nm]) T[nm]={id:id,kind:"遷移",of:n.label}; });
  } return T; }
var TERMS=buildTerms(MODELS.asis);
// 既知の用語を含むチップ: クリックで定義元へジャンプ
function infoChip(word,cls){ var w=(word||"").trim(); var t=TERMS[w];
  if(t) return "<span class=\""+cls+" lk\" title=\""+t.of+" の"+t.kind+"へ\" onclick=\"esNode('"+t.id+"')\">"+w+"</span>";
  return "<span class=\""+cls+"\">"+w+"</span>"; }
// 自由文(decide/定義/不変条件)の中の既知用語をリンク化（長い語優先・プレースホルダで二重置換回避）
function linkify(str){ if(!str) return str||""; var keys=[]; for(var k in TERMS){ if(k.length>=2) keys.push(k); } keys.sort(function(a,b){return b.length-a.length;});
  var subs=[]; for(var i=0;i<keys.length;i++){ var w=keys[i]; if(str.indexOf(w)<0) continue; var t=TERMS[w];
    subs.push("<span class=\"tlink\" title=\""+t.of+" の"+t.kind+"へ\" onclick=\"esNode('"+t.id+"')\">"+w+"</span>");
    str=str.split(w).join(""+(subs.length-1)+""); }
  for(var j=0;j<subs.length;j++) str=str.split(""+j+"").join(subs[j]); return str; }
function whenTag(e){ return e.when?(" <span class=\"orc\">"+e.when+"</span> のとき"):""; }
function relIn(e){ return "<div class=\"rel\">"+chip(e.from)+"<span class=\"v\">"+(VERB[e.rel]||e.rel)+"</span>"+whenTag(e)+" → <b>ここ</b></div>"; }
function relOut(e){ return "<div class=\"rel\"><b>ここ</b> <span class=\"v\">"+(VERB[e.rel]||e.rel)+"</span>"+whenTag(e)+" → "+chip(e.to)+"</div>"; }
function hasSpec(n){ return n.spec && ((n.spec.in&&n.spec.in.length)||(n.spec.steps&&n.spec.steps.length)||(n.spec.out&&n.spec.out.length)); }
function ul(a){ return "<ul>"+a.map(function(x){return "<li>"+x+"</li>";}).join("")+"</ul>"; }
function specHtml(n){ var sp=n.spec,h="";
  if(sp.in&&sp.in.length) h+=section("入力",ul(sp.in));
  if(sp.steps&&sp.steps.length) h+=section("処理（入力→出力に至る手順）", sp.steps.map(function(s,i){ return "<div class=\"flowrow\"><b>"+(i+1)+".</b><b style=\"color:#212529\">"+s.label+"</b>"+(s.rule?" — <span class=\"muted\">"+s.rule+"</span>":"")+"</div>"; }).join(""));
  if(sp.out&&sp.out.length) h+=section("出力",ul(sp.out)); return h; }
// data(AND/OR/?) を視覚化: 縦の構成リスト・?=任意・[a|b|c]=OR分岐チップ・フラグ/コード=臭い警告
function dataFields(str){ if(!str) return "";
  return str.split(";").map(function(it){ it=it.trim(); if(!it) return "";
    var name=it, cons="", ors=null;
    var m=it.match(/^(.+?):\[(.+)\]$/);
    if(m){ name=m[1].trim(); ors=m[2].split("|").map(function(s){return s.trim();}); }
    else { var p=it.indexOf(":"); if(p>=0){ name=it.slice(0,p).trim(); cons=it.slice(p+1).trim(); } }
    var optional=/\?$/.test(name); name=name.replace(/\?$/,"").trim();
    var sm=/(フラグ|flag|ステータス|status|stage|コード|code)/i.test(name) && !ors;
    var h="<div class=\"frow\"><b>"+name+"</b>";
    if(optional) h+="<span class=\"opt\">任意?</span>";
    if(ors) h+=" <span class=\"arrow\">▸</span>"+ors.map(function(o){return "<span class=\"orc\">"+o+"</span>";}).join("");
    if(cons) h+=" <span class=\"muted\">〔"+cons.replace(/_/g," ")+"〕</span>";
    if(sm) h+=" <span class=\"smell\">⚠ OR状態へ</span>";
    return h+"</div>"; }).join(""); }
// 状態は「名 // ドメイン上の意味」を持てる（例: 受信 // チャージ要求を受け取り決済が未着手の初期状態）
function parseStates(str){ if(!str) return []; return str.split("|").map(function(s){ var p=s.split("//");
    var name=p[0].trim(); if(!name) return null; return {name:name, def:(p[1]||"").trim()}; }).filter(Boolean); }
function stateChips(str){ return parseStates(str).map(function(s){
    return "<div class=\"frow\"><span class=\"stc\">"+s.name+"</span>"+(s.def?" <span class=\"muted\">＝"+s.def+"</span>":" <span class=\"muted\">（意味未記述 — states の「// 意味」で定義）</span>")+"</div>"; }).join(""); }
function transRows(str){ if(!str) return ""; return str.split(";").map(function(t){ t=t.trim(); if(!t) return "";
    var dp=t.split("//"); var def=(dp[1]||"").trim(); t=dp[0].trim();
    var m=t.match(/^(.+?):(.+?)->(.+)$/); if(!m) return "<div class=\"frow\">"+t+"</div>";
    var outs=m[3].split("|").map(function(o){return infoChip(o,"orc");}).join(" ");
    return "<div class=\"frow\"><b>"+m[1].trim()+"</b>: <span class=\"stc\">"+m[2].trim()+"</span> <span class=\"arrow\">→</span> "+outs+(def?"<div class=\"muted\" style=\"margin-left:1em\">＝"+def+"</div>":"")+"</div>"; }).join(""); }
function behaviorHtml(n){ var h="";
  if(n.bin) h+=section("入力", n.bin.split(";").map(function(x){return infoChip(x,"inc");}).join(" "));
  if(n.decide) h+=section("判定", "<p>"+linkify(n.decide)+"</p>");
  if(n.bout) h+=section("出力（択一）", n.bout.split("|").map(function(x){return infoChip(x,"orc");}).join(" <span class=\"muted\">または</span> "));
  return h; }
function hasBehavior(n){ return n.bin||n.bout||n.decide; }
// 述語の定義: name: in,in -> out|out // 定義(計算ルール)  ← 「期限内」等の言葉を behavior として定義
function behaviorsHtml(str){ if(!str) return "";
  return str.split(";").map(function(b){ b=b.trim(); if(!b) return "";
    var def=""; var dp=b.indexOf("//"); if(dp>=0){ def=b.slice(dp+2).trim(); b=b.slice(0,dp).trim(); }
    var m=b.match(/^(.+?):(.*?)->(.+)$/); if(!m) return "<div class=\"frow\">"+b+"</div>";
    var ins=m[2].split(",").map(function(x){x=x.trim();return x?infoChip(x,"inc"):"";}).join("");
    var outs=m[3].split("|").map(function(x){return infoChip(x,"orc");}).join(" ");
    var h="<div class=\"frow\"><b>"+m[1].trim()+"</b>: "+ins+" <span class=\"arrow\">→</span> "+outs;
    if(def) h+="<div class=\"muted\" style=\"margin-left:1em\">定義: "+linkify(def)+"</div>"; else h+=" <span class=\"smell\">⚠ 定義(//)なし</span>";
    return h+"</div>"; }).join(""); }

// ===== ビジネス分析: 収益発生/価値提供/UX毀損 の分類 + オブザーバビリティ + システム思考(ファネル/施策) =====
var BIZJA={revenue:"収益発生",value:"価値提供",degrade:"UX毀損"};
var BIZCOLOR={revenue:"#ffd43b",value:"#69db7c",degrade:"#ff8787"};
function bizClasses(n){ return (n.biz||"").split(/[;,]/).map(function(s){return s.trim();}).filter(Boolean); }
function gchip(m,id){ var n=m[id]; if(!n) return id; return "<span class=\"orc lk\" onclick=\"gotoEs('"+id+"')\">"+n.label+"</span>"; }
// 上流イベント: event <-emits- aggregate <-handles- command <-issues- policy <-triggers- event …
function upstreamEvents(m,eid,seen){ var res=[]; seen=seen||{}; var n=m[eid]; if(!n) return res;
  (n.in||[]).forEach(function(e){ if(e.rel!=="emits") return; var agg=m[e.from]; if(!agg) return;
    (agg.in||[]).forEach(function(e2){ if(e2.rel!=="handles") return; var cmd=m[e2.from]; if(!cmd) return;
      (cmd.in||[]).forEach(function(e3){ if(e3.rel!=="issues") return; var pol=m[e3.from]; if(!pol) return;
        (pol.in||[]).forEach(function(e4){ if(e4.rel!=="triggers") return; var ev=e4.from;
          if(!seen[ev]){ seen[ev]=1; res.push(ev); upstreamEvents(m,ev,seen).forEach(function(x){res.push(x);}); } }); }); }); });
  return res; }
// 漏れ: 上流チェーン上の集約が emit する degrade イベント（収益/価値への到達を妨げる分岐）
function leakageFor(m,eid){ var leaks={}, chain=[eid].concat(upstreamEvents(m,eid));
  chain.forEach(function(cid){ var c=m[cid]; if(!c) return;
    (c.in||[]).forEach(function(e){ if(e.rel!=="emits") return; var agg=m[e.from]; if(!agg) return;
      (agg.out||[]).forEach(function(o){ if(o.rel==="emits" && m[o.to] && o.to!==eid && bizClasses(m[o.to]).indexOf("degrade")>=0) leaks[o.to]=1; }); }); });
  return Object.keys(leaks); }
// クラス別の汎用オブザーバビリティ（取得・計算）。イベント固有の capture=/compute= が無いときの既定。
var OBS_GEN={
  revenue:{cap:"確定・売上イベントの発生箇所で、顧客ID・取引を一意に識別する番号(取引ID)・金額・発生時刻をログに出力。要求イベントと同じ取引IDで突き合わせる。",cmp:"件数＝集計期間(例:5分間)あたりのイベント数。額＝金額の合計。成功率＝成功件数÷要求件数。"},
  value:{cap:"価値が届いたイベントの発生箇所でログを出力し、開始イベントと同じ取引IDで結ぶ。開始→到達の所要時間(レイテンシ)を計測する。",cmp:"成功率＝集計期間あたりの 到達件数÷要求件数。所要時間＝(到達時刻−要求時刻)の分布をとり、中央値(p50)と遅い方から1%(p99)を見る。"},
  degrade:{cap:"失敗・取消イベントの発生箇所で、失敗理由コードを付けてログ出力。失敗理由を集計の分類軸にする。",cmp:"発生率＝集計期間あたりの 毀損件数÷要求件数。内訳＝失敗理由ごとの件数。"}};
function obsFor(n){ var cls=bizClasses(n)[0]||"value", g=OBS_GEN[cls]||OBS_GEN.value;
  return {cap:n.capture||g.cap, cmp:n.compute||g.cmp}; }
function buildBizReport(){ var m=MODELS.tobe||MODELS.asis||{}, h="", groups={revenue:[],value:[],degrade:[]};
  for(var id in m){ var n=m[id]; if(n.type!=="event"&&n.type!=="errorevent") continue; bizClasses(n).forEach(function(c){ if(groups[c]) groups[c].push(id); }); }
  h+="<h2>ビジネス分析（収益・価値・UX）</h2><p class=\"muted\">イベントを事業インパクトで分類し、UXの良し悪しを測る計測点（取得方法・計算方法）と、収益/価値を上げる施策レバー（システム思考）を示す。</p>";
  ["revenue","value","degrade"].forEach(function(c){
    h+="<h3 style=\"border-left:6px solid "+BIZCOLOR[c]+";padding-left:8px\">"+BIZJA[c]+"イベント</h3>";
    if(!groups[c].length){ h+="<p class=\"muted\">（該当なし／未分類）</p>"; return; }
    groups[c].forEach(function(id){ var n=m[id]; h+="<div class=\"bizrow\">"+gchip(m,id)+"</div>"; }); });
  // オブザーバビリティ表: 指標 / 取得方法 / 計算方法
  h+="<h3>オブザーバビリティ設計（何を・どう取得・どう計算）</h3>";
  h+="<p class=\"muted\">原則: 価値提供→成功率×所要時間／UX毀損→発生率×理由内訳／収益→件数・額・成功率。各イベントの具体は下表。</p>";
  h+="<p class=\"muted\">用語: <b>所要時間(レイテンシ)</b>=要求から完了までの時間 ／ <b>p50</b>=中央値(半数がこれより速い) ／ <b>p99</b>=遅い方から1%の値(ほぼ最悪) ／ <b>取引ID</b>=1件の処理を一意に識別する番号(要求と完了を突き合わせる鍵) ／ <b>集計期間</b>=指標を集計する時間幅(例:5分間)。</p>";
  h+="<table class=\"obs\"><thead><tr><th>イベント<th>計測指標<th>取得方法<th>計算方法</tr></thead><tbody>";
  var evs=groups.revenue.concat(groups.value,groups.degrade).filter(function(v,i,a){return a.indexOf(v)===i;});
  evs.forEach(function(id){ var n=m[id], o=obsFor(n);
    h+="<tr><td>"+gchip(m,id)+"<td>"+(n.measure||"-")+"<td>"+o.cap+"<td>"+o.cmp+"</tr>"; });
  h+="</tbody></table>";
  var el=document.getElementById("biz_top"); if(el) el.innerHTML=h;
  // ループ凡例 + システム思考(施策)
  var L="";
  if(typeof CLD_LOOPS!=="undefined" && CLD_LOOPS.length){
    L+="<h3>ループの読み方（強化 R / バランス B）</h3>";
    L+="<p class=\"muted\">強化ループ(R)=同方向に増幅し成長や暴走を生む。バランスループ(B)=打ち消し合い安定や抑制を生む。負(－)の数が偶数/0なら強化、奇数ならバランス。</p>";
    CLD_LOOPS.forEach(function(lp){ var R=lp.kind==="R"; var col=R?"#2f9e44":"#e8590c", tag=R?"強化ループ R":"バランスループ B";
      L+="<div class=\"bizcard\"><b style=\"color:"+col+"\">"+lp.id+" "+tag+"</b>: "+lp.desc+"<div class=\"muted\">関与変数: "+lp.vars.split(",").join(" → ")+" → (戻る)</div></div>"; });
  }
  L+="<h3>施策分析（どのイベントを動かすと収益/価値が上がるか）</h3>";
  var seen={}, targets=groups.revenue.concat(groups.value).filter(function(v){ if(seen[v]) return false; seen[v]=1; return true; });
  targets.forEach(function(id){ var n=m[id], ups=upstreamEvents(m,id), leaks=leakageFor(m,id);
    L+="<div class=\"bizcard\"><b>"+gchip(m,id)+"</b>（"+bizClasses(n).map(function(c){return BIZJA[c];}).join("・")+"）を上げるには:";
    L+="<div class=\"rel\">⬆ ファネル上流（増やす→ "+n.label+" 増）: "+(ups.length?ups.map(function(u){return gchip(m,u);}).join(" ← "):"<span class=\"muted\">(なし)</span>")+"</div>";
    L+="<div class=\"rel\">⬇ 漏れ（減らす→ "+n.label+" 増）: "+(leaks.length?leaks.map(function(l){return gchip(m,l);}).join(" "):"<span class=\"muted\">(なし)</span>")+"</div>";
    L+="<div class=\"muted\">施策レバー: 上流イベントの成功率↑／漏れイベントの発生率↓。効果は各イベントの計測(measure=)をSLIにして測る。</div></div>"; });
  var el2=document.getElementById("biz_loops"); if(el2) el2.innerHTML=L; }

// ===== 用語集（ユビキタス言語）: .es から決定論射影。手書きせず、モデル更新で常に最新 =====
var TYPEJA_G={actor:"アクター",command:"コマンド",aggregate:"集約",event:"イベント",errorevent:"イベント(エラー)",policy:"ポリシー",readmodel:"リードモデル",external:"外部システム",hotspot:"ホットスポット(論点)"};
function termDef(n){
  if(n.role) return n.role;
  if(n.invariant) return "不変条件: "+n.invariant;
  if(n.decide) return "判定: "+n.decide;
  if(n.fields) return "構成: "+n.fields;
  if(n.discuss) return "論点: "+n.discuss;
  return "<span class=\"muted\">(定義未記入)</span>";
}
// ===== 辞書カード: 動詞が暗黙に生む状態区別を展開する（transitions= から機械導出）=====
// 「決済する」という語の存在が「決済可能／不可能」の区別を生む。✓（できる）だけでなく
// ✗（できない＝防いでいる事故）まで明示し、前提状態を誰が生むか（能力の供給網）も描く。
function parseTransitions(t){
  if(!t) return [];
  return t.split(";").map(function(s){ s=s.trim(); if(!s) return null;
    var dp=s.split("//"); var def=(dp[1]||"").trim(); s=dp[0].trim();
    var i=s.indexOf(":"); if(i<0) return null;
    var name=s.slice(0,i).trim(); var m=s.slice(i+1).split("->"); if(m.length<2) return null;
    var outs=m[1].split("|").map(function(x){return x.trim();}).filter(Boolean);
    return {name:name, from:m[0].trim(), to:outs[0], alts:outs.slice(1), def:def};
  }).filter(Boolean);
}
function dictCards(m){ var h="";
  for(var id in m){ var n=m[id]; if(n.type!=="aggregate") continue;
    var stobjs=parseStates(n.states); var sdef={}; stobjs.forEach(function(s){ sdef[s.name]=s.def; });
    var sts=stobjs.map(function(s){return s.name;});
    var trs=parseTransitions(n.transitions);
    if(sts.length<2||!trs.length) continue;
    h+="<h3>『"+n.label+"』の動詞と状態 <span class=\"muted\">— 動詞は状態の区別を暗黙に生む。✗＝防いでいる事故</span></h3>";
    h+="<div class=\"cardgrid\">";
    trs.forEach(function(t){
      var stem=t.name.replace(/する$/,"");
      var prod=trs.filter(function(p){return p.to===t.from||p.alts.indexOf(t.from)>=0;});
      h+="<div class=\"dictcard verbcard\"><div class=\"dch\">"+t.name+"<span class=\"dctype\" style=\"background:var(--command)\">動詞</span></div>";
      h+="<div class=\"meaning\">"+(t.def?("<b>ドメイン上の意味</b>＝"+t.def):("<b>ドメイン上の意味</b>＝<span class=\"muted\">未記述（この語は業務で何をすることか。transitions の「// 意味」で定義）</span>"))+"</div>";
      h+="<div class=\"sig\">"+t.name+" : <b>"+t.from+"</b>の"+n.label+" ─→ "+t.to+(t.alts.length?" ｜ "+t.alts.join(" ｜ "):"")+"</div>";
      h+="<div class=\"muted\">⚡ この語が「"+t.from+"である／でない」の区別を生む＝前提を満たした値だけを受け付ける</div>";
      h+="<table class=\"acc\">";
      sts.forEach(function(s){
        if(s===t.from) h+="<tr class=\"accok\"><td>"+s+"</td><td>✓ 受け付ける ─→ "+t.to+"</td></tr>";
        else if(s===t.to) h+="<tr class=\"accng\"><td>"+s+"</td><td>✗ 既に"+t.to+"（二重"+stem+"を防ぐ）</td></tr>";
        else h+="<tr class=\"accng\"><td>"+s+"</td><td>✗ "+t.from+"でない（この変化は仕様が定義しない）</td></tr>";
      });
      h+="</table>";
      h+="<div class=\"rel\">前提「"+t.from+"」を生むのは: "+(prod.length?prod.map(function(p){return "<span class=\"inc\">"+p.name+"</span>";}).join(" "):"<span class=\"muted\">（初期状態＝受理時に生まれる）</span>")+"</div>";
      h+="<div class=\"muted\">実装: if(状態=="+t.from+") の実行時チェックは漏れうる → 引数の型を「"+t.from+"の"+n.label+"」にする（条件を満たさない値はそもそも渡せない）</div>";
      h+="</div>";
    });
    sts.forEach(function(s){
      var can=trs.filter(function(t){return t.from===s;});
      var cant=trs.filter(function(t){return t.from!==s;});
      var born=trs.filter(function(t){return t.to===s||t.alts.indexOf(s)>=0;});
      h+="<div class=\"dictcard statecard\"><div class=\"dch\">"+s+"<span class=\"dctype\" style=\"background:var(--aggregate)\">状態</span></div>";
      h+="<div class=\"meaning\">"+(sdef[s]?("<b>ドメイン上の意味</b>＝"+sdef[s]):("<b>ドメイン上の意味</b>＝<span class=\"muted\">未記述（この状態は業務上どういう局面か。states の「// 意味」で定義）</span>"))+"</div>";
      h+="<div class=\"rel\">できること: "+(can.length?can.map(function(t){return "<span class=\"orc\">✓ "+t.name+" → "+t.to+"</span>";}).join(" "):"<span class=\"muted\">（終端状態＝ここからの変化は無い）</span>")+"</div>";
      h+="<div class=\"rel\">できないこと: "+cant.map(function(t){return "<span class=\"smell\">✗ "+t.name+"</span>";}).join(" ")+"</div>";
      h+="<div class=\"muted\">この状態を生む動詞: "+(born.length?born.map(function(t){return t.name;}).join("・"):"（初期状態）")+"</div>";
      h+="</div>";
    });
    h+="</div>";
  }
  return h;
}
function buildGlossary(){
  var m=MODELS.tobe||MODELS.asis||{}, h="";
  h+="<h2>用語集（ユビキタス言語）</h2><p class=\"muted\">.es から決定論射影（手書きしない＝モデル更新で常に最新）。用語をクリックすると図の定義元へ移動。種別ごとにグルーピング。</p>";
  h+=dictCards(m);
  var order=["aggregate","command","event","errorevent","policy","readmodel","actor","external","hotspot"], groups={};
  for(var id in m){ var n=m[id]; (groups[n.type]=groups[n.type]||[]).push(id); }
  order.forEach(function(t){ var ids=groups[t]; if(!ids||!ids.length) return;
    h+="<h3>"+(TYPEJA_G[t]||t)+"（"+ids.length+"）</h3>";
    h+="<table class=\"obs\"><thead><tr><th>用語<th>定義（役割／不変条件／構成）<th>構造</tr></thead><tbody>";
    ids.forEach(function(id){ var n=m[id], st=[];
      if(n.fields) st.push("項目: "+n.fields);
      if(n.states) st.push("状態: "+n.states);
      if(n.behaviors) st.push("述語: "+n.behaviors);
      h+="<tr><td>"+gchip(m,id)+"<td>"+termDef(n)+"<td class=\"muted\">"+(st.join("<br>")||"-")+"</td></tr>"; });
    h+="</tbody></table>"; });
  var el=document.getElementById("glossary_report"); if(el) el.innerHTML=h;
}

function esNode(id){ var n=NODES[id]; if(!n) return; var h="";
  h+="<h2>"+n.label+"<span class=\"loc\">◀ 図で強調中</span></h2><span class=\"badge\" title=\""+(ROLE[n.type]||"")+"\" style=\"background:var(--"+n.type+");color:"+fg(n.type)+"\">"+(TYPEJA[n.type]||n.type)+"</span>";
  h+=section("このカードの役割", n.role?("<p>"+linkify(n.role)+"</p>"):"<p class=\"muted\">（このカード固有の役割は未記述。.es に role= を追記）</p>");
  h+=changeBlock(id);
  if(n.discuss) h+=section("論点（何を議論・決めるか）", "<div style=\"border-left:3px solid #e8590c;padding:4px 10px;background:#fff4e6\">"+linkify(n.discuss)+"</div>");
  var sp=hasSpec(n); if(sp) h+=specHtml(n);
  if(n.type==="command"){
    if(hasBehavior(n)) h+=behaviorHtml(n);
    if(n.behaviors) h+=section("述語の定義（この判定で使う言葉）", behaviorsHtml(n.behaviors));
    h+=section("トリガー（誰が発行するか）", inOf(id,"issues").map(relIn).join(""));
    if(!sp && !hasBehavior(n)) h+="<p class=\"muted\">⚠ このコマンドの処理仕様は未分析です。in / out / decide（または .spec）を追記すると箱の中身が表示されます。</p>";
    h+=section("後続（コレオグラフィ＝箱の外の繋がり。処理仕様ではない）", outOf(id).map(relOut).join(""));
  } else if(n.type==="aggregate"){
    if(n.states) h+=section("状態（OR）", stateChips(n.states));
    if(n.transitions) h+=section("遷移（behavior）", transRows(n.transitions));
    if(n.fields) h+=section("構成（AND）", dataFields(n.fields));
    h+=section("不変条件 (invariant)", n.invariant?("<p>"+linkify(n.invariant)+"</p>"):(n.fields||n.states?"":"<p class=\"muted\">⚠ 集約だが不変条件なし</p>"));
    h+=section("受けるコマンド", inOf(id,"handles").map(function(e){return chip(e.from);}).join(" "));
    h+=section("発行イベント", outOf(id,"emits").map(function(e){return chip(e.to);}).join(" "));
    h+=section("要確認（hotspot）", inOf(id,"marks").map(function(e){return chip(e.from);}).join(" "));
  } else if(n.type==="event"||n.type==="errorevent"||n.type==="readmodel"){
    if(n.fields) h+=section(n.type==="readmodel"?"このビューが持つ情報":"このイベントが伝える情報", dataFields(n.fields));
    h+=section("生成元", inOf(id,"emits").map(relIn).join(""));
    h+=section("起動／供給先", outOf(id).map(relOut).join(""));
  } else if(n.type==="policy"){
    if(hasBehavior(n)) h+=behaviorHtml(n);
    if(n.behaviors) h+=section("述語の定義（この判定で使う言葉）", behaviorsHtml(n.behaviors));
    h+=section("起動契機（どのイベントで動くか）", inOf(id,"triggers").map(relIn).join(""));
    h+=section("発行コマンド", outOf(id,"issues").map(relOut).join(""));
  } else if(n.type==="bc"||n.type==="ext"){
    if(n.kind) h+=section("ドメイン種別", "<span class=\"badge\" style=\"background:"+(n.kind==="core"?"#ffd43b":n.kind==="supporting"?"#b2f2bb":"#dee2e6")+"\">"+(KINDJA[n.kind]||n.kind)+"</span>");
    if(n.summary) h+=section("責務・概要", "<p>"+linkify(n.summary)+"</p>");
    if(n.aggregates) h+=section("含むES流れ（コマンド → 集約 → イベント）", bcFlows(n.aggregates));
    if(n.repos) h+=section("所属リポ／構成", n.repos.split(";").map(function(x){return "<span class=\"inc\">"+x.trim()+"</span>";}).join(" "));
    h+=section("← 上流（供給を受ける）", (n.in||[]).map(function(e){return cmapRel(e,false);}).join(""));
    h+=section("→ 下流（供給する）", (n.out||[]).map(function(e){return cmapRel(e,true);}).join(""));
  } else { h+=section("← 上流",(n.in||[]).map(relIn).join("")); h+=section("→ 下流",(n.out||[]).map(relOut).join("")); }
  if(n.evidence) h+=section("根拠 (evidence)","<code>"+n.evidence+"</code>");
  if(n.note) h+=section("実装の評価・アドバイス（学習）", "<p>"+linkify(n.note)+"</p>");
  document.getElementById("side").innerHTML=h;
  var lf=CENTERS[activeVp()]; if(lf) lf(id); }
function filter(q){ q=(q||"").toLowerCase(); var box=document.getElementById("side");
  if(!q){ box.innerHTML="<p class=\"muted\">検索結果がここに出ます。</p>"; return; }
  var hits=""; for(var id in NODES){ var n=NODES[id]; if((n.label+" "+(TYPEJA[n.type]||n.type)).toLowerCase().indexOf(q)>=0) hits+="<div class=\"hit\" onclick=\"esNode('"+id+"')\">"+chip(id)+"</div>"; }
  box.innerHTML=hits||"<p class=\"muted\">該当なし</p>"; }

var FITS={},ZOOMS={},CENTERS={};
function initPanZoom(vpId,stId){ var vp=document.getElementById(vpId),stage=document.getElementById(stId); if(!vp||!stage) return; var svg=stage.querySelector("svg"); if(!svg) return;
  var vb=svg.viewBox&&svg.viewBox.baseVal; var sw=(vb&&vb.width)||900, sh=(vb&&vb.height)||600;
  if(vb&&vb.width){ svg.setAttribute("width",sw); svg.setAttribute("height",sh); } svg.style.maxWidth="none"; svg.style.height="auto";
  var scale=1,tx=0,ty=0; function apply(){ stage.style.transform="translate("+tx+"px,"+ty+"px) scale("+scale+")"; }
  function fit(){ var vw=vp.clientWidth,vh=vp.clientHeight; if(!vw||!vh) return; var s=Math.min(vw/sw,vh/sh)*0.95; if(!isFinite(s)||s<=0)s=1; scale=s; tx=(vw-sw*s)/2; ty=(vh-sh*s)/2; apply(); }
  function zoomAt(mx,my,f){ var ns=Math.min(8,Math.max(0.08,scale*f)); tx=mx-(mx-tx)*(ns/scale); ty=my-(my-ty)*(ns/scale); scale=ns; apply(); }
  // Ctrl+ホイール / トラックパッドのピンチ(ブラウザはctrlKey付きwheelで送る) → 拡大縮小（カーソル位置基準）。素のホイール/2本指スワイプ → 移動
  vp.addEventListener("wheel",function(e){ e.preventDefault(); var r=vp.getBoundingClientRect();
    if(e.ctrlKey||e.metaKey){ zoomAt(e.clientX-r.left,e.clientY-r.top,e.deltaY<0?1.12:1/1.12); }
    else { tx-=e.deltaX; ty-=e.deltaY; apply(); } },{passive:false});
  var drag=false,lx,ly; vp.addEventListener("pointerdown",function(e){ if(e.target.closest(".node,.clickable,a")) return; drag=true;lx=e.clientX;ly=e.clientY;vp.setPointerCapture(e.pointerId);vp.style.cursor="grabbing"; });
  vp.addEventListener("pointermove",function(e){ if(!drag)return; tx+=e.clientX-lx; ty+=e.clientY-ly; lx=e.clientX; ly=e.clientY; apply(); });
  vp.addEventListener("pointerup",function(){drag=false;vp.style.cursor="grab";}); vp.addEventListener("pointerleave",function(){drag=false;vp.style.cursor="grab";}); vp.addEventListener("dblclick",fit);
  function locate(nodeId){ var ns=stage.querySelectorAll("g.node"), g=null, i;
    for(i=0;i<ns.length;i++){ var m=(ns[i].id||"").match(/^flowchart-(.+)-\d+$/); if(m && m[1]===nodeId){ g=ns[i]; break; } }
    for(i=0;i<ns.length;i++) ns[i].classList.remove("es-hl");
    var svg=stage.querySelector("svg"); if(svg) svg.classList.toggle("has-hl", !!g);
    if(!g) return; g.classList.remove("es-hl"); void g.offsetWidth; g.classList.add("es-hl");
    var gr=g.getBoundingClientRect(), vr=vp.getBoundingClientRect();
    tx += (vr.left+vp.clientWidth/2)-(gr.left+gr.width/2);
    ty += (vr.top+vp.clientHeight/2)-(gr.top+gr.height/2);
    apply(); }
  FITS[vpId]=fit; ZOOMS[vpId]=function(f){ zoomAt(vp.clientWidth/2,vp.clientHeight/2,f); }; CENTERS[vpId]=locate; }
function activeVp(){ return "vp_"+ACTIVE; }
window.esFit=function(){ var f=FITS[activeVp()]; if(f) f(); };
window.esZoom=function(f){ var z=ZOOMS[activeVp()]; if(z) z(f); };
window.toggleHelp=function(show){ var h=document.getElementById("help"); if(h) h.classList.toggle("hidden", !show); };
document.addEventListener("keydown",function(e){ if(e.key==="Escape") toggleHelp(0); });
window.setView=function(name){ ACTIVE=name; NODES=MODELS[name]||NODES; TERMS=buildTerms(NODES);
  ["asis","tobe","cmap","glossary","biz","analysis"].forEach(function(k){ var v=document.getElementById("view_"+k); if(v) v.classList.toggle("hidden",k!==name); var b=document.getElementById("tab_"+k); if(b) b.className=(k===name?"tab on":"tab"); });
  if(name==="glossary"){ buildGlossary(); return; }
  if(name==="biz"){ buildBizReport(); return; }
  if(name==="analysis"){ return; }
  document.getElementById("side").innerHTML="<p class=\"muted\">"+(name==="tobe"?"TO-BE（隠れた集約を表出）":"AS-IS（コードの流れ）")+" のノードをクリックすると詳細が出ます。</p>";
  var f=FITS[activeVp()]; if(f) f(); };
window.addEventListener("resize",function(){ var f=FITS[activeVp()]; if(f) f(); });
(function initDivider(){ var dv=document.getElementById("divider"),side=document.getElementById("side"); if(!dv||!side) return; var dragging=false;
  dv.addEventListener("pointerdown",function(e){ dragging=true; dv.setPointerCapture(e.pointerId); document.body.style.userSelect="none"; e.preventDefault(); });
  window.addEventListener("pointermove",function(e){ if(!dragging) return; var w=window.innerWidth-e.clientX; w=Math.max(240,Math.min(window.innerWidth*0.8,w)); side.style.width=w+"px"; var f=FITS[activeVp()]; if(f) f(); });
  window.addEventListener("pointerup",function(){ if(dragging){ dragging=false; document.body.style.userSelect=""; } });
})();
</script>
<script type="module">
import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs";
mermaid.initialize({startOnLoad:false,securityLevel:"loose",flowchart:{curve:"basis"}});
await mermaid.run();
initPanZoom("vp_asis","st_asis"); var fa=FITS["vp_asis"]; if(fa) fa();
if(document.getElementById("vp_tobe")){ initPanZoom("vp_tobe","st_tobe"); var ft=FITS["vp_tobe"]; if(ft) ft(); }
if(document.getElementById("vp_cmap")){ initPanZoom("vp_cmap","st_cmap"); var fc=FITS["vp_cmap"]; if(fc) fc(); }
if(document.getElementById("vp_tobe")||document.getElementById("vp_cmap")) setView("asis");
</script>
</body></html>
TAIL
