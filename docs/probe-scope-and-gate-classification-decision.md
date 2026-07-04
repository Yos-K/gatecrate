# Decision record: probe scope (liveness ≠ correctness) and gate-type classification for ROI pruning

## What this doc is for

This records two decisions reached while looking for "the next rung" on the second-order
loop (P4 in [`ROADMAP.md`](../ROADMAP.md)), and the one cross-cutting principle that
produced both. A reader should come away knowing:

- **Why the liveness probe (`core/scripts/probe-gate-liveness.sh`) is deliberately NOT
  extended to check "correctness" (clean input → accept).** A proposal to do so was
  *rejected* — recorded here so it is not re-proposed.
- **How a gate's type (prevention vs detection) should be established** for ROI pruning —
  by *derivation*, not by a hand-applied label — and exactly how far a meta-gate can
  guard that classification.
- **The principle underneath both:** enforcing *existence* is mechanizable; enforcing
  *semantic correctness* is not — it terminates in a human trust anchor. Honest harness
  design shrinks the hand-asserted surface and makes that anchor explicit, rather than
  building a meta-gate that only *appears* to close the regress.

---

## 1. The principle (read this first — both decisions are instances of it)

A guard can mechanically check that something **exists / is well-formed**. It cannot
mechanically check that something is **semantically correct** without an infinite regress.
Every verification chain therefore terminates at a point that is **trusted by human
inspection**. The job of harness design is not to pretend that point away — it is to:

1. **Shrink the hand-asserted surface** by *deriving* whatever can be derived from
   structural facts the harness already has, so fewer things rest on human assertion; and
2. **Make the remaining trust anchor explicit** (who owns it, where it sits), the way the
   `# gatecrate-scope: escalation-only` marker already declares "a human owns this gate's
   repair" rather than hiding it.

A meta-gate that claims to verify semantic correctness but can only verify presence is
itself a *silent rot*: it stays green while a mislabeled / vacuous artifact slips through —
the exact failure class the harness exists to prevent. Do not build one.

This principle is the same one P4's "設計上の難所" already states for pruning ("剪定/統合の
最終判定は persona 主導 … 機械判定できるのはプローブ部分だけ"). The two decisions below
apply it to two new spots.

---

## 2. Decision: the liveness probe stays liveness-only (correctness proposal REJECTED)

### The proposal

Extend the probe so that, per gate kind, it also injects a **clean** fixture and asserts
the gate **accepts** it (exit 0) — turning "survival proof" (`probe-gate-liveness`) into a
"correctness proof" (`probe-gate-correctness`) that also catches *false positives* (a gate
that over-rejects legitimate input).

### Why it was rejected

- **Correctness is already the unit-test layer's responsibility, and that layer already
  reproduces the consumer environment.** The gates' own behavior tests
  (`tests/test-check-*.sh`) verify *both* directions. The accept side is real and tested:
  `test-check-conventional-title.sh` ("valid title → exit 0"),
  `test-check-no-committed-secrets.sh` ("clean tree → exit 0"),
  `test-check-file-line-limit.sh` ("only small files → exit 0"). These build a throwaway
  repo with `mktemp` + `git init` and reproduce subdirectory structure — i.e. the *same*
  consumer-realistic environment the probe uses (this is what fixed the `#94` glob blind
  spot). So "the probe is the only thing that sees the consumer environment" is false; the
  accept side is covered there too.
- **The probe's reason to exist (catch *silent* failure) does not apply to false
  positives.** A prevention gate that stops enforcing is *silent* — "never fires" looks
  identical whether it works or is broken; that is why the probe injects a violation. A
  false positive is the **opposite of silent**: it rejects a legitimate PR and a human
  notices immediately. It is outside the probe's mandate by construction.
- **Therefore probe-correctness is a *misplacement*, not merely a duplication.** Correctness
  belongs to the unit-test layer; the probe owns *in-situ liveness of prevention gates*.
  Putting accept-checks in the probe puts a responsibility in the wrong layer.

### Consequence

`probe-gate-liveness.sh` remains one-sided **by design**: violation → must reject. Do not
add clean-fixture accept assertions to it.

### Open item (lower priority, recorded for honesty — not scheduled)

The unit-test layer's guarantee bottoms out one level deeper: `check-gate-tests.sh` enforces
that a behavior test **exists**, not that it is **non-vacuous**. Per §1, the principled
terminator is *gate mutation*: break a gate and confirm its test reddens.

- The probe is *already* the automated "gate suddenly accepts violations" mutation, checked
  in-situ — so the **reject** side has two independent witnesses (unit test + probe).
- The unbuilt dual is "gate suddenly rejects everything" → does the *accept* test redden?
  This would prove the accept test is non-vacuous. It has unique value only on the accept
  side (the reject side is already double-covered) and, like all mutation testing, only
  *samples* — it still terminates in human trust. Worth doing **after** the §3 work, if at
  all; it does not change the §2 decision.

---

