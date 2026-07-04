#!/bin/sh
# [汎用core] measure-complexity.sh — per-method complexity measurement (ADVISORY, not a gate)
# gatecrate-type: advisory  (フィットネス信号を出す・既定は非ブロック、--strict で gate；価値=信号が消費されるか)
#
# WHY: an AI agent's cost to change code scales with the number of branch combinations it must
# reason about (cyclomatic complexity) and the structural load it must hold in mind to read the
# code (cognitive complexity). The DIFFERENCE (cognitive − cyclomatic) is a proxy for accidental
# complexity — structural noise that extract-refactors can remove without changing behavior
# (essential branches show up in both metrics; nesting/flow-breaks inflate only cognitive).
# Duplication (CPD) is pure accidental complexity, so it is measured alongside.
# Thresholds and interpretation: docs/code-quality-metrics.md.
#
# STACK ASSUMPTION: this measures Java sources via PMD. PMD's CyclomaticComplexity and
# CognitiveComplexity (SonarSource definition) rules drive the numbers, so the project must be
# Java (or another language PMD supports — set COMPLEXITY_LANG). For non-PMD stacks this script
# does not apply; use a language-native complexity tool instead.
#
# Usage:
#   sh core/scripts/measure-complexity.sh            # print report (always exit 0)
#   sh core/scripts/measure-complexity.sh --strict   # exit 1 if any RED method exists
#
# PMD is taken from PATH if present; otherwise it is fetched from GitHub releases and cached
# under build/quality/lib (no SDK / build step required).
#
# Config (optional, from harness.config.sh in the consumer repo root, or env):
#   COMPLEXITY_PATHS   — space-separated source roots to scan (default: "src/main/java")
#   COMPLEXITY_LANG    — PMD language id for CPD (default: "java")
#   COMPLEXITY_RULESET — PMD ruleset path (default: scripts/quality/complexity-ruleset.xml,
#                        falling back to core/scripts/quality/complexity-ruleset.xml)
#   COMPLEXITY_CC_YELLOW / COMPLEXITY_CC_RED       — cyclomatic bands (default 10 / 20)
#   COMPLEXITY_COG_YELLOW / COMPLEXITY_COG_RED     — cognitive bands (default 15 / 25)
#   COMPLEXITY_CPD_MIN_TOKENS — CPD duplicate threshold in tokens (default 100)
#   PMD_VERSION        — PMD release to fetch when not on PATH (default 7.20.0)
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"

OUT="$ROOT/build/quality"
LIB="$OUT/lib"
SCAN_PATHS="${COMPLEXITY_PATHS:-src/main/java}"
LANG="${COMPLEXITY_LANG:-java}"
PMD_VERSION="${PMD_VERSION:-7.20.0}"
STRICT="${1:-}"
mkdir -p "$OUT" "$LIB"

# Ruleset: consumer override, else consumer scripts/, else kit core/scripts/.
if [ -n "${COMPLEXITY_RULESET:-}" ]; then
  RULESET="$COMPLEXITY_RULESET"
elif [ -f "$ROOT/scripts/quality/complexity-ruleset.xml" ]; then
  RULESET="$ROOT/scripts/quality/complexity-ruleset.xml"
else
  RULESET="$(dirname -- "$0")/quality/complexity-ruleset.xml"
fi

# Band thresholds (source: docs/code-quality-metrics.md).
CC_YELLOW="${COMPLEXITY_CC_YELLOW:-10}"   # GREEN <=10 / YELLOW 11-20 / RED >20 (fitness S-01)
CC_RED="${COMPLEXITY_CC_RED:-20}"
COG_YELLOW="${COMPLEXITY_COG_YELLOW:-15}" # GREEN <=15 / YELLOW 16-25 / RED >25 (Sonar default 15)
COG_RED="${COMPLEXITY_COG_RED:-25}"
CPD_MIN_TOKENS="${COMPLEXITY_CPD_MIN_TOKENS:-100}"

if [ ! -f "$RULESET" ]; then
  echo "measure-complexity: ruleset not found: $RULESET" >&2
  echo "Provide one via COMPLEXITY_RULESET, or add scripts/quality/complexity-ruleset.xml." >&2
  exit 1
fi

# Build a single source argument list; verify at least one path exists.
SRC_ARGS=""
found_src=0
for p in $SCAN_PATHS; do
  if [ -d "$ROOT/$p" ]; then
    SRC_ARGS="$SRC_ARGS $ROOT/$p"
    found_src=1
  fi
done
if [ "$found_src" -eq 0 ]; then
  echo "measure-complexity: no source paths found (COMPLEXITY_PATHS='$SCAN_PATHS')" >&2
  exit 1
fi

ensure_pmd() {
  if command -v pmd >/dev/null 2>&1; then
    PMD_BIN="pmd"
    return
  fi
  PMD_HOME="$LIB/pmd-bin-$PMD_VERSION"
  PMD_BIN="$PMD_HOME/bin/pmd"
  if [ ! -x "$PMD_BIN" ]; then
    echo "Downloading PMD $PMD_VERSION..."
    curl -sL "https://github.com/pmd/pmd/releases/download/pmd_releases%2F$PMD_VERSION/pmd-dist-$PMD_VERSION-bin.zip" \
      -o "$LIB/pmd.zip"
    unzip -q -o "$LIB/pmd.zip" -d "$LIB"
    rm -f "$LIB/pmd.zip"
  fi
}

ensure_pmd

