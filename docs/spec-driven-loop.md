# The agent's spec-driven learning loop — usage

This guide shows how to run **`harness-spec-test-loop`**: the loop where the agent explores a code
cluster, **proposes the domain model it suggests**, **documents the spec**, **tests it with the
ROI-chosen technique**, and **measures adequacy with mutation** — looping until the spec-bearing code
has no surviving mutant. It pairs with [`spec-rules.md`](spec-rules.md) (the rule mini-language) and
[`test-selection-roi.md`](test-selection-roi.md) (which technique fits which risk).

```
explore → propose-model → specify → reflect (ROI technique) → measure (mutation) → iterate
```

| step | persona | output |
|---|---|---|
| explore | coverage-scout | structural facts + risk shape of the cluster |
| propose-model | domain-modeler | the domain concepts the code SUGGESTS (hypotheses / decisions) |
| specify | spec-author | rules `R-n` in the mini-language, with traceability |
| reflect | spec-author | per-rule ROI technique + a (compiling) test scaffold |
| measure | coverage-deepener | survivor-strict mutation → add tests until clean |

## Quick start (standalone, alongside your coding)

Run it on **the cluster you just changed** in a feature or refactor — same PR, so the spec doc and
tests grow with the code. The workflow lives at
`.claude/skills/gatecrate-evaluate/takt/harness-spec-test-loop.yaml`. Prerequisites in the consumer:

- a git repo; `scripts/check-test-compiles.sh` adopted (backs the scaffold-compiles gate);
- a **survivor-strict** mutation gate for `measure` (rust/cargo-mutants is strict natively; floor-based
  adapters need `MUTATION_THRESHOLD=100` for the deepen pass — see `harness-coverage-deepen.yaml`);
- `.takt/config.yaml`: `workflow_command_gates: { custom_scripts: true }`.

Invoke the workflow with the target cluster as the run task. `measure` is scoped to the changed
cluster (one mutation target) so it stays cheap enough to run per-change.

## Modes — who decides whether a hypothesis becomes a rule (`SPEC_LOOP_MODE`)

Set it in `harness.config.sh` (default: `expert-gated`):

```sh
# harness.config.sh
SPEC_LOOP_MODE=autonomous      # vibe-coded: no separate human intent — the agent decides
# SPEC_LOOP_MODE=expert-gated  # business-requirement domains — a human/owner decides (default)
```

- **`expert-gated`** — a separate human/owner owns the intent. `propose-model` stops at HYPOTHESES,
  `specify` marks rules DRAFT, `reflect` keeps the tests SKIPPED until a human classifies. Use when
  business requirements drive the spec.
- **`autonomous`** — no separate human intent (vibe coding). The agent DECIDES each model question
  from functional correctness / good design and PROCEEDS — canonizes the rule, writes an ACTIVE test.
  Business-POLICY-shaped calls (tier / revocation / grace period — where functional reasoning can only
  DEFAULT) are recorded as `DECIDED AUTONOMOUSLY (policy) — chose X because Y; an owner may prefer Z`
  and never hidden; a call that could move money / change a contract / surprise a user is escalated to
  expert-gated for THAT item. Either mode surfaces the load-bearing **missing concepts** — the owner's
  learning is preserved whether they act now or review the agent's call later.

You can also override the mode per run (state it in the run task).

## With cc-sdd (Kiro-style Spec-Driven Development)

