#!/bin/sh
# [汎用core] ゲート生存証明プローブ — スタック非依存
# Second-order harness check (ROADMAP P4). A *prevention* gate (secrets / PR-title /
# file-size) is supposed to never fire in normal operation — but "never fires" looks
# identical whether the gate is working or has silently broken. This probe injects a
# synthetic violation into each gate and confirms the gate REJECTS it. It is the
# survival proof for prevention layers — the harness analogue of mutation testing
# (deliberately inject a fault and check that the guard catches it).
#
#   ALIVE  the gate rejected the injected violation (it is enforcing)
#   DEAD   the gate accepted the violation (it is NOT enforcing — needs attention)
#
# Each probe runs the gate in a throwaway git repo with scripts/<gate> copied in, so
# the gate resolves its own ROOT exactly as it would in a consumer. Nothing in this
# repo is mutated.
#
# Modes:
#   probe-gate-liveness.sh
#       Probe the prevention gates listed in harness.config.sh PROBE_GATES; if unset,
#       fall back to this kit's own three core gates (dogfood). Exit 1 if any gate is DEAD.
#       This is the survival-proof view: it probes EVERY gate, including escalation-only ones,
#       so a silently-broken human-owned gate still surfaces (for a human / gatecrate-evaluate).
#   probe-gate-liveness.sh --repairable-only
#       Same, but deterministically SKIP gates marked escalation-only (see marker below). This is
#       the view the harness-liveness-converge TAKT loop uses: the loop must only ever see gates
#       an agent may auto-repair. Excluding escalation-only gates here is what structurally prevents
#       the loop from pressuring the agent to edit a human-owned gate (the exp3 failure mode) —
#       a deterministic pre-loop triage, not a persona rule it can rationalize past.
#   probe-gate-liveness.sh --one <gate_path> <kind>
#       Probe a single gate; ALIVE -> exit 0, DEAD -> exit 1.
#       kind: title | secrets | filesize | hard-constraints | posix | escalation
#   probe-gate-liveness.sh --list-reject-gates
#       Emit the prevention(reject-type) gate registry, one gate base per line. The single source of
#       truth classify-gate-type.sh derives "prevention" from (so REJECT_GATES is never re-declared).
#   probe-gate-liveness.sh --audit
#       Coverage meta-check: every probe-able reject-type gate PRESENT must be registered in
#       PROBE_GATES. Exit 1 if an injectable reject-type gate is unregistered ("added a gate but forgot
#       to register it for survival proof"). Reject-type gates with no injector yet (git-scenario /
#       toolchain) are reported as NOTE so the remaining coverage gap is VISIBLE, never silent. This
#       applies the probe's own thesis (a never-firing gate hides whether it works) to its own coverage.
#
# Consumer config (optional, from harness.config.sh in the consumer repo root, or env):
#   PROBE_GATES — whitespace/newline separated "<repo-root-relative-path>:<kind>" tokens,
#                 e.g. "scripts/check-no-committed-secrets.sh:secrets scripts/check-title.sh:title".
#                 kind is one of title|secrets|filesize|hard-constraints|posix|escalation (injectable classes).
#                 Unset -> the kit's own core gates (title/secrets/filesize/posix/escalation, dogfood).
#
# Escalation-only marker: a gate whose repair is reserved for a human (security-owned policy, or a
# gate whose guarded risk vanished -> removal proposal) carries this comment line in its own file:
#       # gatecrate-scope: escalation-only
#   --repairable-only excludes such gates from the converge loop; the default survival-proof mode
#   still probes them (and reports DEAD ones) so a human is not left unaware.
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"

# The synthetic violation for the PR-title gate (no leading type, no colon).
BAD_TITLE='not a valid conventional title'

# inject_secrets <workdir>: track a keystore-like file the secrets gate must reject.
inject_secrets() {
  printf 'storePassword=hunter2\n' > "$1/key.properties"
  git -C "$1" add key.properties >/dev/null 2>&1
}

# inject_filesize <workdir>: drop a file past the 300-line limit the size gate enforces.
inject_filesize() {
  i=0
  while [ "$i" -lt 301 ]; do echo "# bloat line $i"; i=$((i + 1)); done > "$1/bloat.sh"
}

