#!/bin/sh
# [汎用core] ゲート発火実績・CIコストの集計 — スタック非依存
# Second-order harness measurement (ROADMAP P4, ROI procedure ① and ②). The ROI
# evaluation needs evidence, not sentiment: for each gate, how often did it run, how
# often did it FIRE (fail = caught something / blocked a violation), and what does it
# cost in CI seconds. This script turns a repo's CI run history into that evidence so
# the gatecrate-evaluate skill can apply the two-axis verdicts mechanically.
#
# The probe side (survival proof of prevention gates) is already shipped as
# core/scripts/probe-gate-liveness.sh — this is the COMPLEMENT: detection-layer firing
# and continuous CI cost (procedure ① and ②), which the probe cannot supply.
#
# Design — two layers, so the judgement core is deterministic and testable:
#   fetch  (--fetch)     : calls `gh` against live GitHub. Non-deterministic (network),
#                          NOT unit-tested. Emits normalized records to stdout:
#                              <gate>\t<conclusion>\t<seconds|NA>
#                          one line per (run, job, step). gate = the CI step name.
#   aggregate (--aggregate): reads those records from stdin and emits the per-gate
#                          report. Pure POSIX awk, no network — this is the part the
#                          behavior test pins (tests/test-collect-gate-history.sh).
#   default              : fetch then aggregate (the operator-facing path). A FAILED fetch is
#                          propagated (non-zero exit), never hidden as an empty TSV — so a missing/
#                          unauthed gh reads as UNCONFIRMED, not as valid empty history.
#
# Report (TSV, one row per gate, header included):
#   gate  runs  fires  fire_rate  total_seconds  avg_seconds
#     runs   = executions with a success/failure conclusion (skipped/cancelled excluded)
#     fires  = executions that failed. For DETECTION layers a healthy non-zero number
#              means "it catches real defects". For PREVENTION layers ~0 is normal —
#              read it together with the liveness probe, never alone (counterfactual
#              trap: "never fired = useless" deletes your most important gates).
#
# Logical gate grouping (--group-map <file>, optional):
#   By default `gate` is the raw CI step name, so the report mixes real quality gates
#   (Run mutation tests, …) with setup steps (Checkout, Set up Java, …) and dilutes the
#   ROI signal. A map file relabels step names into LOGICAL gates BEFORE counting, so the
#   evaluator reasons about `mutation` / `gradle-build` / `pr-title` instead of every step.
#   Map format: a TSV of  <step_pattern>\t<logical_gate>  (further columns ignored), where
#   step_pattern is a glob (only `*` wildcard; matched against the whole step name). Blank
#   lines and `#` comments are skipped; rules are tried top-to-bottom, FIRST match wins.
#   Grouping lives in the aggregate layer (pure, deterministic, tested) — the record format
#   is unchanged, so a map can match the step name only (not workflow/job). UNMAPPED steps
#   keep their raw name (preserved as their own rows), so nothing is hidden and a consumer
#   can grow a small map incrementally. Example map:
#     Run mutation tests	mutation
#     Build Gradle debug variants*	gradle-build
#     Check documentation currency*	docs-currency
#     Validate pull request title	pr-title
#
# Usage:
#   collect-gate-history.sh [--workflow <file>] [--limit <n>] [--repo <owner/name>] [--group-map <file>]
#   collect-gate-history.sh --fetch     [--workflow ...] [--limit ...] [--repo ...]
#   collect-gate-history.sh --aggregate [--group-map <file>] < records.tsv
set -eu

WORKFLOW=""
LIMIT="50"
REPO=""
GROUP_MAP=""

usage() {
  sed -n '2,52p' "$0" | sed 's/^# \{0,1\}//'
}

