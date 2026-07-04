# Decision record: running the Alloy domain-model check in CI

## What this doc is for

This records *when* to run the formal domain-model check (`docs/domain/models/*.als`, verified by
`scripts/check-domain-model.sh`) in CI, *how* to wire it, and *why* it is **advisory by default**.
A consumer reading this should understand why the job exists, why it does not block merges out of
the box, and what it would take to promote it to a required gate.

**Default: adopt it as an advisory job** (`core/workflows/domain-model-check.yml` →
`.github/workflows/domain-model-check.yml`). Advisory = a red run warns, it does not block; the
check is simply not registered as a required check in branch protection.

---

## 1. Why have the check at all

- A spec model is a **design-stage** harness. The L2/L3 rules in your glossary interact; a rule
  change that breaks an existing guarantee is **invisible to review and to code-level tests until
  the code is written** (see the `check-domain-model.sh` header). Each `.als` encodes the rules plus
  `check ... expect N`, and Alloy exhaustively explores a small finite state space — so it fails
  (non-zero) exactly when a guarantee unexpectedly gains or loses a counterexample. It is one sieve
  *left* of the fitness/test gates.
- It closes the spec-driven loop. The `alloy-spec-model-generator` skill and the
  `harness-rule-reflect` workflow turn domain knowledge into `.als` asserts; this gate runs them in
  CI so the agent gets feedback and improves the spec. Without the gate the loop breaks before the
  check (models are written but never exercised).
- The cost is small and the flakiness risk is low: the Alloy jar is pinned + SHA-256 verified, the
  solver is deterministic, and the search space is small. The only non-deterministic factor is the
  network (fetching the jar), which the script absorbs as an advisory skip (exit 0).

**Therefore:** add a lightweight job that fires only on `docs/domain/models/**` (and the check
script / workflow) changes, mechanically surfacing spec regressions on the PR — **advisory first**.

---

## 2. Why advisory by default (and not a required gate)

### Required checks + `paths:` filters do not mix

A common CI pattern: a *required* check that uses `paths:` filtering gets stuck **pending** on PRs
whose diff does not match the paths — branch protection waits forever for a check that never runs.
Teams work around this for required jobs by avoiding `paths:` entirely (report success immediately
instead). An **advisory** (non-required) check has no such problem: on a non-matching PR the check
simply does not appear, and the merge is not blocked. So advisory is what *lets* this job use a
narrow `paths:` trigger.

### The environment-skip must not masquerade as a pass, and a real counterexample must show red

Two design rules make advisory operation honest:

- **No `continue-on-error: true`.** The script exits non-zero on exactly two real anomalies — an
  unexpected counterexample (`expect N` mismatch) or a jar checksum mismatch. Both are genuine
  problems and must show red. `continue-on-error` would paint even a real counterexample green,
  which defeats the point. Advisory is achieved by *not registering* the check as required (a red
  run does not block the merge), **not** by hiding failures.
- **Surface skips as a warning.** When Java or the Alloy jar is unavailable, the script skips with
  `exit 0` and prints `skipping (advisory check)`. The workflow greps for that string and emits a
  `::warning::` annotation plus a step-summary note, so a skipped run is **never** mistaken for a
  verified one. (`DOMAIN_MODEL_STRICT=1` turns a missing toolchain into a hard failure for repos
  that want to force the model to always run.)

---

## 3. How it is wired (and why)

| Concern | Decision | Why |
|---|---|---|
| Trigger | `paths:` = `docs/domain/models/**`, the check script, the workflow itself | the spec guarantees only change when a model or the checker changes |
| Push trigger | `main` only | mirrors the main CI workflow's push policy |
| Java | `actions/setup-java` (temurin 17) always | guarantees the toolchain on CI, narrowing the skip source to the network alone |
| Jar cache | `actions/cache` on `~/.local/share/alloy`, keyed on the check script's hash | avoids re-downloading and lowers the advisory-skip rate; the key follows the pinned version + SHA in the script |
| Invocation | `sh scripts/check-domain-model.sh` (explicit `sh`) | the script is portable `#!/bin/sh`; invoking via `sh` is stack- and shebang-independent |
| Skip visibility | grep stdout for the skip string → `::warning::` + step summary | green-because-skipped is indistinguishable from green-because-verified otherwise |

---

## 4. Constraints honored

- Starts advisory: not registered as a required check (no branch-protection change needed —
  unregistered checks are non-required by default).
- Does not bypass branch protection (it makes no settings change at all).
- Changes no application behavior — it adds only a workflow and `.als` specs.

---

## 5. Known risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Network failure fetching the jar | that run is skipped (stays green) | the `::warning::` makes the skip visible (§2); the jar cache lowers the probability |
| Alloy version bump | checksum mismatch → exit 1 (red) | intended fail-fast; update the pinned version + SHA in the script |
| More models → longer runs | job latency | a few models complete in seconds; the 10-minute timeout has ample headroom; if it grows, parallelize per model |

## 6. Open decision

| Question | Impact | Evidence needed before deciding |
|---|---|---|
| When (if ever) to promote to a required gate | medium (becomes a merge gate) | several weeks of Actions history showing the advisory skip rate and any false-red incidents |