# inject_hardconstraints <workdir>: copy the consumer's hard-constraints.tsv in and synthesize a
# violation of its FIRST forbid rule (a file matching the rule's pathspec, containing its pattern),
# so the config-driven check-hard-constraints gate must reject it. Returns 3 (a SETUP signal, NOT a
# survival proof) when there is no config / no forbid rule to inject — we must never report ALIVE for
# a gate we could not actually exercise. This is what makes the config-driven gate probeable.
inject_hardconstraints() {
  wd="$1"
  cfile="${HARD_CONSTRAINTS_FILE:-$ROOT/hard-constraints.tsv}"
  [ -f "$cfile" ] || return 3
  cp "$cfile" "$wd/hard-constraints.tsv"
  rule="$(awk -F '\t' '$1=="forbid"{print; exit}' "$wd/hard-constraints.tsv")"
  [ -n "$rule" ] || return 3
  pathspec="$(printf '%s' "$rule" | cut -f2)"
  regex="$(printf '%s' "$rule" | cut -f3)"
  # concrete path from the pathspec: turn glob wildcards into a literal segment so the file exists.
  target="$(printf '%s' "$pathspec" | sed 's#\*\*/#probe/#g; s/\*\*/probe/g; s/\*/probe/g; s/?/x/g')"
  mkdir -p "$wd/$(dirname "$target")"
  printf '%s\n' "$regex" > "$wd/$target"
  git -C "$wd" add -A >/dev/null 2>&1
}

# inject_posix <workdir>: drop a script with a non-#!/bin/sh shebang the posix-portability gate must
# reject (shebang check alone fails it, so no shellcheck dependency is needed to prove liveness).
inject_posix() {
  printf '#!/bin/bash\necho bashism\n' > "$1/scripts/bad-shebang.sh"
  git -C "$1" add -A >/dev/null 2>&1
}

# inject_escalation <workdir>: leave the escalation record the mutation-escalation gate must reject.
inject_escalation() {
  mkdir -p "$1/.kiro"
  printf 'gatecrate mutation escalation (synthetic probe)\n--- last survivors ---\n[Survived] Probe\n' \
    > "$1/.kiro/.gatecrate-mutation-escalated"
}

# pcommit <workdir> <msg> [extra git args...]: a deterministic commit (no user config needed).
pcommit() { wd="$1"; m="$2"; shift 2; git -C "$wd" -c user.email=probe@probe -c user.name=probe commit -q "$@" -m "$m" >/dev/null 2>&1; }

# inject_doccurrency <workdir>: commit an EN/JA pair (base), then change ONLY the EN side, so the
# doc-currency gate (diffs BASE..HEAD for one-sided pair edits) must reject. Base sha -> .probe-base.
inject_doccurrency() {
  wd="$1"; mkdir -p "$wd/docs"
  printf 'en\n' > "$wd/docs/probe.md"; printf 'ja\n' > "$wd/docs/probe.ja.md"
  git -C "$wd" add -A >/dev/null 2>&1; pcommit "$wd" base
  git -C "$wd" rev-parse HEAD > "$wd/.probe-base"
  printf 'en changed\n' >> "$wd/docs/probe.md"
  git -C "$wd" add -A >/dev/null 2>&1; pcommit "$wd" edit
}

# inject_ruledoc <workdir>: a lane file; the gate is driven via the RULE_DOC_CHANGED seam in run_gate
# (a rule-bearing change with no doc update and no Docs-Impact -> the gate must reject).
inject_ruledoc() {
  printf 'probe\t^src/probe\\.ts$\t^docs/probe\\.md$\n' > "$1/rule-doc-lanes.tsv"
}

# inject_mergeintegrity <workdir>: build a 2-parent merge (x+y) that does NOT contain the final head B,
# so the gate must reject the race. head sha -> .probe-head, merge sha -> .probe-merge.
inject_mergeintegrity() {
  wd="$1"
  pcommit "$wd" base --allow-empty
  def="$(git -C "$wd" rev-parse --abbrev-ref HEAD)"
  git -C "$wd" branch -q x; git -C "$wd" branch -q y
  git -C "$wd" checkout -q x; pcommit "$wd" X --allow-empty
  git -C "$wd" checkout -q y; pcommit "$wd" Y --allow-empty
  git -C "$wd" checkout -q "$def"; pcommit "$wd" B --allow-empty
  git -C "$wd" rev-parse HEAD > "$wd/.probe-head"
  git -C "$wd" checkout -q x
  git -C "$wd" -c user.email=probe@probe -c user.name=probe merge --no-ff -q -m M y >/dev/null 2>&1
  git -C "$wd" rev-parse HEAD > "$wd/.probe-merge"
}