# ---- aggregate layer: stdin TSV -> per-gate report (pure, deterministic, tested) ----
# Input  : <gate>\t<conclusion>\t<seconds|NA>   (blank/short lines ignored)
# Output : gate  runs  fires  fire_rate  total_seconds  avg_seconds
# With --group-map, raw step names ($1) are relabeled to logical gates before counting.
aggregate() {
  if [ -n "$GROUP_MAP" ] && [ ! -r "$GROUP_MAP" ]; then
    echo "collect-gate-history: --group-map file not found/readable: $GROUP_MAP" >&2
    return 2
  fi
  awk -F '\t' -v mapfile="$GROUP_MAP" '
    # glob (only the * wildcard) -> anchored ERE; every other ERE metachar is escaped so
    # a step name like "Set up Java (1.8)" cannot inject regex via the map file.
    function glob2re(g,   i, n, c, re) {
      re = "^"; n = length(g)
      for (i = 1; i <= n; i++) {
        c = substr(g, i, 1)
        if (c == "*") { re = re ".*" }
        else if (index("\\.[](){}+?|^$", c) > 0) { re = re "\\" c }
        else { re = re c }
      }
      return re "$"
    }
    # raw step name -> logical gate (FIRST matching rule wins). Unmapped names are kept
    # as-is, so leftover/setup steps stay visible as their own rows instead of vanishing.
    function resolve(name,   k) {
      for (k = 0; k < ng; k++) if (name ~ gre[k]) return glab[k]
      return name
    }
    BEGIN {
      ng = 0
      if (mapfile != "") {
        while ((getline line < mapfile) > 0) {
          sub(/\r$/, "", line)                       # tolerate CRLF map files
          if (line ~ /^[ \t]*#/ || line ~ /^[ \t]*$/) continue
          ti = index(line, "\t"); if (ti == 0) continue
          pat = substr(line, 1, ti - 1)
          rest = substr(line, ti + 1)                # 2nd column up to the next tab
          tj = index(rest, "\t")
          lab = (tj > 0 ? substr(rest, 1, tj - 1) : rest)
          if (pat == "" || lab == "") continue
          gre[ng] = glob2re(pat); glab[ng] = lab; ng++
        }
        close(mapfile)
      }
    }
    NF < 2 { next }
    {
      gate = (ng > 0 ? resolve($1) : $1); concl = $2; secs = (NF >= 3 ? $3 : "NA")
      seen[gate] = 1
      # Only success/failure are "executions". skipped/cancelled/null do not count
      # toward the rate denominator, so a skipped gate does not look like a pass.
      if (concl == "success" || concl == "failure") {
        runs[gate]++
        if (concl == "failure") fires[gate]++
        if (secs ~ /^[0-9]+([.][0-9]+)?$/) { tot[gate] += secs; nsec[gate]++ }
      }
    }
    END {
      print "gate\truns\tfires\tfire_rate\ttotal_seconds\tavg_seconds"
      n = 0
      for (g in seen) order[n++] = g
      # insertion-free selection sort: keep output stable across awk implementations
      for (i = 0; i < n; i++)
        for (j = i + 1; j < n; j++)
          if (order[j] < order[i]) { t = order[i]; order[i] = order[j]; order[j] = t }
      for (i = 0; i < n; i++) {
        g = order[i]; r = runs[g] + 0; f = fires[g] + 0
        rate = (r > 0) ? f / r : 0
        total = tot[g] + 0
        avg = (nsec[g] > 0) ? total / nsec[g] : 0
        printf "%s\t%d\t%d\t%.3f\t%.1f\t%.1f\n", g, r, f, rate, total, avg
      }
    }
  '
}

# ---- fetch layer: GitHub CI history -> normalized records (needs gh; non-deterministic) ----
fetch() {
  command -v gh >/dev/null 2>&1 || {
    echo "collect-gate-history: 'gh' (GitHub CLI) is required for --fetch" >&2
    echo "  install it, run 'gh auth login', or feed records via --aggregate." >&2
    return 2
  }
  # Propagate gh failures EXPLICITLY (a bare `var="$(gh …)"` would not: `set -e` is disabled when
  # fetch runs inside `if fetch`, so an unauthed gh would otherwise let fetch finish and return 0).
  repo="$REPO"
  if [ -z "$repo" ]; then
    repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)" \
      || { echo "collect-gate-history: 'gh repo view' failed (unauthenticated? wrong host?)." >&2; return 3; }
  fi

  # Recent runs (optionally a single workflow). databaseId identifies each run.
  if [ -n "$WORKFLOW" ]; then
    ids="$(gh run list --repo "$repo" --workflow "$WORKFLOW" --limit "$LIMIT" \
      --json databaseId --jq '.[].databaseId')" \
      || { echo "collect-gate-history: 'gh run list' failed." >&2; return 3; }
  else
    ids="$(gh run list --repo "$repo" --limit "$LIMIT" \
      --json databaseId --jq '.[].databaseId')" \
      || { echo "collect-gate-history: 'gh run list' failed." >&2; return 3; }
  fi

  # Per run, emit one record per step. Step duration is computed inside gh's jq engine
  # (gojq) via fromdateiso8601, so no portable shell date math is needed; steps without
  # timestamps emit NA (counted toward runs/fires but excluded from the seconds average).
  for id in $ids; do
    [ -n "$id" ] || continue
    gh api "repos/$repo/actions/runs/$id/jobs" --jq '
      .jobs[] | .steps[]? |
      [ .name,
        (.conclusion // "null"),
        (if (.started_at and .completed_at)
           then ((.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601))
           else "NA" end)
      ] | @tsv' 2>/dev/null || true
  done
}

# ---- argument handling ----
MODE="all"
while [ $# -gt 0 ]; do
  case "$1" in
    --fetch)     MODE="fetch" ;;
    --aggregate) MODE="aggregate" ;;
    --workflow)  WORKFLOW="${2:?--workflow needs a value}"; shift ;;
    --limit)     LIMIT="${2:?--limit needs a value}"; shift ;;
    --repo)      REPO="${2:?--repo needs a value}"; shift ;;
    --group-map) GROUP_MAP="${2:?--group-map needs a value}"; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "collect-gate-history: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

case "$MODE" in
  aggregate) aggregate ;;
  fetch)     fetch ;;
  all)
    # Do NOT `fetch | aggregate`: a pipeline's status is the LAST command's, so a failed fetch
    # (no/unauthed gh, network error) would be hidden behind aggregate's exit 0 and emit just the
    # TSV header — making "fetch failed" look like "valid empty history". Capture fetch's status
    # first and propagate it, so a caller (e.g. the evaluator) records UNCONFIRMED, not empty.
    records="$(mktemp)"
    if fetch > "$records"; then
      aggregate < "$records"
      rm -f "$records"
    else
      rc=$?
      rm -f "$records"
      echo "collect-gate-history: fetch failed (rc=$rc) — gh missing/unauthenticated or the API errored." >&2
      echo "  The firing/cost history is UNCONFIRMED, not empty. Authenticate gh, or use --aggregate with records." >&2
      exit "$rc"
    fi
    ;;
esac
