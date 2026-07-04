#!/bin/sh
# [汎用コア] es-coverage.sh — TO-BE モデル ↔ コード対応の導出（ADVISORY, not a gate）
# gatecrate-type: advisory  (フィットネス信号を出す・非ブロック；価値=信号が消費されるか)
#
# WHY: `.es` の evidence リンクはモデル↔コードの唯一の対応台帳（check-es-evidence がドリフトを、
# check-evidence-resolves が捏造を塞ぐ）。TO-BE のノードは実装されるまで evidence を持たないので、
# 「TO-BE にどれだけ近づいたか」は evidence の集合演算だけで決定論導出できる——LLM の達成度判断は
# 使わない（ゲームされ、コミット間で揺れる）。本スクリプトは TO-BE 各ノードを
#   implemented  evidence があり実コードに解決する
#   stale        evidence があるが解決しない（進捗の裏で腐った実装済。隠すと達成率が嘘をつく）
#   missing      evidence が無い（未実装 = TO-BE ギャップ）
# に分類し、ギャップ一覧と達成率（implemented/対象数）を出す。
#
# 対象種別: コードになる種別のみ（command/aggregate/event/errorevent/policy/readmodel）。
# actor/external/hotspot はコードにならないため evidence を要求しない。
# AS-IS を併せて渡すと becomes= 対応も突合する: TO-BE に無い id を指す becomes=（モデル不整合）と、
# どの becomes= からも指されない TO-BE ノード（新規能力）を報告する。
#
# 導出値を源泉に書き戻さない: status は毎回計算する。`.es` に status= を書くと evidence との
# 二重管理が始まる（dashboard が毎回 render するのと同じ原則）。
#
# Usage:
#   sh es-coverage.sh <tobe.es> [asis.es]
# Config (env, from harness.config.sh or CLI env):
#   EVIDENCE_CODE_ROOT — evidence 解決先のコード根（既定: git root。check-evidence-resolves と同名）
#   ES_COVERAGE_KINDS  — coverage 対象の種別（既定: "command aggregate event errorevent policy readmodel"）
#   ES_COVERAGE_OUT    — 成果物出力先（既定: <root>/build/quality）
# Outputs: <out>/es-coverage.tsv  (id \t kind \t label \t status \t evidence)
# Exit: 0=導出完了（advisory・件数によらず） / 2=入力不備
set -eu

TOBE="${1:?usage: es-coverage.sh <tobe.es> [asis.es]}"
ASIS="${2:-}"
[ -f "$TOBE" ] || { echo "es-coverage: model not found: $TOBE" >&2; exit 2; }
[ -z "$ASIS" ] || [ -f "$ASIS" ] || { echo "es-coverage: asis model not found: $ASIS" >&2; exit 2; }

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"

ROOTC="${EVIDENCE_CODE_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"
KINDS="${ES_COVERAGE_KINDS:-command aggregate event errorevent policy readmodel}"
OUT="${ES_COVERAGE_OUT:-$ROOT/build/quality}"
mkdir -p "$OUT"

# --- TO-BE の対象ノードを id \t kind \t label \t evidence に射影 ---
extract_nodes() {
  awk -v kinds=" $KINDS " '
    function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/,"",s); return s }
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    $1=="N" {
      id=$2; kind=$3
      if (index(kinds, " " kind " ") == 0) next
      line=$0; sub(/^N[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+/,"",line)
      lbl=line; sub(/[[:space:]]*\|.*$/,"",lbl); lbl=trim(lbl)
      ev=""
      if (match($0, /\|[[:space:]]*evidence=[^|]*/)) {
        ev=substr($0, RSTART, RLENGTH); sub(/^\|[[:space:]]*evidence=/,"",ev); ev=trim(ev)
      }
      printf "%s\t%s\t%s\t%s\n", id, kind, lbl, ev
    }
  ' "$1"
}

# --- 1参照の解決（check-evidence-resolves と同じ規則: suffix/basename 発見・行数・メソッド名） ---
resolve_ref() {
  rp="$1"; loc="$2"
  base="$(basename "$rp")"
  f="$(find "$ROOTC" -type f -path "*/$rp" 2>/dev/null | head -1)"
  [ -n "$f" ] || f="$(find "$ROOTC" -type f -name "$base" 2>/dev/null | head -1)"
  [ -n "$f" ] || return 1
  [ -n "$loc" ] || return 0
  if printf '%s' "$loc" | grep -qE '^[0-9]+$'; then
    n="$(wc -l < "$f" | tr -d ' ')"; [ "$n" -ge "$loc" ] && return 0 || return 1
  fi
  name="$(printf '%s' "$loc" | sed 's/().*$//; s/(.*$//')"
  [ -n "$name" ] || return 0
  grep -q "$name" "$f" && return 0 || return 1
}

