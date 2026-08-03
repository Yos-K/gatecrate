#!/bin/sh
# [汎用コア] イベントストーミング 情報完全性ゲート（prevention・es-lint の上位層）
# gatecrate-type: prevention
#
# WHY: es-lint は「文法」(型・許可エッジ)を保証するが「情報の中身」は見ない。だが ES が分析に耐えるには、
# kawasima ドメイン記述ミニ言語の4層を満たす必要がある: lexicon(名前) / syntax(AND・OR・?) /
# semantics(behavior の入出力と不変条件) / pragmatics(BC)。用語集と言語の差は semantics=behavior。
# これらをプロンプトに置くと AI は埋め残すので、機械ゲートで強制する。さらに「フラグ・ステータスコード」は
# OR状態/状態遷移へ昇格すべき臭いとして指摘する（Wlaschin/kawasima 指針）。
#
# 文法拡張(N行・| 区切り):
#   data寄り:  fields=名:制約; 名?; 名:[a|b|c]      （AND合成・?任意・[..]OR分岐）
#              states=s1|s2|s3                       （OR状態集合＝状態機械）
#              transitions=名:from->to|fail; ...     （遷移＝semantics）
#   behavior:  in=a;b   out=X|Y   decide="..."       （入力->出力OR・判定）
# 規則:
#   R1 event/errorevent/readmodel は fields(運ぶ情報) 必須
#   R2 aggregate は fields または states 必須（構造か状態機械）
#   R3 policy は in/out/decide 必須、command は in/out 必須（behavior=semantics）
#   R4(warn) fields項目は :制約 推奨
#   R5(warn) フラグ/コード/status/stage 名 → OR状態・状態遷移へ昇格を検討
#   R6(warn) policy の in 項目が、どの fields/states にも定義が無い（出所未定義）
#   R17(warn) policy/command の out に**発火条件**が書かれている（欄の取り違え）
#             out は「判定の結果どの分岐になるか」（受理|入力不正 等の結果ラベルでよい）。
#             「常時」「毎回」等は発火条件であり when= に書くもの。ここが無検査だと `out=常時` が通り、
#             しかも when に「常時」があると R11 は out を一切見ないため、この穴は R17 でしか塞げない。
#             ※ out の選択肢が既存の語彙に解決するかまでは要求しない——判定結果は新しい語で
#               表すのが自然であり（受理/在庫切れ 等）、解決を強制すると正当な用法を弾く
#   R7(warn) decide が複合条件(∧/かつ/&&)なのに behaviors で述語(「期限内」等)を定義していない／
#            behavior に // 定義(計算ルール)が無い（用語が宙に浮く=semantics欠落）
#   R8(warn) becomes=(AS-IS→TO-BE変化) は「なぜそう変えるか」を含むこと（因果の明示）
#   R9(warn) 1図(=1.es)のノードが多すぎ(>40)＝毛玉化 → 1BCスライスに分割（.cmapでBC俯瞰し各BC別.esに）
#   R10(warn) 非ドメインイベントの疑い（取得/照会/分類/ロック等＝問合せ・技術操作）→ リードモデル化 or 除外
#   R11(warn) policy→command の when= が out= のどの選択肢とも対応しない（or when 無し）。
#             独立に書かれた2表現（判定の出力と発火条件）の一致＝意味の三角測量。常時なら「常時」と明記
#   R12(warn) transitions の from（と第1遷移先）が states= に宣言されていない。
#             「from->to|fail」の fail 側（失敗の帰結）は状態でなくてよいので免除
#   R13(warn) transitions の動詞に「// ドメイン上の意味」が無い（オーソリする＝業務で何をすることか）
#   R14(warn) states の状態に「// ドメイン上の意味」が無い（「受信」だけでは意味が分からない）
#   R15(warn) 存在論カテゴリ is=kind|role|phase|relator の整合（役割は role-of=担い手 を持つ）
#   R16(warn/err) kind-of(is-a) の参照先未解決 / is-a 循環（分類階層は木/DAG）
#
# Usage: sh es-lint-info.sh <model.es>     ( ERROR があれば exit 1 )
#   推奨: sh es-lint.sh m.es && sh es-lint-info.sh m.es
set -eu
MODEL="${1:?usage: es-lint-info.sh <model.es>}"
[ -f "$MODEL" ] || { echo "es-lint-info: model not found: $MODEL" >&2; exit 2; }

