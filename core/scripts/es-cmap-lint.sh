#!/bin/sh
# [汎用コア] コンテキストマップ文法ゲート（prevention） — スタック非依存
# gatecrate-type: prevention
#
# WHY: .cmap(BC/EXT/REL)も座標なしテキストの源泉で、図はその射影。REL先のBCが未定義／関係種別の誤り／
# トークン間のスペース抜け（実害: `bc_x| key=` でMermaidのエッジに余分な | が出て描画崩壊）が起きる。
# これらをプロンプト（注意書き）に置くと再発するので、文法を機械ゲートで強制する（es-lint と同方針）。
#
# 文法: BC <id> <名前> [| summary= | repos= | aggregates= | kind= | discuss=]
#       EXT <id> <名前> [| summary=]
#       REL <from> <CS|Conformist|ACL|SharedKernel|PL> <to> [| key= | reason=]
# 規則:
#   R1 REL の from/to は宣言済みの BC/EXT id（未定義・スペース抜け `id|` を reject）
#   R2 REL の関係種別 ∈ {CS,Conformist,ACL,SharedKernel,PL}
#   R3 BC/EXT 行は id と 名前 を持つ
#   R4(warn) BC に summary 無し / REL に reason 無し / kind が core|supporting|generic 以外
#
# Usage: sh es-cmap-lint.sh <map.cmap>     ( 違反があれば exit 1 )
set -eu
MODEL="${1:?usage: es-cmap-lint.sh <map.cmap>}"
[ -f "$MODEL" ] || { echo "es-cmap-lint: not found: $MODEL" >&2; exit 2; }

awk '
function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/,"",s); return s }
/^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
$1=="BC" || $1=="EXT"{
  id=$2; decl[id]=1
  rest=$0; sub(/^[[:space:]]*(BC|EXT)[[:space:]]+[^[:space:]]+[[:space:]]*/,"",rest)
  nm=rest; sub(/[[:space:]]*\|.*$/,"",nm); nm=trim(nm)
  if(id=="" || nm=="") err[++ne]="R3 名前なし: " $1 " " id " ← <id> <名前> を書く"
  if($1=="BC" && $0 !~ /summary=/) warn[++nw]="R4 summary無し: BC " id
  if($0 ~ /kind=/){ k=$0; sub(/.*kind=[[:space:]]*/,"",k); sub(/[[:space:]]*\|.*$/,"",k); k=trim(k); if(k!="core" && k!="supporting" && k!="generic") warn[++nw]="R4 kind不正: BC " id " の kind=\"" k "\" ← core|supporting|generic" }
  next
}
$1=="REL"{ rels[++r]=$0; next }
END{
  RELOK["CS"]=1; RELOK["Conformist"]=1; RELOK["ACL"]=1; RELOK["SharedKernel"]=1; RELOK["PL"]=1
  for(i=1;i<=r;i++){ nf=split(rels[i], F, /[[:space:]]+/); from=F[2]; rel=F[3]; to=F[4]
    if(!(rel in RELOK)) err[++ne]="R2 関係種別が不正: \"" rel "\" (REL " from " " rel " " to ") ← CS|Conformist|ACL|SharedKernel|PL"
    if(!(from in decl)) err[++ne]="R1 未定義BC参照(from): \"" from "\" ← 宣言された BC/EXT id か確認"
    if(!(to in decl)) err[++ne]="R1 未定義BC参照(to): \"" to "\" ← 宣言された BC/EXT id か確認（| の前のスペース抜けに注意）"
    if(rels[i] !~ /reason=/) warn[++nw]="R4 reason無し: REL " from " " rel " " to
  }
  print "=== es-cmap-lint: " FILENAME " ==="
  if(ne==0) print "  OK: 文法違反なし"
  for(i=1;i<=ne;i++) print "  [ERROR] " err[i]
  for(i=1;i<=nw;i++) print "  [warn]  " warn[i]
  print "---- ERROR=" ne+0 " WARN=" nw+0 " ----"
  exit (ne>0?1:0)
}
' "$MODEL"