# evidence 値 -> status（複数参照は1つでも解決すれば implemented）
node_status() {
  ev="$1"
  [ -n "$ev" ] || { echo missing; return; }
  refs="$(printf '%s\n' "$ev" | grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z]+(:[0-9A-Za-z_()]+)?' || true)"
  [ -n "$refs" ] || { echo stale; return; }   # file 参照の形をしていない evidence は解決不能扱い
  for ref in $refs; do
    rp="${ref%%:*}"; loc=""
    case "$ref" in *:*) loc="${ref#*:}";; esac
    if resolve_ref "$rp" "$loc"; then echo implemented; return; fi
  done
  echo stale
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
extract_nodes "$TOBE" > "$WORK/targets"

: > "$OUT/es-coverage.tsv"
while IFS="$(printf '\t')" read -r id kind lbl ev; do
  [ -n "$id" ] || continue
  st="$(node_status "$ev")"
  printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$kind" "$lbl" "$st" "$ev" >> "$OUT/es-coverage.tsv"
done < "$WORK/targets"

total=$(wc -l < "$OUT/es-coverage.tsv" | tr -d ' ')
impl=$(awk -F'\t' '$4=="implemented"' "$OUT/es-coverage.tsv" | wc -l | tr -d ' ')
stale=$(awk -F'\t' '$4=="stale"' "$OUT/es-coverage.tsv" | wc -l | tr -d ' ')
miss=$(awk -F'\t' '$4=="missing"' "$OUT/es-coverage.tsv" | wc -l | tr -d ' ')

echo "==================== es-coverage (tobe: $TOBE / code root: $ROOTC) ===================="
echo ""
if [ "$total" -eq 0 ]; then
  echo "coverage 対象ノードなし（対象種別: $KINDS）。"
else
  echo "TO-BE 達成: $impl/$total implemented / stale: $stale / missing: $miss"
fi
echo ""
if [ "$miss" -gt 0 ]; then
  echo "--- missing: TO-BE にあるが evidence が無い（未実装ギャップ = 次にやる仕事） ---"
  awk -F'\t' '$4=="missing" { printf "  [%s] %s %s\n", $2, $1, $3 }' "$OUT/es-coverage.tsv"
  echo ""
fi
if [ "$stale" -gt 0 ]; then
  echo "--- stale: evidence が実コードに解決しない（ドリフト = 台帳か実装を直す） ---"
  awk -F'\t' '$4=="stale" { printf "  [%s] %s %s  (evidence: %s)\n", $2, $1, $3, $5 }' "$OUT/es-coverage.tsv"
  echo ""
fi

# --- AS-IS becomes= 突合（任意） ---
if [ -n "$ASIS" ]; then
  # 不整合判定の突合先は TO-BE の「全ノード id」（coverage 対象外の actor 等への対応も正当）。
  awk '/^[[:space:]]*#/ || /^[[:space:]]*$/ { next } $1=="N" { print $2 }' "$TOBE" > "$WORK/tobe_ids"
  # AS-IS の becomes= 対象 id を1行1個に展開（becomes= の値はカンマ区切り。説明文は | で切れる）
  awk '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    $1=="N" && match($0, /\|[[:space:]]*becomes=[^|]*/) {
      v=substr($0, RSTART, RLENGTH); sub(/^\|[[:space:]]*becomes=/,"",v)
      gsub(/[[:space:]]/,"",v)
      n=split(v, a, ","); for(i=1;i<=n;i++) if(a[i]!="") print a[i]
    }
  ' "$ASIS" | sort -u > "$WORK/becomes_ids"
  sort -u "$WORK/tobe_ids" > "$WORK/tobe_ids.s"
  DANGLING="$(comm -23 "$WORK/becomes_ids" "$WORK/tobe_ids.s")"
  UNMAPPED="$(comm -13 "$WORK/becomes_ids" "$WORK/tobe_ids.s")"
  if [ -n "$DANGLING" ]; then
    echo "--- モデル不整合: AS-IS の becomes= が TO-BE に無い id を指している（どちらかを直す） ---"
    printf '%s\n' "$DANGLING" | sed 's/^/  /'
    echo ""
  fi
  if [ -n "$UNMAPPED" ]; then
    echo "--- 新規能力: どの AS-IS の becomes= からも指されない TO-BE ノード（情報・移行でなく新設） ---"
    printf '%s\n' "$UNMAPPED" | sed 's/^/  /'
    echo ""
  fi
fi

echo "detail: $OUT/es-coverage.tsv"
echo "es-coverage done (implemented $impl / stale $stale / missing $miss / advisory)"
exit 0
