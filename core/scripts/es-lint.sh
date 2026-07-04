#!/bin/sh
# [汎用コア] イベントストーミング文法ゲート — スタック非依存
# gatecrate-type: prevention
#
# WHY: AIエージェントはイベントストーミングが構造的に不得意——「ルール」を「集約」と誤ラベルし
# （例: "ファイル読込検証" を集約に）、イベントをイベントへ直接連結する（event→event）。これは判断層
# （プロンプトの注意書き）に文法を置く限り再発する。実害として観測済み: 手描き図で集約の誤りとイベント
# 連結が同時に混入した。本ゲートはES文法を機械強制し、AIが書いた型付きモデル(.es)の文法違反を出荷前に
# reject する（survivor-strict mutation が仕様網羅を機械保証するのと同じ位置づけ＝予防型ゲート）。
#
# AIの責務は「型付きノードと型付きエッジ」を書くことだけ。「集約か否か」「連結してよいか」の文法判断は
# 人間にもAIにも依存させない——このスクリプトが単一の判定者になる。
#
# 入力 .es 形式（1行1宣言・# はコメント）:
#   N <id> <type> <ラベル> [| invariant=...] [| evidence=path:line]
#   E <from> <relation> <to>
#   type     ∈ actor command aggregate event errorevent policy readmodel external hotspot
#   relation ∈ issues handles emits triggers feeds marks
#
# 許可される文法トリプル（これ以外のエッジは全て reject）＝「前後にどのカードが来てよいか」:
#   actor    issues   command         （アクターの次はコマンド）
#   policy   issues   command         （ポリシーの次はコマンド）
#   command  handles  aggregate|external  （コマンドの次は必ず集約か外部システム）
#   aggregate emits   event|errorevent    （集約の次はイベント）
#   external emits    event|errorevent    （外部システムの次はイベント）
#   event    triggers policy|actor    （イベントの次はポリシーかアクター）
#   event    feeds    readmodel        （イベントはリードモデルにも流れる）
#   （hotspot は marks で任意接続・文法対象外＝未決定論点のマーカー）
# ＝逆に言えば: イベントは必ず集約/外部の後・コマンドは必ずアクター/ポリシーの後・集約は必ずコマンドの後。
#   errorevent は終端（triggers の起点にしない＝補償を駆動するなら event にする）。
#
# Usage: sh es-lint.sh <model.es>   (違反があれば名指しして exit 1)
# Consumption model: モデルファイルを引数で受けるだけ。kit でも消費者でもそのまま動く。
set -eu

MODEL="${1:?usage: es-lint.sh <model.es>}"
[ -f "$MODEL" ] || { echo "es-lint: model not found: $MODEL" >&2; exit 2; }

awk '
BEGIN{
  ok["actor|issues|command"]=1;     ok["policy|issues|command"]=1
  ok["command|handles|aggregate"]=1; ok["command|handles|external"]=1
  ok["aggregate|emits|event"]=1;    ok["aggregate|emits|errorevent"]=1
  ok["external|emits|event"]=1;     ok["external|emits|errorevent"]=1
  ok["event|triggers|policy"]=1;    ok["event|triggers|actor"]=1;   ok["event|feeds|readmodel"]=1
  vt["actor"]=1; vt["command"]=1; vt["aggregate"]=1; vt["event"]=1; vt["errorevent"]=1
  vt["policy"]=1; vt["readmodel"]=1; vt["external"]=1; vt["hotspot"]=1
}
/^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
$1=="N"{
  id=$2; t=$3; type[id]=t; declared[id]=1
  if(!(t in vt)) err[++ne]="未知の型: ノード " id " の型 \"" t "\" (有効: actor command aggregate event errorevent policy readmodel external hotspot)"
  if(index($0,"invariant=")>0) hasInv[id]=1
  if(index($0,"evidence=")>0)  hasEv[id]=1
  next
}
$1=="E"{ ef[++m]=$2; er[m]=$3; et[m]=$4; next }
{ err[++ne]="不正な行(先頭が N/E でない): " $0 }
END{
  for(i=1;i<=m;i++){
    f=ef[i]; r=er[i]; t=et[i]
    if(!(f in declared)){ err[++ne]="未宣言ノードを参照: " f " (エッジ " f " " r " " t ")"; continue }
    if(!(t in declared)){ err[++ne]="未宣言ノードを参照: " t " (エッジ " f " " r " " t ")"; continue }
    ft=type[f]; tt=type[t]
    if(ft=="hotspot" || tt=="hotspot"){               # ホットスポットは marks のみ（語彙を強制）
      if(r!="marks") err[++ne]="文法違反: hotspot のエッジは marks のみ: " ft "(" f ") --" r "--> " tt "(" t ")  ← ホットスポットは未決定論点のマーカー。接続は marks に限る"
      continue
    }
    key=ft"|"r"|"tt
    if(!(key in ok)){
      msg="文法違反: " ft "(" f ") --" r "--> " tt "(" t ")"
      if(ft=="event" && tt=="event")     msg=msg "  ← イベントはイベントを直接呼べない。間に [policy]→[command]→[aggregate] が必要"
      if(ft=="command" && tt=="event")    msg=msg "  ← コマンドがイベントを直接emit。集約[aggregate]をスキップしている"
      if(ft=="aggregate" && tt=="aggregate") msg=msg "  ← 集約→集約は不可"
      err[++ne]=msg
    }
    if(r=="emits" && (tt=="event"||tt=="errorevent")) emitters[t]++
    if(r=="handles") hasAgg[f]=1
  }
  for(id in declared) if(type[id]=="aggregate" && !(id in hasInv))
    err[++ne]="集約に不変条件がない: " id " ← これは集約ではなくルール/仕様の可能性。invariant= を付けるか型を見直す"
  for(id in emitters) if(emitters[id]>1)
    err[++ne]="イベントを複数の集約がemit: " id " (" emitters[id] "件) ← イベントは1集約に属する"
  for(id in declared) if(type[id]=="command" && !(id in hasAgg))
    warn[++nw]="孤児コマンド: " id " ← 受領する集約 (command --handles--> aggregate) が無い"
  for(id in declared) if(type[id]=="event" && !(id in hasEv))
    warn[++nw]="証拠リンクなしイベント: " id " ← evidence= (path:line) か hypothesis 化が必要"

  print "=== es-lint: " FILENAME " ==="
  if(ne==0) print "  OK: 文法違反なし"
  for(i=1;i<=ne;i++) print "  [ERROR] " err[i]
  for(i=1;i<=nw;i++) print "  [warn]  " warn[i]
  print "---- ERROR=" ne+0 " WARN=" nw+0 " ----"
  if(ne>0) exit 1
}
' "$MODEL"