# PMD exit codes: 0 = no violations, 4 = violations found (the measurement ruleset reports every
# method as a "violation", so 4 is normal). Anything else is a real execution error.
status=0
# shellcheck disable=SC2086  # SRC_ARGS is an intentional space-separated path list
"$PMD_BIN" check -d $SRC_ARGS -R "$RULESET" -f text --no-progress \
  > "$OUT/complexity-raw.txt" 2>"$OUT/pmd-errors.txt" || status=$?
if [ "$status" != "0" ] && [ "$status" != "4" ]; then
  echo "measure-complexity failed: PMD exited with $status" >&2
  cat "$OUT/pmd-errors.txt" >&2
  exit 1
fi

# Join CC and cognitive complexity on file:line into a TSV.
awk -F'\t' '
  /CyclomaticComplexity:/ {
    split($1, loc, ":"); key = loc[1] ":" loc[2]
    if (match($0, /complexity of [0-9]+/)) {
      cc[key] = substr($0, RSTART + 14, RLENGTH - 14)
    }
    if (match($0, /\047[^\047]+\047/)) {
      name[key] = substr($0, RSTART + 1, RLENGTH - 2)
    }
  }
  /CognitiveComplexity:/ {
    split($1, loc, ":"); key = loc[1] ":" loc[2]
    if (match($0, /complexity of [0-9]+/)) {
      cog[key] = substr($0, RSTART + 14, RLENGTH - 14)
    }
  }
  END {
    for (key in cc) {
      c = cc[key]; g = (key in cog) ? cog[key] : 0
      print key "\t" name[key] "\t" c "\t" g "\t" (g - c)
    }
  }
' "$OUT/complexity-raw.txt" | sort -t'	' -k4,4nr > "$OUT/methods.tsv"

total=$(wc -l < "$OUT/methods.tsv" | tr -d ' ')
if [ "$total" -eq 0 ]; then
  echo "measure-complexity failed: no methods parsed (PMD output format changed?)" >&2
  exit 1
fi

echo "==================== complexity ($SCAN_PATHS) ===================="
echo ""
echo "methods measured: $total"
echo ""

echo "--- band summary (cyclomatic CC / cognitive Cog) ---"
awk -F'\t' -v cy="$CC_YELLOW" -v cr="$CC_RED" -v gy="$COG_YELLOW" -v gr="$COG_RED" '
  { if ($3 <= cy) ccg++; else if ($3 <= cr) ccy++; else ccr++
    if ($4 <= gy) cgg++; else if ($4 <= gr) cgy++; else cgr++ }
  END {
    printf "CC : GREEN(<=%d) %d / YELLOW(%d-%d) %d / RED(>%d) %d\n", cy, ccg+0, cy+1, cr, ccy+0, cr, ccr+0
    printf "Cog: GREEN(<=%d) %d / YELLOW(%d-%d) %d / RED(>%d) %d\n", gy, cgg+0, gy+1, gr, cgy+0, gr, cgr+0
  }' "$OUT/methods.tsv"
echo ""

echo "--- top 15 by cognitive complexity (AI comprehension hotspots) ---"
printf '%-4s %-4s %-5s %s\n' "Cog" "CC" "diff" "method (location)"
head -15 "$OUT/methods.tsv" | awk -F'\t' '{
  n = split($1, p, "/"); printf "%-4s %-4s %-5s %s  (%s:%s)\n", $4, $3, $5, $2, p[n-1] "/" p[n], ""
}' | sed 's|:(.*)||'
echo ""

echo "--- accidental-complexity proxy: (cognitive − CC) top 10 ---"
echo "    bigger diff => complexity is nesting/structural noise, not domain branching"
echo "    (=> likely removable by behavior-preserving Extract Method etc.)"
printf '%-5s %-4s %-4s %s\n' "diff" "Cog" "CC" "method (file)"
sort -t'	' -k5,5nr "$OUT/methods.tsv" | head -10 | awk -F'\t' '{
  n = split($1, p, "/"); printf "%-5s %-4s %-4s %s  (%s)\n", $5, $4, $3, $2, p[n]
}'
echo ""

echo "--- duplication (CPD, >= ${CPD_MIN_TOKENS} tokens, pure accidental complexity) ---"
cpd_status=0
# shellcheck disable=SC2086
"$PMD_BIN" cpd --minimum-tokens "$CPD_MIN_TOKENS" --dir $SRC_ARGS --language "$LANG" \
  > "$OUT/cpd-raw.txt" 2>/dev/null || cpd_status=$?
if [ "$cpd_status" != "0" ] && [ "$cpd_status" != "4" ]; then
  echo "(CPD error: exit $cpd_status — skipped)"
else
  blocks=$(grep -c "^Found a " "$OUT/cpd-raw.txt" 2>/dev/null) || blocks=0
  dup_lines=$(awk '/^Found a /{ if (match($0, /[0-9]+ line/)) s += substr($0, RSTART, RLENGTH-5) } END { print s+0 }' "$OUT/cpd-raw.txt")
  echo "duplicate blocks: $blocks / duplicate lines (per occurrence): $dup_lines"
  grep -A2 "^Found a " "$OUT/cpd-raw.txt" | grep "Starting at line" | head -6 | sed 's/^/  /'
fi
echo ""
echo "detail: $OUT/methods.tsv (full TSV) / $OUT/cpd-raw.txt"

red_total=$(awk -F'\t' -v cr="$CC_RED" -v gr="$COG_RED" '$3 > cr || $4 > gr' "$OUT/methods.tsv" | wc -l | tr -d ' ')
if [ "$STRICT" = "--strict" ] && [ "$red_total" -gt 0 ]; then
  echo "measure-complexity --strict: $red_total RED method(s) found" >&2
  exit 1
fi
echo "measure-complexity done (RED: $red_total / advisory)"
exit 0