# inject_release <workdir> <gatedir>: copy the version-env.sh dependency, set VERSION_NAME=1.0.0 and
# tag v1.0.0, so the release-version-name gate (rejects a version name equal to the latest tag) fires.
# Returns 3 (setup, not a survival proof) if version-env.sh is not alongside the gate.
inject_release() {
  wd="$1"; gatedir="$2"
  [ -f "$gatedir/version-env.sh" ] || return 3
  cp "$gatedir/version-env.sh" "$wd/scripts/version-env.sh"
  printf 'VERSION_NAME=1.0.0\nVERSION_CODE=1\n' > "$wd/VERSION"
  git -C "$wd" add -A >/dev/null 2>&1; pcommit "$wd" base
  git -C "$wd" tag v1.0.0 >/dev/null 2>&1
}

# inject_thirdparty <workdir>: a bundled asset present but the notices file missing a required string,
# so the third-party-notices gate must reject (config supplied via env in run_gate).
inject_thirdparty() {
  printf 'bundled\n' > "$1/probe-asset.js"
  printf 'no required notice here\n' > "$1/THIRD_PARTY_NOTICES.md"
}

# inject_modularity <workdir>: a synthetic RED (strong x distant x volatile) edge with NO baseline
# entry, injected via the MODULARITY_RED_FILE seam (no JVM sources needed), so the modularity
# ratchet gate must reject the new balance violation.
inject_modularity() {
  printf 'probe.src.pkg\tprobe.far.volatile\t3\tintrusive\t4\t12\t192\n' > "$1/probe-red.tsv"
}

# run_gate <workdir> <gate_basename> <kind>: execute the copied gate against the
# injected violation and return the gate's own exit code.
run_gate() {
  wd="$1"; base="$2"; kind="$3"
  case "$kind" in
    title)            ( cd "$wd" && sh "scripts/$base" "$BAD_TITLE" ) ;;
    secrets)          ( cd "$wd" && sh "scripts/$base" ) ;;
    filesize)         ( cd "$wd" && FILE_LINE_PATHS="." FILE_LINE_NAMES="*.sh" sh "scripts/$base" ) ;;
    hard-constraints) ( cd "$wd" && sh "scripts/$base" ) ;;
    posix)            ( cd "$wd" && sh "scripts/$base" ) ;;
    escalation)       ( cd "$wd" && sh "scripts/$base" ) ;;
    doc-currency)     ( cd "$wd" && DOC_CURRENCY_BASE="$(cat .probe-base)" sh "scripts/$base" ) ;;
    rule-doc)         ( cd "$wd" && RULE_DOC_CHANGED="src/probe.ts" RULE_DOC_COMMITS="probe change" sh "scripts/$base" ) ;;
    merge-integrity)  ( cd "$wd" && sh "scripts/$base" "$(cat .probe-head)" "$(cat .probe-merge)" ) ;;
    release-version)  ( cd "$wd" && sh "scripts/$base" ) ;;
    third-party)      ( cd "$wd" && TPN_BUNDLED_ASSET=probe-asset.js TPN_REQUIRED_STRINGS=ProbeNotice sh "scripts/$base" ) ;;
    modularity)       ( cd "$wd" && MODULARITY_RED_FILE="$wd/probe-red.tsv" MODULARITY_BASELINE_FILE="$wd/probe-baseline.tsv" sh "scripts/$base" ) ;;
    *) echo "probe: unknown kind: $kind" >&2; return 2 ;;
  esac
}

# is_escalation_only <gate_path>: true if the gate file is marked escalation-only, i.e. its
# repair is reserved for a human (security-owned policy / premise-vanished removal). The marker is
# a deterministic comment in the gate's own file, so the converge loop can EXCLUDE such gates
# instead of trusting the agent not to edit them under loop pressure (the exp3 finding).
is_escalation_only() {
  [ -f "$1" ] || return 1
  grep -Eq '^[[:space:]]*#[[:space:]]*gatecrate-scope:[[:space:]]*escalation-only([[:space:]]|$)' "$1"
}

