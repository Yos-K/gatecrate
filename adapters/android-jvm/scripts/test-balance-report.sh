#!/bin/sh
# [Android-JVMアダプタ] テストバランスレポート（small/medium/large比率）
# Tallies tests by Google test SIZE and reports ratios against target bands.
#
# Optional env vars:
#   SMALL_MIN / SMALL_MAX   — target band % for small tests (default: 70/90)
#   MEDIUM_MIN / MEDIUM_MAX — target band % for medium tests (default: 10/25)
#   LARGE_MIN / LARGE_MAX   — target band % for large tests (default: 1/10)
#
# Usage:
#   sh scripts/test-balance-report.sh           # report only (exit 0)
#   sh scripts/test-balance-report.sh --strict   # exit 1 if small/medium drift
set -u

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
cd "$ROOT"

STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1

SMALL_MIN="${SMALL_MIN:-70}"; SMALL_MAX="${SMALL_MAX:-90}"
MEDIUM_MIN="${MEDIUM_MIN:-10}"; MEDIUM_MAX="${MEDIUM_MAX:-25}"
LARGE_MIN="${LARGE_MIN:-1}"; LARGE_MAX="${LARGE_MAX:-10}"

# Size heuristic (by what a test is allowed to touch):
#   - small : JVM unit test with no Android framework and no I/O.
#   - medium: JVM test that uses Robolectric or filesystem / sleep (single
#             machine, no real device).
#   - large : instrumented test (src/androidTest) or the emulator smoke ladder.
#
# For `large`, presence and pre-release execution matter more than the exact
# ratio, so the smoke ladder is reported as a presence signal in addition to
# any instrumented test count.
MEDIUM_MARKERS='org\.robolectric|RuntimeEnvironment|java\.io\.File|java\.nio\.file|@TempDir|Thread\.sleep'

# src/test/java: small tests (pure JVM). JUnit (*Test.java) and PBT (*Property.java) both count.
# A class here is medium only if it touches Robolectric / filesystem / sleep.
small=0
medium=0
for f in $(find src/test \( -name '*Test.java' -o -name '*Property.java' \) 2>/dev/null); do
  if grep -Eq "$MEDIUM_MARKERS" "$f"; then
    medium=$((medium + 1))
  else
    small=$((small + 1))
  fi
done

# src/testMedium/java: medium tests by location (Robolectric / Android on JVM; Gradle only).
medium=$((medium + $(find src/testMedium \( -name '*Test.java' -o -name '*Property.java' \) 2>/dev/null | wc -l | tr -d ' ')))

# large: instrumented test classes plus the smoke ladder presence.
large=$(find src/androidTest \( -name '*Test.java' -o -name '*Property.java' \) 2>/dev/null | wc -l | tr -d ' ')
smoke="absent"
[ -f .github/workflows/device-smoke.yml ] && smoke="present (manual / pre-release)"

total=$((small + medium + large))
if [ "$total" -eq 0 ]; then
  echo "test-balance: no tests found." >&2
  exit 0
fi

pct() { echo $(( $1 * 100 / total )); }
band() { # band <pct> <min> <max>  -> ok | LOW | HIGH
  if [ "$1" -lt "$2" ]; then echo LOW; elif [ "$1" -gt "$3" ]; then echo HIGH; else echo ok; fi
}

sp=$(pct "$small"); mp=$(pct "$medium"); lp=$(pct "$large")
ss=$(band "$sp" "$SMALL_MIN" "$SMALL_MAX")
ms=$(band "$mp" "$MEDIUM_MIN" "$MEDIUM_MAX")
ls=$(band "$lp" "$LARGE_MIN" "$LARGE_MAX")

echo "Test balance (by size; ratios, not counts):"
printf '  small   %3d%%  target %d-%d%%   [%s]\n' "$sp" "$SMALL_MIN" "$SMALL_MAX" "$ss"
printf '  medium  %3d%%  target %d-%d%%   [%s]\n' "$mp" "$MEDIUM_MIN" "$MEDIUM_MAX" "$ms"
printf '  large   %3d%%  target %d-%d%%   [%s]\n' "$lp" "$LARGE_MIN" "$LARGE_MAX" "$ls"
echo "  e2e smoke ladder: $smoke  (large counts less than presence + pre-release run)"
echo "  (heuristic over $total test classes)"

drift=0
[ "$ss" = ok ] || drift=1
[ "$ms" = ok ] || drift=1
if [ "$drift" -eq 1 ]; then
  echo "test-balance: small/medium ratio is outside the target band." >&2
  [ "$STRICT" -eq 1 ] && exit 1
fi
exit 0
