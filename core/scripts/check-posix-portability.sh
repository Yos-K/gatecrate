#!/bin/sh
# [汎用core] POSIX 移植性ゲート — 出荷スクリプトが POSIX sh で動くことを保証する
# gatecrate's scripts are POSIX `sh`, so they run the same from bash and zsh, from fish (which still
# EXECUTES them via the `#!/bin/sh` shebang), and on Windows via Git Bash / WSL. The user's
# interactive shell does not matter for an executed script — the shebang picks `/bin/sh`. This gate
# keeps that true by failing on the two ways a bashism sneaks in:
#   1. a non-`#!/bin/sh` shebang (a `#!/bin/bash` line would make shellcheck lint in bash dialect, so
#      bashisms would pass silently). Sourced files declaring `# shellcheck shell=sh` are exempt.
#   2. shellcheck SC3xxx — a construct UNDEFINED in POSIX sh (arrays, `[[ ]]`, `echo -e`, …).
# `sh -n` (dash on CI) already catches non-POSIX *syntax*; this adds the *semantic* bashisms and the
# shebang guard. shellcheck is needed for check 2; if absent, check 1 still runs (and says so).
#
# Scope: every tracked `*.sh` plus install.sh. Override with POSIX_CHECK_PATHS (space-separated).
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd))"
cd "$ROOT"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"

# File set: explicit override, else all tracked shell scripts.
if [ -n "${POSIX_CHECK_PATHS:-}" ]; then
  files="$POSIX_CHECK_PATHS"
else
  files="$(git ls-files '*.sh' 2>/dev/null || true)"
fi
[ -n "$files" ] || { echo "posix-portability: no shell scripts to check."; exit 0; }

status=0

# ---- check 1: shebang must be #!/bin/sh (sourced sh-declared files exempt) ----
for f in $files; do
  [ -f "$f" ] || continue
  first="$(head -1 "$f")"
  case "$first" in
    '#!/bin/sh') ;;  # the ONLY allowed executable shebang — exact, no args (a `#!/bin/sh -x` or a
                     # CRLF-terminated line behaves differently across platforms) and no other interpreter
    '#!'*) echo "NON-POSIX shebang: $f -> '$first' (use exactly '#!/bin/sh', no arguments)" >&2; status=1 ;;
    *) grep -q 'shellcheck shell=sh' "$f" || { echo "NO shebang and not an sh-declared sourced file: $f" >&2; status=1; } ;;
  esac
done

# ---- check 2: shellcheck SC3xxx (POSIX-undefined constructs = bashisms) ----
if command -v shellcheck >/dev/null 2>&1; then
  # shellcheck disable=SC2086  # $files is a controlled list of paths, intentional split
  out="$(shellcheck --shell=sh -S style $files 2>&1 || true)"
  bashisms="$(printf '%s\n' "$out" | grep -E 'SC3[0-9]{3}' || true)"
  if [ -n "$bashisms" ]; then
    echo "Non-POSIX (bashism) constructs detected — scripts must run under any POSIX sh (dash):" >&2
    printf '%s\n' "$out" | grep -B3 -E 'SC3[0-9]{3}' >&2
    status=1
  fi
else
  echo "posix-portability: shellcheck not found — ran the shebang check only (install shellcheck for the bashism check)."
fi

# ---- check 3: no predictable PID-suffixed temp paths (use mktemp) ----
# A /tmp path whose name ends in the shell PID is a symlink-attack / collision risk; mktemp is the
# portable fix (this is the structural promotion of a one-off cleanup, so the mistake cannot recur).
# Match a /tmp path starting with an alnum char and ending in two PID markers; skip comment lines so a
# doc mention is not flagged (and the leading-alnum rule keeps a "/tmp/...<pid>" prose ellipsis out).
# shellcheck disable=SC2086
# grep -n prints "file:line:content" for many files but "line:content" for one, so the optional
# "(file:)" keeps the comment-line exclusion working in both shapes.
predictable="$(grep -nE '/tmp/[A-Za-z0-9][^[:space:]]*[$][$]' $files 2>/dev/null \
  | grep -vE '^([^:]+:)?[0-9]+:[[:space:]]*#' || true)"
if [ -n "$predictable" ]; then
  echo "Predictable temp path — use mktemp, never a PID-suffixed /tmp name (symlink/collision risk):" >&2
  printf '%s\n' "$predictable" >&2
  status=1
fi

if [ "$status" -ne 0 ]; then
  echo "POSIX portability check FAILED: a script would not run under a strict POSIX sh." >&2
  echo "Keep scripts POSIX so they work from bash/zsh/fish and on Windows Git Bash/WSL." >&2
  exit 1
fi
echo "POSIX portability check passed: all scripts are #!/bin/sh with no bashisms."