# probe_gate <gate_path> <kind>: print "ALIVE <name>" / "DEAD <name>";
# return 0 if alive, 1 if dead, 2 on setup error.
#
# The gate's exit code is interpreted STRICTLY: 0 = it accepted the violation (DEAD),
# 1 = it rejected the violation (ALIVE). Any other code (and an invalid/typo'd kind) is a
# SETUP ERROR, not a survival proof — we must NOT report ALIVE for it. Otherwise a mistyped
# PROBE_GATES kind (e.g. "secret" or a missing colon) would skip the gate entirely yet exit 0,
# a false survival proof — exactly the silent failure this probe exists to catch.
probe_gate() {
  gate="$1"; kind="$2"
  case "$kind" in
    title|secrets|filesize|hard-constraints|posix|escalation|doc-currency|rule-doc|merge-integrity|release-version|third-party|modularity) ;;
    *) echo "probe: invalid kind '$kind' for $gate — see header for the injectable classes (check PROBE_GATES)" >&2
       return 2 ;;
  esac
  [ -f "$gate" ] || { echo "probe: gate not found: $gate" >&2; return 2; }
  base="$(basename "$gate")"
  gatedir="$(dirname "$gate")"
  wd="$(mktemp -d)"
  git -C "$wd" init -q
  mkdir -p "$wd/scripts"
  cp "$gate" "$wd/scripts/$base"
  irc=0
  case "$kind" in
    secrets)          inject_secrets "$wd" ;;
    filesize)         inject_filesize "$wd" ;;
    hard-constraints) inject_hardconstraints "$wd" || irc=$? ;;
    posix)            inject_posix "$wd" ;;
    escalation)       inject_escalation "$wd" ;;
    doc-currency)     inject_doccurrency "$wd" ;;
    rule-doc)         inject_ruledoc "$wd" ;;
    merge-integrity)  inject_mergeintegrity "$wd" ;;
    release-version)  inject_release "$wd" "$gatedir" || irc=$? ;;
    third-party)      inject_thirdparty "$wd" ;;
    modularity)       inject_modularity "$wd" ;;
    title)            : ;;  # injected via argv inside run_gate
  esac
  if [ "$irc" -eq 3 ]; then
    rm -rf "$wd"
    echo "probe: $base ($kind) — required config/dependency to inject is absent; cannot prove liveness (setup, not ALIVE)" >&2
    return 2
  fi
  rc=0
  run_gate "$wd" "$base" "$kind" >/dev/null 2>&1 || rc=$?
  rm -rf "$wd"
  case "$rc" in
    0) echo "DEAD  $base ($kind) — accepted a synthetic violation"; return 1 ;;
    1) echo "ALIVE $base ($kind)"; return 0 ;;
    *) echo "probe: $base ($kind) neither cleanly accepted nor rejected (rc=$rc) — setup error, not a survival proof" >&2
       return 2 ;;
  esac
}

# ---- flag: --repairable-only excludes escalation-only gates (the converge-loop view) ----
REPAIRABLE_ONLY=0
if [ "${1:-}" = "--repairable-only" ]; then
  REPAIRABLE_ONLY=1
  shift
fi

# ---- single-gate mode (used by the tests) ----
if [ "${1:-}" = "--one" ]; then
  probe_gate "$2" "$3"
  exit $?
fi

# Reject-type prevention gates and their injectable probe kind. An EMPTY kind means "reject-type but
# no injector built yet" (needs a git-scenario / toolchain setup) — the audit surfaces these as gaps
# so a missing survival proof is VISIBLE, never silent. Non-reject gates (measure-*, collect-*,
# kit-drift, test-compiles, domain-model) are intentionally absent: they are not reject-type.
REJECT_GATES="check-conventional-title.sh:title check-no-committed-secrets.sh:secrets
check-file-line-limit.sh:filesize check-hard-constraints.sh:hard-constraints
check-posix-portability.sh:posix check-mutation-escalation.sh:escalation
check-doc-currency.sh:doc-currency check-rule-doc-currency.sh:rule-doc
check-merge-integrity.sh:merge-integrity check-release-version-name.sh:release-version
check-third-party-notices.sh:third-party check-modularity-ratchet.sh:modularity"

# ---- list mode: emit the prevention(reject-type) registry, one gate base per line ----
# Single source of truth for "which gates are prevention-type". classify-gate-type.sh consumes this
# instead of re-declaring REJECT_GATES (a second copy would drift). Every reject-type gate is listed,
# including ones with no injector yet (empty kind) — lacking a survival proof does not make a gate
# any less prevention-type. Membership here is the structural signature classify derives "prevention"
# from; it deliberately says nothing about whether a gate is correctly classified (that is not knowable
# mechanically — see docs/probe-scope-and-gate-classification-decision.md §1).
if [ "${1:-}" = "--list-reject-gates" ]; then
  for entry in $REJECT_GATES; do
    echo "${entry%:*}"
  done
  exit 0
fi

