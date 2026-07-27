#!/bin/sh
# [汎用core] measure-modularity.sh — Balanced Coupling 3次元評価 (ADVISORY, not a gate)
# gatecrate-type: advisory  (フィットネス信号を出す・既定は非ブロック、--strict で gate；価値=信号が消費されるか)
#
# WHY: measure-coupling.sh は strength(import数)×volatility の2次元縮約で、distance は「別パッケージか否か」
# の2値に落ちていた（docs/code-quality-metrics.md が明記していた既知の欠落）。vladikk の Balanced Coupling は
# 3次元のバランス式でモジュール性を定義する:
#     BALANCE = (STRENGTH XOR DISTANCE) OR NOT VOLATILITY
# 「強い結合は近くに置き、遠い結合は弱くする。このバランスが破れていても、依存先が変動しないなら実害はない」。
# 本スクリプトはこれを機械評価し、
#   RED    = 強い×遠い×変動   (最悪形: 依存先が変わるたびに遠くまで強い波及が走る。ratchet ゲートの reject 対象)
#   YELLOW = 弱い×近い×変動   (過剰分割の疑い: すぐ隣のよく変わる相手と契約越しに付き合っており、
#                              境界の維持費が見合っていない可能性。統合候補・非ブロック)
# を報告する。
#
# 分業（決定論は機械・判断はエージェント）: distance(パッケージ木距離)と volatility(git履歴)は機械計測。
# strength の質的レベル contract(1) < model(2) < functional(3) < intrusive(4) は意味論的判断であり機械では
# 計測できないため、判断層（modularity-review スキル/人間）が modularity-strength.tsv に証拠つきで分類し、
# 本スクリプトはそれを consume するだけ。未分類エッジは既定レベル(model)で評価しつつ「未分類」として
# 報告する＝判断層への作業キュー。
#
# STACK ASSUMPTION: エッジ抽出は measure-coupling.sh に委譲するため同じ JVM 前提（COUPLING_PKG_PREFIX 必須）。
# テスト/非JVM 用に MODULARITY_EDGES_FILE / MODULARITY_VOLATILITY_FILE シームで直接注入できる。
#
# Usage:
#   sh core/scripts/measure-modularity.sh            # print report (always exit 0)
#   sh core/scripts/measure-modularity.sh --strict   # exit 1 if any RED edge exists
#
# Config (optional, from harness.config.sh in the consumer repo root, or env):
#   MODULARITY_STRENGTH_FILE  — 判断層の分類TSV: src_pkg \t dst_pkg \t level \t evidence
#                               (default: <root>/modularity-strength.tsv; 無ければ全エッジ未分類扱い)
#   MODULARITY_DEFAULT_LEVEL  — 未分類エッジの評価レベル (default: model)
#   MODULARITY_STRENGTH_HIGH  — 「強い」の下限レベル値 (default: 3 = functional 以上)
#   MODULARITY_DISTANCE_HIGH  — 「遠い」の下限パッケージ木距離 (default: 4 = 兄弟パッケージ(2)は近い)
#   MODULARITY_VOL_HIGH       — 「変動」の下限変更回数/窓 (default: 5)
#   MODULARITY_EDGES_FILE / MODULARITY_VOLATILITY_FILE — test seam: measure-coupling を呼ばず直接読む
#   MODULARITY_OUT_DIR        — 成果物出力先 (default: <root>/build/quality)
# Outputs: <out>/modularity-all.tsv (全エッジ判定) / <out>/modularity-red.tsv (RED のみ、ratchet が consume)
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"

OUT="${MODULARITY_OUT_DIR:-$ROOT/build/quality}"
mkdir -p "$OUT"
STRICT=0
EMIT_QUEUE=0
case "${1:-}" in
  --strict)     STRICT=1 ;;
  --emit-queue) EMIT_QUEUE=1 ;;
esac

STRENGTH_FILE="${MODULARITY_STRENGTH_FILE:-$ROOT/modularity-strength.tsv}"
DEFAULT_LEVEL="${MODULARITY_DEFAULT_LEVEL:-model}"
S_HIGH="${MODULARITY_STRENGTH_HIGH:-3}"
D_HIGH="${MODULARITY_DISTANCE_HIGH:-4}"
V_HIGH="${MODULARITY_VOL_HIGH:-5}"

