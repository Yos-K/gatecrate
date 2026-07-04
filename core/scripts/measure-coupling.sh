#!/bin/sh
# [汎用core] measure-coupling.sh — package coupling measurement (ADVISORY, not a gate)
# gatecrate-type: advisory  (フィットネス信号を出す・既定は非ブロック、--strict で gate；価値=信号が消費されるか)
#
# WHY: coupling determines a change's "blast radius" and so dominates an AI agent's cost to
# modify code. Following vladikk's Balanced Coupling (load = strength x distance x volatility),
# this ranks dangerous "far, strong, frequently-changing" couplings using both static coupling
# (imports) and temporal coupling (git co-changes).
# Thresholds and interpretation: docs/code-quality-metrics.md.
#
# LANGUAGES: the import-edge extraction is language-parametric via COUPLING_LANG
# (java = default / python / go / typescript / rust). For java it reads `package x.y;` +
# `import <PKG_PREFIX>...` (COUPLING_PKG_PREFIX REQUIRED). For go it reads `import "<PKG_PREFIX>/x/y"`
# (PKG_PREFIX = the go.mod module path, REQUIRED). For python (`from a.b import` / `import a.b`),
# typescript (relative `from './x'` imports, resolved per file) and rust (`use crate::a::b::…`)
# no prefix is needed — the MODULE is the source DIRECTORY relative to COUPLING_SRC, dot-joined
# ("root" for files directly under it), so pkgdist/modularity work unchanged. When a required
# prefix is missing the import half is skipped and only the language-agnostic git co-change
# coupling is reported (still a real, portable signal).
#
# What it measures:
#   1. Per-package Ca / Ce / instability I = Ce/(Ca+Ce)         (fitness D-01..D-03) [JVM only]
#   2. SDP violations (Stable Dependencies Principle breaks)     [JVM only]
#   3. Balanced Coupling top edges: strength(import count) x volatility(depended-on changes) [JVM]
#   4. Co-change pairs: different packages changed together frequently in one commit
#      (hidden coupling not visible in imports; signal threshold 5+)              [any stack]
#
# Deps: git / awk only (no compile, runs everywhere).
#
# Config (optional, from harness.config.sh in the consumer repo root, or env):
#   COUPLING_LANG         — import extractor: java|python|go|typescript|rust (default: "java")
#   COUPLING_SRC          — source root scanned (default: "src/main/java")
#   COUPLING_PKG_PREFIX   — java: internal root package / go: go.mod module path (REQUIRED for those)
#   COUPLING_FILE_GLOB    — find -name pattern for source files (default: "*.java")
#   COUPLING_SINCE_DAYS   — volatility / co-change window in days (default: 90)
#   COUPLING_COCHANGE_MIN — co-change pair signal threshold (default: 5)
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"

OUT="$ROOT/build/quality"
SRC="${COUPLING_SRC:-src/main/java}"
LANG_MODE="${COUPLING_LANG:-java}"
case "$LANG_MODE" in java|python|go|typescript|rust) ;; *)
  echo "measure-coupling: unknown COUPLING_LANG='$LANG_MODE' (java|python|go|typescript|rust)" >&2; exit 2 ;;
esac
PKG_PREFIX="${COUPLING_PKG_PREFIX:-}"
FILE_GLOB="${COUPLING_FILE_GLOB:-*.java}"
SINCE_DAYS="${COUPLING_SINCE_DAYS:-90}"
COCHANGE_MIN="${COUPLING_COCHANGE_MIN:-5}"
mkdir -p "$OUT"
cd "$ROOT"

if [ ! -d "$SRC" ]; then
  echo "measure-coupling: source root not found: $SRC (set COUPLING_SRC)" >&2
  exit 1
fi

echo "==================== coupling ($SRC / volatility window ${SINCE_DAYS}d) ===================="
echo ""

# --- 1. import-based "file -> module" dependency edges (COUPLING_LANG) ---
# Output: src_mod \t dst_mod \t src_file (internal modules only, self-module excluded).
: > "$OUT/edges.tsv"
EXT="${FILE_GLOB##*.}"

