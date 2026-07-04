#!/bin/sh
# [汎用コア] イベントストーミング図レンダラ（ツール・非ゲート） — スタック非依存
#
# WHY: drawio はAIに不向き——AIはキャンバスを見られないのに座標(x,y)を直接書かされ、図が歪む。本ツールは
# es-lint を通過した型付きモデル(.es)を Mermaid flowchart へ決定論変換する。AIは座標を一切書かない（型だけ
# 書く）。色・形・レイアウトは classDef と Mermaid の自動配置に委ねる＝AIの手描き精度に依存しない。
# 出力は source of truth ではなく .es の射影。GitHub上の ```mermaid ブロックでそのまま描画される。
#
# Usage: sh es-render.sh <model.es>     ( Mermaid を stdout に出力 )
#   推奨: es-lint で文法検証してから渡す ( sh es-lint.sh m.es && sh es-render.sh m.es > m.mmd )
# Consumption model: モデルファイルを引数で受けるだけ。kit でも消費者でもそのまま動く。
set -eu

MODEL="${1:?usage: es-render.sh <model.es>}"
[ -f "$MODEL" ] || { echo "es-render: model not found: $MODEL" >&2; exit 2; }

awk '
function esc(s){ gsub(/"/,"",s); return s }
BEGIN{
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
  so["actor"]="(["; sc["actor"]="])"
  so["command"]="[/"; sc["command"]="/]"
  so["aggregate"]="{{"; sc["aggregate"]="}}"
  so["event"]="["; sc["event"]="]"
  so["errorevent"]="["; sc["errorevent"]="]"
  so["policy"]="[["; sc["policy"]="]]"
  so["readmodel"]="("; sc["readmodel"]=")"
  so["external"]=">"; sc["external"]="]"
  so["hotspot"]="["; sc["hotspot"]="]"
}
/^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
$1=="N"{
  id=$2; t=$3
  line=$0; sub(/^N[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+/,"",line)
  lbl=line; sub(/[[:space:]]*\|.*$/,"",lbl); lbl=esc(lbl)
  type[id]=t; label[id]=lbl; order[++n]=id
  next
}
$1=="E"{ ef[++m]=$2; er[m]=$3; et[m]=$4; next }
END{
  for(i=1;i<=n;i++){ id=order[i]; ty=type[id]; o=so[ty]; c=sc[ty]
    if(o==""){ o="["; c="]" }   # 未知の型は箱でフォールバック（es-lint通過後は全型に shape 在り）
    print "    " id o "\"" label[id] "\"" c ":::" ty }
  for(j=1;j<=m;j++){ f=ef[j]; r=er[j]; t=et[j]
    arrow="-->|" r "|"
    if(r=="marks") arrow="-.->|?|"
    if(r=="feeds") arrow="-.->|feeds|"
    print "    " f " " arrow " " t }
}
' "$MODEL"