## 3. Decision: gate-type (prevention/detection) is DERIVED, and the meta-gate guards presence only

### Why a type is needed at all

ROI pruning reads firing history (`collect-gate-history.sh`: `runs / fires / fire_rate /
…`). But **"prevention gate with 0 fires" (healthy) and "detection gate with 0 fires"
(removal candidate) are indistinguishable from firing data alone.** This is the §1 silent
blind spot reappearing on the ROI side: the firing axis cannot, by itself, tell the two
apart. The pruning logic therefore needs to know each gate's type — otherwise it either
deletes the most valuable (silent, healthy) prevention gates, or never prunes anything.

### Why the type is DERIVED, not hand-labeled

The classification is already half-encoded in structural facts the harness holds:

- **Prevention = probe-able.** Membership in the probe's `REJECT_GATES` (a reject-type gate
  that has a synthetic-violation injector *and* a clean-accept behavior test) is the
  structural signature of a prevention gate. Its completeness is **already audited** by
  `probe-gate-liveness.sh --audit` ("every probe-able reject-type gate present must be
  registered").
- **Detection = measured by firing.** `collect-gate-history.sh` already declares itself
  "the COMPLEMENT: detection-layer firing", and already carries the counterfactual-trap
  warning ("never fired = useless deletes your most important gates — read with the
  liveness probe, never alone").

So derive the type from these signals instead of asking a human to paste a
`gate-type: prevention|detection` comment on every gate. **Hand-labels rot** (the
testless-gate failure mode); a derivation rests on facts already guarded elsewhere, so the
hand-asserted surface stays small. A human marker is kept only as a **narrow override** for
genuinely ambiguous gates — mirroring how `escalation-only` is a narrow human override on an
otherwise-derived default, not a label every gate must carry.

### What the meta-gate may and may not claim

Per §1, split the originally-proposed "detect missing **or wrong** labels" into two:

- **Missing / underivable → mechanizable. Build it.** A gate that is neither derivable as a
  type nor human-overridden is surfaced as **"untyped"** (the analogue of "added a gate but
  forgot to register it for the survival proof").
- **Semantically wrong (a detection gate mislabeled prevention to dodge ROI scrutiny) →
  NOT mechanizable. Do not claim to detect it.** This is the same wall as "detect a vacuous
  test." A meta-gate that *claimed* to catch it would be the silent-rot meta-gate §1 warns
  against. Correcting a genuine misclassification is **escalation** (human-owned), stated
  explicitly — consistent with `escalation-only`, whose correctness is *also* not
  machine-verified (`is_escalation_only` is a plain `grep` for the marker, by design).

### Consequence — the revised first step for the ROI-shrinking work

The earlier "first build the type label + its meta-gate" is corrected to:

1. **Derive the type** — a small function: in `REJECT_GATES` + has clean-accept test ⇒
   prevention; otherwise consult firing history / human override.
2. **Meta-gate surfaces "untyped" only** — never claims to detect mislabeling.
3. **Then** the type-aware two-axis verdict runs: prevention with 0 fires ⇒ keep (value
   proven by liveness, not firing); detection with long-term 0 fires + cost ⇒ removal
   candidate (human-approved, never auto-removed).

### 3.1 Refinement after the step-1 PoC (resolved): a third category, and type is not purely script-derivable

Implementing step 1 (`classify-gate-type.sh`) and classifying the kit's own gates corrected
two things in the §3 sketch:

- **The prevention/detection pair is not exhaustive — a third category `advisory` is needed.**
  The kit's gates split into 11 prevention + 7 that derived as `untyped`, and inspecting those
  7 showed they are *not* homogeneous: `check-test-compiles` is **detection** (exits non-zero
  on a real compile failure), `check-gate-tests` is a **prevention**-shaped meta-gate (rejects
  testless gates), while `measure-complexity` / `measure-coupling` / `check-kit-drift` /
  `check-domain-model` do **not block by default** — they emit a signal. The earlier guess
  "the untyped ones are all advisory" was wrong; the real point is that a *non-rejecting* gate
  needs its own category because the firing-based ROI verdict **does not apply** to it. Its
  value question is "is the signal consumed / acted on?", which is **not** derivable from CI
  firing history — it is a human judgment. So the automated two-axis verdict (step 3) runs on
  **prevention + detection only**; `advisory` gates are routed to a human, never auto-pruned.

- **prevention/detection/advisory is not purely a property of the gate script.** Evidence:
  `measure-complexity` is advisory by default but **rejects under `--strict`**;
  `check-kit-drift` is the same (`--strict` flips it to blocking); `check-domain-model` exits
  non-zero on a counterexample yet is "advisory" because it is wired as a **non-required** CI
  check (branch protection). So whether a gate blocks a merge depends on its **configured mode
  (`--strict`) and CI wiring (required check or not)**, not on the script alone. This is the §1
  principle again: the script is a partial signal; the rest lives in configuration/wiring, a
  separate source. Therefore `advisory` **cannot be derived from the gate file** the way
  `prevention` can (registry membership).

Resolved decisions (this refinement):

1. **Categories**: `prevention` / `detection` / `advisory`, plus `untyped` for a genuine gap.
   `advisory` is a *terminal* classification — the meta-gate must **not** nag about it; it nags
   only about `untyped` (a gate that blocks but has no class). Conflating the two would either
   raise false alarms on advisory gates or hide real gaps.
2. **How `advisory` is established**: a human marker `# gatecrate-type: advisory` (the honest
   minimum for step 2, mirroring the `detection` marker). Deriving it from CI wiring (required
   checks via `gh`, `--strict` in the workflow) is the §1 "shrink the hand-asserted surface"
   follow-up — tracked, not blocking.
3. **Non-gate harness machinery is excluded from the classification universe.** Tooling and
   utilities (`collect-gate-history`, `probe-gate-liveness`, `classify-gate-type`, `version-*`,
   `start-work`, `pr-preflight`, `setup-branch-protection`, `prepare-*`) are **not gates**;
   `--one` reports them as `not-a-gate`. The curated set is kept aligned with the
   "計測 advisory / ユーティリティ" enumeration `check-gate-tests.sh` already carries.

### 3.2 When the harness defers to a human, it must present the decidability evidence

§1 ends every chain at "a human decides." That is only honest if the human is given what makes
the decision cheap. Surfacing a bare `untyped — classify it` hands a human a blank — they will
guess or rubber-stamp, which is the silent rot §1 warns against, merely relocated to the human.
So a deferral must carry the *evidence that makes the call decidable* (the same reason
`check-progress`-style "未決定事項" tables must include a "判断に必要な材料" column).

The guardrail that keeps this from sliding back into auto-labeling:

- **Suggest with the basis shown — never auto-apply.** The harness gathers the derivable
  evidence (does the gate have a non-zero exit path? is it in the reject registry? does it accept
  `--strict`? does its header self-declare advisory? is it invoked in a workflow?) and prints a
  *suggested* type **with the rule that produced it**. Evidence it cannot derive (required-check
  status, firing history) is marked `needs gh`, never guessed. The marker is still added by a
  human hand; the suggestion is a hypothesis with its reasoning exposed, not a verdict.
- **Why this is safe where auto-enforce is not.** Auto-enforce applies a label *and acts on it*
  with no human and no evidence — a wrong label silently changes ROI behavior. Suggest-with-
  evidence shifts the human's task from "derive from scratch" (hard, invites guessing) to "check
  this hypothesis against this evidence" (easy, the right cognitive task); a wrong suggestion is
  visible and overridable. The human stays the trust anchor, now *informed*.

The suggestion is shown as an **inference ladder** (Ladder of Inference:
observe → select → assume → conclude), so the human can climb *down* and check each rung rather
than accept or reject a verdict whole. The load-bearing **assumption** is flagged `[UNVERIFIED]`
when it rests on data this view cannot see (e.g. "a non-zero exit blocks the merge *as wired*"
depends on required-check status = `needs gh`), and a `check first:` line names that rung — so the
human's scrutiny lands exactly where the inference is weakest. Where there is no inferential leap
(a structural fact like registry membership, or a human's own marker) the ladder **collapses** to
observe → conclude; we never fabricate rungs to look rigorous.

This is `classify-gate-type.sh --explain <gate>`, and step 2's `untyped` meta-gate embeds its
output in the failure message so the human sees *what to decide and on what basis*, not just
*that* something is unclassified. The principle generalizes to every human-deferral the harness
makes (removal proposals, coverage suggestions, escalation triage): present the material, suggest,
never auto-apply.

---

## 4. Status

§2 stands as a design decision (the probe-mutation open item is parked). §3 is **fully implemented**:

- **step 1 (type derivation)** — `core/scripts/classify-gate-type.sh` + `probe --list-reject-gates`,
  refined per §3.1 (prevention/detection/advisory/untyped/not-a-gate); §3.2 `--explain` evidence view.
- **step 2 (the `untyped`-only meta-gate)** — `core/scripts/check-gate-classified.sh`, embedding
  `--explain` in its failure; wired blocking in self-harness; kit converged to 0 untyped.
- **step 3 (the type-aware axis-1 verdict)** — `core/scripts/gate-roi-verdict.sh`: reads the
  `collect-gate-history` firing TSV and emits a per-gate verdict **routed by type** (prevention
  fires=0 → keep; detection fires=0 ∧ high-cost → removal-candidate with ② uniqueness flagged to a
  human; cheap detection → keep; advisory → human-judgment), proposals only, never auto-removing. It
  mechanizes the axis-1 firing interpretation only; axis-2 (consolidate/downgrade), ② uniqueness, and
  the advisory "is it consumed?" call remain the `gatecrate-evaluate` skill / human's job.

See [`ROADMAP.md`](../ROADMAP.md) P4 and
[`docs/harness-roi-evaluation.md`](./harness-roi-evaluation.md) for the surrounding method.