gatecrate **integrates with** [cc-sdd](https://github.com/gotalab/cc-sdd) (MIT) **without modifying or
bundling it** — it uses cc-sdd's own extension point: every `/kiro:*` command loads the entire
`.kiro/steering/` directory as project memory.

1. **Install cc-sdd + the steering file** (cc-sdd stays vanilla; gatecrate adds only its steering).
   The installer does both in one step:

   ```sh
   sh <gatecrate>/install.sh --profile <p> --target . --with-cc-sdd
   ```

   This runs `npx cc-sdd@latest --claude-skills --lang ja` (override via `CC_SDD_AGENT` /
   `CC_SDD_LANG` / `CC_SDD_FLAGS`), then overlays the steering. By hand it is equivalent to:

   ```sh
   npx cc-sdd@latest --claude-skills --lang ja          # bootstrap cc-sdd
   mkdir -p .kiro/steering
   cp <gatecrate>/templates/kiro-steering/gatecrate-spec-test-loop.md .kiro/steering/
   ```

   Now `/kiro:steering`, `validate-gap`, `spec-design`, `spec-impl`, `validate-impl` read it and let
   the loop participate in each phase (reverse model proposals; entity/value/policy; ROI technique +
   mutation; drift report `discovered-spec vs .kiro/specs`).

2. **Mode follows the spec's existence**: cc-sdd spec present → `expert-gated` (the `.kiro/specs/` is
   the authored intent; drift and missing concepts are routed back as proposals into cc-sdd's approval
   flow). No spec yet (greenfield/legacy) → `autonomous` (the discovered spec bootstraps a
   `.kiro/specs/<feature>/requirements.md` draft a human then approves via cc-sdd's gate).

3. **Mechanical backing — the Stop hook** (so "green tests" can't end `validate-impl`).
   `install.sh --with-cc-sdd` already installs this in step 1 (hook + `.claude/settings.json` +
   `.gitignore` marker). By hand it is:

   ```sh
   mkdir -p .claude/hooks
   cp <gatecrate>/templates/hooks/spec-test-mutation-gate.sh .claude/hooks/
   # merge templates/hooks/settings-stop-hook.json into your settings.json (hooks.Stop)
   echo '.kiro/.gatecrate-mutation-pending' >> .gitignore
   ```

   Then confirm the gate actually runs: `sh scripts/run-mutation.sh` must print a mutation score
   (a version-incompatible runner can crash and the gate never executes — verify, don't assume).

   The steering arms the gate at `validate-impl` start (`touch .kiro/.gatecrate-mutation-pending`);
   the Stop hook then runs the survivor-strict mutation gate and **blocks the agent from stopping**
   while a mutant survives (exit 2 + the survivor list fed back), until the spec is adequately tested.
   A per-session counter caps consecutive blocks (`SPEC_TEST_MUTATION_MAX_BLOCKS`, default 3) so it can
   never loop forever. **At the cap it escalates, it does not silently pass**: it writes a visible record
   `.kiro/.gatecrate-mutation-escalated` (with the survivors) and the first-order CI gate
   `check-mutation-escalation.sh` then fails the PR until a human kills the survivors and deletes the
   record. So the bypass is multi-layer-defended — logged at the Stop hook (immediate layer) and blocked
   in CI (first-order layer), never invisible. See `templates/hooks/README.md`.

## Worked example (autonomous)

On a fresh cart-pricing module the loop formed this domain knowledge:

- **DECISION (functional, canon):** the total never goes negative (clamp to 0); empty cart = 0.
- **DECIDED AUTONOMOUSLY (policy):** percent+fixed coupons stack additively; one coupon per cart; no
  minimum order — *an owner may prefer exclusive types / stacking / a threshold.*
- **Missing concept (for the owner):** `Coupon` is a bare value with no validity / code / usage-limit —
  there may be a `Coupon`/`Promotion` **entity** the code lacks.
- **Agent-implemented rule:** from "percent is unguarded → a negative percent *raises* the total", the
  agent decided **R-5 "percent must be 0..100"** and implemented the guard (canon + active test).
- **ROI technique:** R-1 (total ∈ [0, subtotal], a whole-input invariant) → **PBT**; the small/finite
  rules → example tests.
- **measure:** removing the clamp `max(0, …)` left the naive example tests green (survivor), while the
  ROI-selected PBT killed it — the loop mechanically caught a rule the green tests had not verified.

## Config reference

| Variable (harness.config.sh) | Default | Meaning |
|---|---|---|
| `SPEC_LOOP_MODE` | `expert-gated` | `autonomous` \| `expert-gated` (see Modes) |
| `SPEC_TEST_MUTATION_CMD` | `sh scripts/run-mutation.sh` | the survivor-strict mutation command the Stop hook runs |
| `SPEC_TEST_MUTATION_MAX_BLOCKS` | `3` | consecutive Stop-hook blocks before force-through |

## Honest limits

- The agent discovers only the spec the code **implies**; a rule that *should* exist but is nowhere in
  the code is invisible (mutation cannot see it either). The loop seeds — it does not replace — the
  owner / domain expert.
- The steering is **prompt-level guidance** (a judgment layer). The **mechanical** guarantees are the
  gate scripts: survivor-strict mutation (the Stop hook), `check-test-compiles`, traceability. Concept
  confirmation and intent approval stay with the human (cc-sdd's phase gates).