awk '
function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/,"",s); return s }
function basename(nm){ sub(/:.*$/,"",nm); sub(/\?$/,"",nm); return trim(nm) }
function smell(nm){ return (nm ~ /(フラグ|flag|ステータス|status|stage|応答コード|コード|code)/) }
/^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
$1=="N"{
  id=$2; ty=$3; type[id]=ty; order[++n]=id
  line=$0; sub(/^N[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+/,"",line)
  lb=line; sub(/[[:space:]]*\|.*$/,"",lb); lbl[id]=trim(lb)
  delete KV; r=line
  while(match(r,/\|[[:space:]]*[a-zA-Z][a-zA-Z-]*=/)){ seg=substr(r,RSTART); r=substr(r,RSTART+RLENGTH)
    k=seg; sub(/^\|[[:space:]]*/,"",k); sub(/=.*$/,"",k); v=r
    if(match(v,/\|[[:space:]]*[a-zA-Z][a-zA-Z-]*=/)) v=substr(v,1,RSTART-1); KV[k]=trim(v) }
  fld[id]=KV["fields"]; sts[id]=KV["states"]; bin[id]=KV["in"]; bout[id]=KV["out"]; dec[id]=KV["decide"]; bhv[id]=KV["behaviors"]; bcm[id]=KV["becomes"]; trn[id]=KV["transitions"]; onto[id]=KV["is"]; kof[id]=KV["kind-of"]; rof[id]=KV["role-of"]
  # known: 全fields基底名 + 全states + event fields
  if(fld[id]!=""){ c=split(fld[id],a,/;/); for(i=1;i<=c;i++){ nm=basename(a[i]); if(nm!=""){ known[nm]=1; fldlist[id,++fc[id]]=a[i] } } }
  if(sts[id]!=""){ c=split(sts[id],a,/\|/); for(i=1;i<=c;i++){ nm=a[i]; sub(/\/\/.*$/,"",nm); nm=trim(nm); if(nm!="") known[nm]=1 } }
  next
}
$1=="E"{
  # policy→command エッジの when= を R11（三角測量）用に記録
  me++; ef[me]=$2; er[me]=$3
  w=""
  if(match($0,/\|[[:space:]]*when=[^|]*/)){ w=substr($0,RSTART,RLENGTH); sub(/^\|[[:space:]]*when=/,"",w); w=trim(w) }
  ew[me]=w
  next
}
END{
  ne=0; nw=0
  for(i=1;i<=n;i++){ id=order[i]; ty=type[id]
    if(ty=="event"||ty=="errorevent"||ty=="readmodel"){
      if(fld[id]=="") err[++ne]="R1 情報なし: " ty "(" id ") ← fields= で運ぶ情報を列挙。後続が判定できない"
    }
    # R10: ドメインイベントは「業務上の状態変化の事実」のみ。問合せ・取得・技術操作はイベントでない
    if((ty=="event"||ty=="errorevent") && lbl[id] ~ /(取得|参照|照会|分類|算出|計算|検索|読[み込]|再読込|ロック|特定|キャッシュ|セッション)[^。]*され/) \
      warn[++nw]="R10 非ドメインイベントの疑い: " id " \"" lbl[id] "\" は問合せ/技術操作のよう ← ドメインイベント=業務状態の変化の事実のみ。問合せ結果はリードモデルへ、技術操作(ロック/再読込/照会)は除外"
    if(ty=="aggregate"){
      if(fld[id]=="" && sts[id]=="") err[++ne]="R2 構造なし: aggregate(" id ") ← fields= か states= で構造/状態を表出"
    }
    if(ty=="policy"){
      if(bin[id]=="") err[++ne]="R3 in無し: policy(" id ") ← 判定に使う入力(in=)を明示"
      if(bout[id]=="") err[++ne]="R3 out無し: policy(" id ") ← 出力(out=X|Y)を明示(semantics)"
      if(dec[id]=="") err[++ne]="R3 decide無し: policy(" id ") ← 判定式(decide=\"...\")を明示"
      if(bin[id]!=""){ c=split(bin[id],a,/;/); for(j=1;j<=c;j++){ nm=basename(a[j]); if(nm!="" && !(nm in known)) warn[++nw]="R6 出所未定義: policy(" id ") の in \"" nm "\" は どの fields/states にも定義が無い" } }
    }
    # R17: out に発火条件を書いていないこと（欄の取り違え）。
    # in(R6) は出所を検査されるのに out は「存在するか」しか見られていなかった。その結果
    # `out=常時` のような取り違えが通る。しかも when に「常時」が含まれると R11 は即 continue し
    # out を一切見ないため、この穴は R17 でしか塞げない。
    # out の選択肢が既存語彙に解決するかは**要求しない**——判定結果は新しい語で表すのが自然で
    # （受理/在庫切れ 等）、解決を強制すると正当な用法を弾く（実測: 既存モデルで40件の誤検出）。
    if(type[id]=="policy" || type[id]=="command"){
      if(bout[id]!=""){
        c=split(bout[id],a,/\|/)
        for(j=1;j<=c;j++){
          nm=trim(a[j])
          if(nm=="") continue
          if(nm ~ /^(常時|毎回|always|いつでも|無条件)$/)
            warn[++nw]="R17 欄の取り違え: " type[id] "(" id ") の out \"" nm "\" は発火条件であって出力ではない ← out には判定の結果(受理|入力不正 等)を書き、発火条件は when= に書く"
        }
      }
      # R7: 複合判定の述語(「期限内」「残量評価」等)が behaviors で定義されているか
      if((dec[id] ~ /∧/ || dec[id] ~ /かつ/ || dec[id] ~ /&&/) && bhv[id]=="") warn[++nw]="R7 述語未定義: policy(" id ") の decide が複合条件だが behaviors で言葉(期限内/残量評価 等)を定義していない ← 用語が宙に浮く(semantics欠落)"
      if(bhv[id]!=""){ c=split(bhv[id],a,/;/); for(j=1;j<=c;j++){ if(trim(a[j])!="" && index(a[j],"//")==0){ nm2=a[j]; sub(/:.*/,"",nm2); warn[++nw]="R7 定義なし述語: policy(" id ") の behavior \"" trim(nm2) "\" に // 定義(計算ルール)が無い" } } }
    }
    if(ty=="command"){
      if(bin[id]=="") warn[++nw]="R3 in無し(command): " id " ← in= を推奨"
      if(bout[id]=="") warn[++nw]="R3 out無し(command): " id " ← out= を推奨"
    }
    # R4/R5: fields 各項目
    for(j=1;j<=fc[id];j++){ it=fldlist[id,j]; nm=basename(it)
      if(index(it,":")==0 && index(it,"[")==0) warn[++nw]="R4 制約なし: " id "." nm " ← :型/制約 を推奨"
      if(smell(nm) && index(it,"[")==0) warn[++nw]="R5 臭い(フラグ/コード): " id "." nm " ← OR状態 [a|b] か states/transitions へ昇格を検討" }
    if(sts[id]!=""){ c=split(sts[id],a,/\|/); for(j=1;j<=c;j++){ nm=a[j]; sub(/\/\/.*$/,"",nm); nm=trim(nm); if(smell(nm)) warn[++nw]="R5 臭い: " id " の状態名 \"" nm "\" がコード臭い" } }
    # R13/R14: 動詞(transitions)と状態(states)は「// ドメイン上の意味」を持つこと（semantics層。名前だけでは意味が分からない）
    if(trn[id]!=""){ c=split(trn[id],a,/;/); for(j=1;j<=c;j++){ it=trim(a[j]); if(it!="" && it !~ /\/\//){ vn=it; sub(/:.*$/,"",vn); warn[++nw]="R13 動詞の意味未定義: " id " の \"" trim(vn) "\" ← 「// 意味」でドメイン上何をすることか定義（例: オーソリする // 支払い枠を確保する）" } } }
    if(sts[id]!=""){ c=split(sts[id],a,/\|/); for(j=1;j<=c;j++){ it=trim(a[j]); if(it!="" && it !~ /\/\//){ warn[++nw]="R14 状態の意味未定義: " id " の \"" it "\" ← 「// 意味」で業務上どういう局面か定義（例: 受信 // 要求を受け取り決済が未着手）" } } }
    # R8: AS-IS→TO-BE 変化(becomes=)は「なぜ」を必ず含む（変化の理由＝因果の明示）
    if(bcm[id]!="" && index(bcm[id],"なぜ")==0) warn[++nw]="R8 理由なし: " id " の becomes= に「なぜ」が無い ← AS-IS→TO-BE変化の理由を「。なぜ: …」で記載"
    # R15: 存在論カテゴリ(is=)の整合。役割(role)は担い手(role-of)を持つ／role-of があるなら is=role
    if(onto[id]!="" && onto[id]!~/^(kind|role|phase|relator)$/) warn[++nw]="R15 カテゴリ不正: " id " の is=\"" onto[id] "\" ← kind(種)|role(役割)|phase(相)|relator(関係子)"
    if(onto[id]=="role" && rof[id]=="") warn[++nw]="R15 担い手なし: " id " は is=role(役割) だが role-of=(担い手の種) が無い ← 役割は「何が」演じるかを明記(例: 顧客 role-of=人)"
    if(rof[id]!="" && onto[id]!="" && onto[id]!="role") warn[++nw]="R15 矛盾: " id " に role-of= があるのに is=" onto[id] " ← role-of を持つのは役割(is=role)"
  }
  # R16: kind-of(is-a) の参照先がモデル内に存在し、循環しないこと
  for(i=1;i<=n;i++){ lab2id[lbl[order[i]]]=order[i] }
  for(i=1;i<=n;i++){ id=order[i]
    if(kof[id]=="") continue
    if(!(kof[id] in lab2id)){ warn[++nw]="R16 上位概念が未解決: " id " の kind-of=\"" kof[id] "\" がモデル内のどのノードのラベルとも一致しない"; continue }
    # 循環検出（ラベル→idを辿る）
    seen=""; cur=id
    while(cur!="" && kof[cur]!="" && (kof[cur] in lab2id)){
      nxt=lab2id[kof[cur]]
      if(index(seen,"|" nxt "|")>0 || nxt==id){ err[++ne]="R16 is-a循環: " id " から kind-of を辿ると循環する ← 分類階層は木/DAG"; break }
      seen=seen "|" cur "|"; cur=nxt
    }
  }
  # R9: 1図(=1.es)のノードが多すぎる → 1BCスライスに分割（毛玉化＝可読限界の防止）
  if(n>40) warn[++nw]="R9 図が過大: ノード " n " 個(>40) ← 1図=1BCスライスへ分割。コンテキストマップ(.cmap)でBCを俯瞰し、各BCを別 .es に。100個級は可読限界を超え「毛玉」化する"
  # R11: policy→command の when= と out= の三角測量（独立に書かれた2表現の一致を機械検査）
  for(e=1;e<=me;e++){ f=ef[e]
    if(er[e]!="issues" || type[f]!="policy") continue
    if(ew[e]==""){ warn[++nw]="R11 when無し: policy(" f ") のエッジに when= が無い ← どの出力で発火するかを明記（常時なら「常時」）"; continue }
    if(index(ew[e],"常時")>0) continue
    okw=0; c=split(bout[f],alts,/\|/)
    for(j=1;j<=c;j++){ alt=trim(alts[j]); if(alt!="" && index(ew[e],alt)>0){ okw=1; break } }
    if(!okw) warn[++nw]="R11 不一致: policy(" f ") の when=\"" ew[e] "\" が out=\"" bout[f] "\" のどの選択肢とも対応しない ← 判定の出力と発火条件がズレている（どちらかが誤り）"
  }
  # R12: transitions の from（と第1遷移先）は宣言済み state であること（to|fail の fail 側は帰結として免除）
  for(i=1;i<=n;i++){ id=order[i]
    if(type[id]!="aggregate" || trn[id]=="") continue
    delete stset; c=split(sts[id],a,/\|/); for(j=1;j<=c;j++){ nm=a[j]; sub(/\/\/.*$/,"",nm); nm=trim(nm); if(nm!="") stset[nm]=1 }
    c=split(trn[id],segs,/;/)
    for(j=1;j<=c;j++){ seg=segs[j]; sub(/\/\/.*$/,"",seg); seg=trim(seg); if(seg=="") continue
      sub(/^[^:]*:/,"",seg)                               # 遷移名を除去 -> from->to|alt
      if(split(seg,ft,/->/)<2) continue
      from=trim(ft[1]); split(ft[2],tos,/\|/); to1=trim(tos[1])
      if(from!="" && !(from in stset)) warn[++nw]="R12 未宣言state: aggregate(" id ") の遷移元 \"" from "\" が states= に無い ← 状態機械と遷移がズレている"
      if(to1!="" && !(to1 in stset)) warn[++nw]="R12 未宣言state: aggregate(" id ") の遷移先 \"" to1 "\" が states= に無い ← 第1遷移先は宣言済み状態にする（失敗の帰結は to|fail の fail 側へ）"
    }
  }
  print "=== es-lint-info: " FILENAME " ==="
  if(ne==0) print "  OK: 情報完全性(ERROR) 充足"
  for(i=1;i<=ne;i++) print "  [ERROR] " err[i]
  for(i=1;i<=nw;i++) print "  [warn]  " warn[i]
  print "---- ERROR=" ne+0 " WARN=" nw+0 " ----"
  exit (ne>0?1:0)
}
' "$MODEL"
