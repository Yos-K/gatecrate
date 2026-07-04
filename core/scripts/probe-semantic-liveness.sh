#!/bin/sh
# [汎用コア] 意味的レビュー工程の生存証明プローブ（ツール・非ゲート） — スタック非依存
#
# WHY: 意味的正しさの最後の砦は refute 工程（check-model-refuted が存在と鮮度を強制）だが、
# 「捕まえないレビュアは壊れていても見えない」——probe-gate-liveness が解いた死角の相似形。本ツールは
# **文法ゲートを通過する意味違反**を .es へ決定論注入し（先頭の適格2項目を入替＝乱数・時刻を使わない）、
# refute 工程がそれを名指しできたか（ALIVE/DEAD）を機械検証する＝レビュー工程への mutation testing。
# 判断（レビュー実行）はエージェント/人間、注入と判定は本ツール、という分業。
#
# 注入 kind（すべて es-lint / check-es-evidence を通過する＝意味だけが壊れる）:
#   retarget-evidence  先頭2ノードの evidence= 値を入替（行は実在するが主張を裏付けない）
#   swap-decide        先頭2ノードの decide= 値を入替（判定式が別ノードの意味になる）
#   swap-when          先頭2エッジの when= 値を入替（発火条件が入れ違う）
#
# 検出プロトコル: refuter は検出した違反の node/edge id を1行1個で列挙したファイルを出す。
# --verify は planted id のいずれかがそこに在れば ALIVE（入替の片端を名指し=捕捉）、無ければ DEAD。
#
# Usage:
#   probe-semantic-liveness.sh --list
#   probe-semantic-liveness.sh --inject  <kind> <model.es>              # 変異モデルを stdout へ
#   probe-semantic-liveness.sh --planted <kind> <model.es>              # 注入位置の id を1行1個
#   probe-semantic-liveness.sh --verify  <kind> <model.es> <report>     # ALIVE=0 / DEAD=1 / setup=2
set -eu

KINDS="retarget-evidence swap-decide swap-when"

usage() { echo "usage: probe-semantic-liveness.sh --list | --inject <kind> <model.es> | --planted <kind> <model.es> | --verify <kind> <model.es> <report>" >&2; exit 2; }

MODE="${1:-}"
[ "$MODE" = "--list" ] && { for k in $KINDS; do echo "$k"; done; exit 0; }
case "$MODE" in --inject|--planted|--verify) ;; *) usage ;; esac
KIND="${2:?usage: <kind> required}"
MODEL="${3:?usage: <model.es> required}"
case " $KINDS " in *" $KIND "*) ;; *) echo "probe-semantic: unknown kind '$KIND' (see --list)" >&2; exit 2 ;; esac
[ -f "$MODEL" ] || { echo "probe-semantic: model not found: $MODEL" >&2; exit 2; }

# 対象抽出パターン: kind ごとに「行選別の正規表現」と「入替対象の属性名」を決める（決定論＝先頭2件）。
case "$KIND" in
  retarget-evidence) SEL='^N ';  ATTR="evidence" ;;
  swap-decide)       SEL='^N ';  ATTR="decide" ;;
  swap-when)         SEL='^E ';  ATTR="when" ;;
esac

# 先頭2つの適格行（属性を持つ SEL 行）の行番号と id を求める。E 行の id は from ノード。
eligible() {
  awk -v sel="$SEL" -v attr="$ATTR" '
    $0 ~ sel && index($0, "| " attr "=") + index($0, "|" attr "=") + match($0, "\\|[[:space:]]*" attr "=") {
      if (match($0, "\\|[[:space:]]*" attr "=")) { print NR "\t" $2; c++ }
      if (c == 2) exit
    }
  ' "$MODEL"
}

ELIG="$(eligible)"
NELIG="$(printf '%s\n' "$ELIG" | grep -c . || true)"
if [ "$NELIG" -lt 2 ]; then
  echo "probe-semantic: $KIND の注入対象（$ATTR= を持つ行）が2つ未満 — 注入不能（setup。偽の判定を出さない）" >&2
  exit 2
fi
L1="$(printf '%s\n' "$ELIG" | sed -n '1p' | cut -f1)"; ID1="$(printf '%s\n' "$ELIG" | sed -n '1p' | cut -f2)"
L2="$(printf '%s\n' "$ELIG" | sed -n '2p' | cut -f1)"; ID2="$(printf '%s\n' "$ELIG" | sed -n '2p' | cut -f2)"

if [ "$MODE" = "--planted" ]; then
  printf '%s\n%s\n' "$ID1" "$ID2"
  exit 0
fi

if [ "$MODE" = "--verify" ]; then
  REPORT="${4:?usage: --verify <kind> <model.es> <report>}"
  [ -f "$REPORT" ] || { echo "probe-semantic: report not found: $REPORT" >&2; exit 2; }
  if grep -q "$ID1" "$REPORT" || grep -q "$ID2" "$REPORT"; then
    echo "ALIVE semantic-review ($KIND) — planted violation ($ID1/$ID2) was named by the refuter"
    exit 0
  fi
  echo "DEAD  semantic-review ($KIND) — planted violation ($ID1/$ID2) was NOT caught; the refute process is not measuring"
  exit 1
fi

# --inject: L1/L2 の ATTR 値を入れ替えて全文を出力（他行は無改変＝決定論）
awk -v l1="$L1" -v l2="$L2" -v attr="$ATTR" '
  function attrval(line,   v) {
    if (match(line, "\\|[[:space:]]*" attr "=[^|]*")) {
      v = substr(line, RSTART, RLENGTH); sub("^\\|[[:space:]]*" attr "=", "", v)
      gsub(/[[:space:]]+$/, "", v); return v
    }
    return ""
  }
  function swap(line, newv,   pre, post) {
    if (match(line, "\\|[[:space:]]*" attr "=[^|]*")) {
      pre = substr(line, 1, RSTART - 1)
      post = substr(line, RSTART + RLENGTH)
      return pre "| " attr "=" newv " " post
    }
    return line
  }
  NR == FNR { if (FNR == l1) v1 = attrval($0); if (FNR == l2) v2 = attrval($0); next }
  FNR == l1 { print swap($0, v2); next }
  FNR == l2 { print swap($0, v1); next }
  { print }
' "$MODEL" "$MODEL"