# dirmod <file>: SRC 相対の親ディレクトリを dot モジュール名に（SRC 直下は "root"）。
dirmod() {
  dm="$(dirname -- "$1")"; dm="${dm#"${SRC%/}"}"; dm="${dm#/}"
  if [ -n "$dm" ]; then printf '%s' "$dm" | tr '/' '.'; else printf 'root'; fi
}
# resolvemod <dotted>: $SRC 配下で dir ならそのまま、ファイル(.EXT)なら親 dir、外部なら空。
resolvemod() {
  rm_rel="$(printf '%s' "$1" | tr '.' '/')"
  if [ -d "$SRC/$rm_rel" ]; then printf '%s' "$1"
  elif [ -e "$SRC/$rm_rel.$EXT" ]; then
    rm_d="$(dirname -- "$rm_rel")"
    if [ "$rm_d" = "." ]; then printf 'root'; else printf '%s' "$rm_d" | tr '/' '.'; fi
  fi
}
# normpath <path>: ./ と ../ を畳む（typescript の相対 import 解決用）。
normpath() {
  printf '%s' "$1" | awk -F/ '{ n=0
    for (i=1; i<=NF; i++) { if ($i=="." || $i=="") continue
      if ($i=="..") { if (n>0) n--; continue } ; p[++n]=$i }
    s=""; for (i=1; i<=n; i++) s = s (i>1 ? "/" : "") p[i]; print s }'
}
# 外部 import（dst 空）や自己エッジは黙って捨てる。&& 連鎖だと除外時に非ゼロを返し
# set -e がループごと落とすため、必ず if 文で（return 0 を保証）。
emit_edge() {
  if [ -n "$2" ] && [ "$2" != "$1" ]; then
    printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$OUT/edges.tsv"
  fi
}

if { [ "$LANG_MODE" = "java" ] || [ "$LANG_MODE" = "go" ]; } && [ -z "$PKG_PREFIX" ]; then
  echo "(COUPLING_PKG_PREFIX not set: skipping import-based Ca/Ce/I/SDP/Balanced sections;"
  echo " reporting co-change coupling only — see header LANGUAGES.)"
  echo ""
else
  case "$LANG_MODE" in
    java)
      esc_prefix=$(printf '%s' "$PKG_PREFIX" | sed 's/\./\\./g')
      find "$SRC" -name "$FILE_GLOB" -type f | while read -r f; do
        pkg=$(sed -n 's/^package \([a-zA-Z0-9_.]*\);/\1/p' "$f" | head -1)
        sed -n "s/^import $esc_prefix\\.\\([a-zA-Z0-9_.]*\\)\\.[A-Z][A-Za-z0-9_]*;/\\1/p" "$f" \
          | sort -u | while read -r dst; do
              emit_edge "$pkg" "$PKG_PREFIX.$dst" "$f"
            done
      done ;;
    python)
      find "$SRC" -name "$FILE_GLOB" -type f | while read -r f; do
        src="$(dirmod "$f")"
        sed -n 's/^from \([a-zA-Z0-9_.]*\) import .*/\1/p; s/^import \([a-zA-Z0-9_.]*\).*/\1/p' "$f" \
          | sort -u | while read -r imp; do
              emit_edge "$src" "$(resolvemod "$imp")" "$f"
            done
      done ;;
    go)
      find "$SRC" -name "$FILE_GLOB" -type f | while read -r f; do
        src="$(dirmod "$f")"
        grep -o "\"$PKG_PREFIX/[^\"]*\"" "$f" 2>/dev/null \
          | sed "s|^\"$PKG_PREFIX/||; s|\"$||" | sort -u | while read -r rel; do
              [ -d "$SRC/$rel" ] || continue           # 内部パッケージ（dir 実在）のみ
              emit_edge "$src" "$(printf '%s' "$rel" | tr '/' '.')" "$f"
            done
      done ;;
    typescript)
      find "$SRC" -name "$FILE_GLOB" -type f | while read -r f; do
        src="$(dirmod "$f")"
        fdir="$(dirname -- "$f")"; fdir="${fdir#"${SRC%/}"}"; fdir="${fdir#/}"
        sed -n "s/.*from ['\"]\(\.\.*\/[^'\"]*\)['\"].*/\1/p" "$f" | sort -u | while read -r imp; do
            np="$(normpath "$fdir/$imp")"
            emit_edge "$src" "$(resolvemod "$(printf '%s' "$np" | tr '/' '.')")" "$f"
          done
      done ;;
    rust)
      find "$SRC" -name "$FILE_GLOB" -type f | while read -r f; do
        src="$(dirmod "$f")"
        grep -o 'use crate::[A-Za-z0-9_:]*' "$f" 2>/dev/null | sed 's/^use crate:://' \
          | sort -u | while read -r path; do
              # 先頭から小文字 snake_case セグメントだけをモジュールパスとして採る（型名で打ち切り）
              mod="$(printf '%s' "$path" | awk -F'::' '{ s=""
                for (i=1; i<=NF; i++) { if ($i !~ /^[a-z_][a-z0-9_]*$/) break
                  s = s (i>1 ? "." : "") $i } ; print s }')"
              [ -n "$mod" ] || continue
              emit_edge "$src" "$(resolvemod "$mod")" "$f"
            done
      done ;;
  esac
fi

# Helper: strip the source root prefix from a path (handles configurable SRC, not just src/main/java).
src_strip="${SRC%/}/"