# ---- audit mode: every probe-able reject-type gate present must be registered in PROBE_GATES ----
# This is the structural fix for "added a gate but forgot to register it for survival proof" — the
# exact blind spot (a prevention gate that never fires looks identical broken or working) this probe
# exists to close, applied to the probe's OWN coverage.
if [ "${1:-}" = "--audit" ]; then
  # A consumer's gates live in scripts/ (install copies there); the kit dogfoods its own in
  # core/scripts/. Mirror the default-mode split (PROBE_GATES set = consumer) rather than guessing
  # by dir existence — the kit ALSO has a scripts/ for internal tooling, which would mislead.
  if [ -n "${PROBE_GATES:-}" ]; then GATE_DIR="scripts"; else GATE_DIR="core/scripts"; fi
  registered=" $(printf '%s' "${PROBE_GATES:-}" | tr '\n' ' ') "
  miss=0
  echo "Probe coverage audit (reject-type prevention gates in $GATE_DIR/):"
  for entry in $REJECT_GATES; do
    base="${entry%:*}"; ekind="${entry##*:}"
    [ -f "$ROOT/$GATE_DIR/$base" ] || continue          # gate not adopted by this consumer
    if [ -z "$ekind" ]; then
      echo "  NOTE  $base — reject-type, no injector yet (git-scenario/toolchain); survival proof pending"
      continue
    fi
    case "$registered" in
      *"/$base:"*|*" $base:"*) echo "  OK    $base ($ekind) — registered in PROBE_GATES" ;;
      *) if [ -z "${PROBE_GATES:-}" ]; then
           echo "  NOTE  $base ($ekind) — injectable; PROBE_GATES unset (kit dogfood default in use)"
         else
           echo "  MISS  $base ($ekind) — injectable but NOT in PROBE_GATES (register it for survival proof)" >&2
           miss=$((miss + 1))
         fi ;;
    esac
  done
  if [ "$miss" -gt 0 ]; then
    echo "" >&2
    echo "probe --audit FAILED: $miss probe-able reject-type gate(s) are not covered by the survival proof." >&2
    exit 1
  fi
  echo "probe --audit passed: all probe-able reject-type gates present are registered."
  exit 0
fi

# ---- default mode: probe the consumer's PROBE_GATES, or the kit's own gates (dogfood) ----
# Each spec is "<path>:<kind>". Consumer-supplied PROBE_GATES uses the same form; when unset we
# fall back to this kit's three core gates so the dogfood path is unchanged.
if [ -n "${PROBE_GATES:-}" ]; then
  specs="$PROBE_GATES"
  echo "Gate liveness probe — survival proof (consumer prevention gates from PROBE_GATES):"
else
  specs="core/scripts/check-conventional-title.sh:title
core/scripts/check-no-committed-secrets.sh:secrets
core/scripts/check-file-line-limit.sh:filesize
core/scripts/check-posix-portability.sh:posix
core/scripts/check-mutation-escalation.sh:escalation
core/scripts/check-doc-currency.sh:doc-currency
core/scripts/check-rule-doc-currency.sh:rule-doc
core/scripts/check-merge-integrity.sh:merge-integrity
core/scripts/check-release-version-name.sh:release-version
core/scripts/check-third-party-notices.sh:third-party
core/scripts/check-modularity-ratchet.sh:modularity"
  echo "Gate liveness probe — survival proof of prevention gates:"
fi

dead=0
skipped=0
# shellcheck disable=SC2086  # specs is a controlled list; intentional word-split into tokens
for spec in $specs; do
  gate_path="${spec%:*}"   # everything before the last colon
  kind="${spec##*:}"       # the trailing kind token
  full="$ROOT/$gate_path"
  # Deterministic pre-loop triage: in --repairable-only, an escalation-only gate is EXCLUDED so the
  # converge loop never pressures the agent to edit a human-owned gate. The default mode still probes
  # it (a broken human-owned gate must surface), so this skip is converge-scope only.
  if [ "$REPAIRABLE_ONLY" = 1 ] && is_escalation_only "$full"; then
    echo "SKIP  $(basename "$gate_path") — escalation-only (excluded from converge; triage to a human / gatecrate-evaluate)"
    skipped=$((skipped + 1))
    continue
  fi
  probe_gate "$full" "$kind" || dead=$((dead + 1))
done

echo ""
if [ "$skipped" -gt 0 ]; then
  echo "($skipped escalation-only gate(s) excluded from converge — review them via gatecrate-evaluate / a human.)"
fi
if [ "$dead" -gt 0 ]; then
  echo "Liveness probe FAILED: $dead gate(s) DEAD — a prevention gate is not enforcing." >&2
  echo "Investigate the gate: a recent change may have broken its rejection path." >&2
  exit 1
fi
echo "Liveness probe passed: all probed prevention gates are ALIVE."
