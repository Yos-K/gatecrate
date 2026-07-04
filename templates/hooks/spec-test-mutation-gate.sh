#!/bin/sh
# Claude Code **Stop hook** — mechanically enforce the survivor-strict mutation gate after a cc-sdd
# spec-impl / validate-impl. This is the MECHANICAL backing for the prompt-level gatecrate steering:
# once the phase is "armed", the agent CANNOT stop while a mutant survives — this hook blocks the stop
# (exit 2) and feeds the survivors back until the gate is clean. "green tests" can no longer end the
# phase; an adequately-tested spec can.
#
# Trigger (scoped — never runs on unrelated stops): only when `.kiro/.gatecrate-mutation-pending`
# exists. The gatecrate steering creates it during validate-impl (`touch` in a Bash step). Absent ->
# no-op, exit 0.
#
# Loop guard (REQUIRED — a blocked Stop re-fires after the agent revises): a per-session counter caps
# consecutive blocks (SPEC_TEST_MUTATION_MAX_BLOCKS, default 3). At the cap it does NOT silently pass:
# it is "3 blocks then ESCALATE", not "un-bypassable". It writes a visible escalation record
# (.kiro/.gatecrate-mutation-escalated, with the survivors) and allows the stop — but the first-order
# CI gate `check-mutation-escalation.sh` then fails the PR until a human clears it. So a local bypass is
# multi-layer-defended: logged here, blocked in CI. The loop can never run forever; the bypass is never invisible.
#
# Install: copy to `.claude/hooks/spec-test-mutation-gate.sh` and register the Stop hook (see
# templates/hooks/settings-stop-hook.json). Configure the gate via harness.config.sh:
#   SPEC_TEST_MUTATION_CMD  — the survivor-strict mutation command (default: sh scripts/run-mutation.sh)
#   SPEC_TEST_MUTATION_MAX_BLOCKS — consecutive-block cap before force-through (default 3)
set -u

payload="$(cat)"   # Stop-hook JSON arrives on stdin
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" 2>/dev/null || exit 0

MARKER="$ROOT/.kiro/.gatecrate-mutation-pending"
[ -f "$MARKER" ] || exit 0          # not armed -> no-op

# session_id for the loop guard (sed, so no jq/python dependency). Fallback keeps the guard working.
sid="$(printf '%s' "$payload" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[ -n "$sid" ] || sid="nosession"
COUNTER="${TMPDIR:-/tmp}/gatecrate_mutation_block_${sid}.count"

# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
GATE="${SPEC_TEST_MUTATION_CMD:-sh scripts/run-mutation.sh}"
MAX_BLOCKS="${SPEC_TEST_MUTATION_MAX_BLOCKS:-3}"

ESCALATED="$ROOT/.kiro/.gatecrate-mutation-escalated"
count="$(cat "$COUNTER" 2>/dev/null || echo 0)"

out="$(sh -c "$GATE" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  rm -f "$MARKER" "$COUNTER" "$ESCALATED"   # adequately tested — clean stop; clear any prior escalation
  exit 0
fi

count=$((count + 1))
echo "$count" > "$COUNTER"

if [ "$count" -ge "$MAX_BLOCKS" ]; then
  # Cap reached: do NOT silently pass. Write a VISIBLE escalation record, then allow the stop so the
  # loop can't run forever. check-mutation-escalation.sh blocks the PR until a human kills the survivors
  # and deletes the record.
  {
    echo "gatecrate mutation escalation — force-passed after ${count} consecutive Stop-hook blocks"
    echo "(SPEC_TEST_MUTATION_MAX_BLOCKS=${MAX_BLOCKS}). Surviving mutants were NOT killed; the spec is"
    echo "not adequately tested. A human must kill them (do not lower the floor) and delete this file."
    echo "Gate: $GATE"
    echo "--- last survivors ---"
    printf '%s\n' "$out" | tail -40
  } > "$ESCALATED"
  # Force-stage the record so it reaches CI even when the consumer gitignores .kiro/ (a file under an
  # ignored directory cannot be re-included by a .gitignore negation, so `git add -A` would silently
  # drop it — then the CI gate would never see the bypass). `git add -f` overrides the ignore; the
  # record then travels with the next commit. Without this the local bypass is invisible to CI.
  git add -f "$ESCALATED" >/dev/null 2>&1 || true
  rm -f "$MARKER" "$COUNTER"
  echo "gatecrate: survivors unresolved after ${count} blocks — wrote (and force-staged) $ESCALATED." >&2
  echo "  Commit it; the CI gate check-mutation-escalation.sh fails the PR until a human clears it" >&2
  echo "  (bypass logged, not silent — even if .kiro/ is gitignored)." >&2
  exit 0
fi

{
  echo "gatecrate: survivor-strict mutation gate FAILED after validate-impl — green tests survived a"
  echo "mutation, so the spec is NOT adequately tested. Add the focused test(s) that KILL the survivors"
  echo "(do not lower the floor or exclude a killable mutant), then let the phase re-run. Survivors:"
  printf '%s\n' "$out" | tail -40
} >&2
exit 2                               # block the stop; stderr is fed back to the model