# --- 2. volatility: per-package change count over the last SINCE_DAYS ---
git log --since="$SINCE_DAYS days ago" --name-only --pretty=format: -- "$SRC" 2>/dev/null \
  | grep "\\.${FILE_GLOB##*.}\$" \
  | sed "s|/[^/]*\\.${FILE_GLOB##*.}\$||; s|^${src_strip}||; s|/|.|g" \
  | sort | uniq -c | awk '{print $2 "\t" $1}' > "$OUT/volatility.tsv"

# --- 3. Ca / Ce / I + SDP + Balanced top edges (only when edges exist) ---
if [ -s "$OUT/edges.tsv" ]; then
  awk -F'\t' -v vol_file="$OUT/volatility.tsv" '
    BEGIN {
      while ((getline line < vol_file) > 0) {
        split(line, vparts, "\t"); vol[vparts[1]] = vparts[2]
      }
    }
    {
      src = $1; dst = $2
      strength[src "\t" dst]++
      pkgs[src] = 1; pkgs[dst] = 1
    }
    END {
      for (e in strength) {
        split(e, p, "\t")
        if (!(e in counted)) { ce[p[1]]++; ca[p[2]]++; counted[e] = 1 }
      }
      printf "--- per-package Ca(afferent) / Ce(efferent) / instability I / changes ---\n"
      printf "%-44s %4s %4s %6s %6s\n", "package", "Ca", "Ce", "I", "chg"
      for (k in pkgs) {
        af = ca[k] + 0; ef = ce[k] + 0
        i = (af + ef > 0) ? ef / (af + ef) : 0
        printf "%-44s %4d %4d %6.2f %6d\n", k, af, ef, i, vol[k] + 0
        inst[k] = i
      }
      printf "\n--- SDP violations (depending on a MORE unstable package) ---\n"
      sdp = 0
      for (e in strength) {
        split(e, p, "\t")
        if (inst[p[2]] > inst[p[1]] + 0.05) {
          printf "  %s (I=%.2f) -> %s (I=%.2f)  strength %d\n", p[1], inst[p[1]], p[2], inst[p[2]], strength[e]
          sdp++
        }
      }
      if (sdp == 0) printf "  none (dependencies point toward the stable side)\n"
      printf "\n--- Balanced Coupling top edges (load = strength x depended-on volatility) ---\n"
      printf "    the more you strongly depend on something that changes often, the costlier each change\n"
      printf "%-7s %-5s %-5s %s\n", "load", "str", "vol", "edge"
      n = 0
      for (e in strength) {
        split(e, p, "\t")
        load[e] = strength[e] * (vol[p[2]] + 0)
      }
      while (n < 8) {
        best = ""; bv = -1
        for (e in load) if (!(e in done) && load[e] > bv) { bv = load[e]; best = e }
        if (best == "" || bv <= 0) break
        split(best, p, "\t")
        printf "%-7d %-5d %-5d %s -> %s\n", bv, strength[best], vol[p[2]] + 0, p[1], p[2]
        done[best] = 1; n++
      }
    }
  ' "$OUT/edges.tsv"
  echo ""
fi

# --- 4. co-change pairs (temporal coupling not visible in imports; any stack) ---
echo "--- co-change pairs (different packages, same commit, >= ${COCHANGE_MIN} times) ---"
echo "    co-changes with no (or reversed) static dependency mean hidden coupling or scattered responsibility"
git log --since="$SINCE_DAYS days ago" --name-only --pretty=format:"@@@" -- "$SRC" 2>/dev/null \
  | awk -v min="$COCHANGE_MIN" -v strip="$src_strip" -v ext="${FILE_GLOB##*.}" '
    BEGIN { extpat = "\\." ext "$" }
    /^@@@$/ { delete files; nf = 0; next }
    $0 ~ extpat {
      sub("^" strip, ""); sub(extpat, "")
      nf++; files[nf] = $0
      for (i = 1; i < nf; i++) {
        a = files[i]; b = files[nf]
        pa = a; pb = b; sub(/\/[^\/]*$/, "", pa); sub(/\/[^\/]*$/, "", pb)
        if (pa != pb) {
          pair = (a < b) ? a "\t" b : b "\t" a
          count[pair]++
        }
      }
    }
    END {
      shown = 0
      while (shown < 10) {
        best = ""; bv = min - 1
        for (p in count) if (!(p in done) && count[p] > bv) { bv = count[p]; best = p }
        if (best == "") break
        split(best, q, "\t")
        na = split(q[1], s1, "/"); nb = split(q[2], s2, "/")
        printf "  %2d  %s <=> %s\n", bv, s1[na], s2[nb]
        done[best] = 1; shown++
      }
      if (shown == 0) printf "  none (no pair reached the %d-times threshold)\n", min
    }'
echo ""
echo "detail: $OUT/edges.tsv (all edges) / $OUT/volatility.tsv"
echo "measure-coupling done (advisory)"
exit 0