# --- inputs: seam files, or delegate extraction to measure-coupling.sh ---
EDGES="${MODULARITY_EDGES_FILE:-}"
VOL="${MODULARITY_VOLATILITY_FILE:-}"
if [ -z "$EDGES" ]; then
  if ! sh "$(dirname -- "$0")/measure-coupling.sh" > "$OUT/coupling-report.txt" 2>&1; then
    echo "measure-modularity: measure-coupling.sh failed — see $OUT/coupling-report.txt" >&2
    exit 2
  fi
  EDGES="$ROOT/build/quality/edges.tsv"
  VOL="$ROOT/build/quality/volatility.tsv"
fi
if [ ! -f "$EDGES" ]; then
  echo "measure-modularity: edges file not found: $EDGES (set COUPLING_PKG_PREFIX for import extraction, or the MODULARITY_EDGES_FILE seam)" >&2
  exit 2
fi
[ -f "$VOL" ] || VOL=/dev/null

if [ ! -s "$EDGES" ]; then
  echo "measure-modularity: no internal package edges to assess (empty edge set)."
  : > "$OUT/modularity-all.tsv"; : > "$OUT/modularity-red.tsv"
  exit 0
fi

# --- evaluate every unique (src,dst) edge against the balance formula ---
# all.tsv columns: src \t dst \t imports \t level \t dist \t vol \t load \t verdict \t classified
rc=0
awk -F'\t' -v OFS='\t' \
    -v strength_file="$STRENGTH_FILE" -v vol_file="$VOL" \
    -v def_level="$DEFAULT_LEVEL" -v s_high="$S_HIGH" -v d_high="$D_HIGH" -v v_high="$V_HIGH" '
  function pkgdist(a, b,   x, y, na, nb, c, i) {
    na = split(a, x, "."); nb = split(b, y, "."); c = 0
    for (i = 1; i <= na && i <= nb; i++) { if (x[i] == y[i]) c++; else break }
    return (na - c) + (nb - c)
  }
  BEGIN {
    lv["contract"] = 1; lv["model"] = 2; lv["functional"] = 3; lv["intrusive"] = 4
    if (!(def_level in lv)) {
      printf "measure-modularity: invalid MODULARITY_DEFAULT_LEVEL \"%s\"\n", def_level > "/dev/stderr"
      exit 2
    }
    while ((getline line < strength_file) > 0) {
      if (line ~ /^[ \t]*(#|$)/) continue
      n = split(line, f, "\t")
      if (n < 3 || !(f[3] in lv)) {
        printf "measure-modularity: invalid strength entry (level must be contract|model|functional|intrusive): %s\n", line > "/dev/stderr"
        exit 2
      }
      cls[f[1] "\t" f[2]] = f[3]
    }
    while ((getline line < vol_file) > 0) {
      split(line, f, "\t"); vol[f[1]] = f[2]
    }
  }
  { imports[$1 "\t" $2]++ }
  END {
    for (e in imports) {
      split(e, p, "\t")
      classified = (e in cls) ? "yes" : "no"
      lname = (e in cls) ? cls[e] : def_level
      s = lv[lname]; d = pkgdist(p[1], p[2]); v = vol[p[2]] + 0
      sh = (s >= s_high); dh = (d >= d_high); vh = (v >= v_high)
      # BALANCE = (S XOR D) OR NOT V; the two imbalance shapes are graded by harm:
      if (sh && dh && vh)        verdict = "RED"     # strong, distant, volatile
      else if (!sh && !dh && vh) verdict = "YELLOW"  # weak, near, volatile: over-fragmented?
      else                       verdict = "OK"
      print p[1], p[2], imports[e], lname, d, v, s * d * v, verdict, classified
    }
  }
' "$EDGES" > "$OUT/modularity-all.tsv" || rc=$?
if [ "$rc" -ne 0 ]; then
  exit 2
fi

# --emit-queue: 未分類エッジを「分類作業のキュー」として CSV で出す。
# なぜ CSV か: TAKT の arpeggio(data-driven batch)の組み込みデータソースは CSV 固定
# （区切りは ',' ・ヘッダ行必須）で、TSV のままでは列を分解できない。分類は1エッジずつ
# src を読んで判断する作業＝収束ループでなくバッチ処理が適合するため、その入力を用意する。
# 分類そのものは機械化しない（本スクリプト冒頭のとおり意味論的判断であり計測できない）。
TAB="$(printf '\t')"
sort -t"$TAB" -k7,7nr "$OUT/modularity-all.tsv" > "$OUT/modularity-all.sorted.tsv" \
  && mv "$OUT/modularity-all.sorted.tsv" "$OUT/modularity-all.tsv"
if [ "$EMIT_QUEUE" -eq 1 ]; then
  {
    echo "src,dst,imports,level,dist,vol,load,verdict"
    awk -F"$TAB" '$9 == "no" { printf "%s,%s,%s,%s,%s,%s,%s,%s\n", $1,$2,$3,$4,$5,$6,$7,$8 }' \
      "$OUT/modularity-all.tsv"
  } > "$OUT/modularity-queue.csv"
  echo "modularity: work queue -> $OUT/modularity-queue.csv ($(( $(wc -l < "$OUT/modularity-queue.csv") - 1 )) unclassified edge(s))"
fi
awk -F'\t' -v OFS='\t' '$8 == "RED" { print $1, $2, $3, $4, $5, $6, $7 }' \
  "$OUT/modularity-all.tsv" > "$OUT/modularity-red.tsv"

# --- report ---
echo "==================== modularity (Balanced Coupling: strength x distance x volatility) ===================="
echo ""
awk -F'\t' '
  { t++; if ($8 == "RED") r++; else if ($8 == "YELLOW") y++
    if ($9 == "no") u++ }
  END { printf "edges assessed: %d / RED (strong x distant x volatile): %d / YELLOW (possibly over-fragmented): %d / strength unclassified: %d\n", t+0, r+0, y+0, u+0 }
' "$OUT/modularity-all.tsv"
echo ""

if [ -s "$OUT/modularity-red.tsv" ]; then
  echo "--- RED: balance violations (weaken the coupling, move it closer, or justify it in the baseline) ---"
  printf '%-7s %-11s %-5s %-4s %s\n' "load" "strength" "dist" "vol" "edge"
  head -10 "$OUT/modularity-red.tsv" | awk -F'\t' '{ printf "%-7d %-11s %-5d %-4d %s -> %s\n", $7, $4, $5, $6, $1, $2 }'
  echo ""
fi
yellow_n=$(awk -F'\t' '$8 == "YELLOW"' "$OUT/modularity-all.tsv" | wc -l | tr -d ' ')
if [ "$yellow_n" -gt 0 ]; then
  echo "--- YELLOW: weak x near x volatile (a boundary right next to a frequently-changing neighbor — is the split worth its upkeep?) ---"
  awk -F'\t' '$8 == "YELLOW"' "$OUT/modularity-all.tsv" | head -5 \
    | awk -F'\t' '{ printf "  vol %-4d %s -> %s\n", $6, $1, $2 }'
  echo ""
fi
uncls_n=$(awk -F'\t' '$9 == "no"' "$OUT/modularity-all.tsv" | wc -l | tr -d ' ')
if [ "$uncls_n" -gt 0 ]; then
  echo "--- unclassified strength (evaluated at default \"$DEFAULT_LEVEL\"; classify via the modularity-review skill) ---"
  echo "    classify them in $STRENGTH_FILE, one line per edge:"
  echo "    src_pkg<TAB>dst_pkg<TAB>contract|model|functional|intrusive<TAB>evidence (file:line)"
  awk -F'\t' '$9 == "no"' "$OUT/modularity-all.tsv" | head -8 \
    | awk -F'\t' '{ printf "  load %-6d %s -> %s\n", $7, $1, $2 }'
  echo ""
fi
echo "detail: $OUT/modularity-all.tsv / RED set for the ratchet gate: $OUT/modularity-red.tsv"

red_n=$(wc -l < "$OUT/modularity-red.tsv" | tr -d ' ')
if [ "$STRICT" -eq 1 ] && [ "$red_n" -gt 0 ]; then
  echo "measure-modularity --strict: $red_n RED (imbalanced) edge(s) found" >&2
  exit 1
fi
echo "measure-modularity done (RED: $red_n / advisory)"
exit 0
