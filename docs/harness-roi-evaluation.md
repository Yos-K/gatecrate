# Harness ROI Evaluation

How to decide which harness layers to **keep, strengthen, consolidate, or remove**
over time. Japanese: [harness-roi-evaluation.ja.md](./harness-roi-evaluation.ja.md).

This is the **evaluation** step of the proven flow (`evaluate → profile → consume →
config → wire CI → sync → verify`). The kit's [profiles](../profiles/) help you
*select* layers up front and [test-selection-roi.md](./test-selection-roi.md) decides
*which verification technique* (PBT / stateful PBT / mutation / model check) is worth
wiring; this document helps you *re-judge and prune* them after they have accrued some
history. Selection and evaluation are complementary: one adds, the other keeps the set
honest.

## Why evaluate at all

A harness accrues maintenance cost the more you add. A layer that looks valuable
the day it is added splits, over time, into "still earning its keep" and "cost
with no return." Without periodic evaluation the dead weight accumulates and
crowds out investment in the layers that actually work. Evaluation makes the
keep/prune decision **evidence-based and mechanical** instead of sentimental.

**No speculation.** Every verdict cites real evidence — CI run history, fired PRs,
synthetic-violation probes, commit churn. Where evidence cannot be obtained,
write `unconfirmed (needs X)` — never a blank or a guess.

## Two axes (and why one is not enough)

Evaluate each layer on **two orthogonal axes**. They catch different failures.

### Axis 1 — removal (denominator: CI cost × frequency)

The cost side is **continuous** cost only; build/setup cost is sunk and excluded.

- **Detection layers** (unit / mutation / smoke / external review): catch existing
  defects. Value = fired-incidents × uniqueness ÷ (CI time × frequency).
- **Prevention layers** (hygiene gates: no-secrets, forbidden-permission, line
  limits): suppress a class of mistake. **Zero firing is normal** — nothing gets
  through because the gate works. Evaluate them by (a) is the guarded risk still
  real, and (b) do they fail a deliberate synthetic-violation probe (survival
  proof). Pushing a probe through and watching the gate reject it is how you prove
  a never-fired prevention layer still works.

**Counterfactual trap:** "never fired = useless" deletes your most important
prevention layers. Guard against it with the removal-candidate AND test below.

**removal-candidate requires all three** (a logical AND, so cheap layers survive):

| # | Condition |
|---|---|
| ① high cost | CI time × frequency is large, or doc-sync cost is large |
| ② zero uniqueness | only detects what another layer already does / guarded risk gone |
| ③ zero firing or risk gone | detection layer never caught anything / prevention's premise vanished |

A cheap grep gate fails ① and so is **kept even with zero firings**.

### Axis 2 — consolidation (denominator: maintenance load, not CI seconds)

Axis 1 alone is insufficient. Its denominator is CI cost, so a **cheap** layer can
never become a removal-candidate (condition ① never fires). Combined with a
"we never delete here" stance, every cheap layer is pinned to *keep* and the
evaluation degenerates into rubber-stamping the net growth of layers.

So measure a **second, orthogonal** cost: the continuous human attention a layer
demands — which does **not** show up in CI seconds. Three signals, measured only:

| Signal | What it measures | How to measure |
|---|---|---|
| Drift-induction risk | Correctness depends on **manual discipline**; the layer breaks if a human forgets | Count of "whenever you do X, also do Y" rules an agent/contributor must hold; actual drift-incident history |
| Cognitive load / overlap | How many layers/rules a reader must hold at once; failure-mode overlap with other layers | Number of workflows / gate scripts / "source-of-truth" docs; cross-reference density |
| Human maintenance time | Wall time a human spends — **not** CI seconds | Round-trips on sync/threshold/flaky PRs; doc-sync commit counts |

A layer that scores high on any signal **and** is too cheap for axis-1 removal is a
`consolidate-candidate`. The remedy is **consolidate / integrate / automate — not
remove**: merge two overlapping gates into one, replace a manual discipline with a
CI check, unify scattered source-of-truth docs behind one index.

**Over-judging guard:** high churn ≠ waste. A frequently-touched layer may be
delivering value with each touch. Only flag layers where the load comes from
**overlap or manual-discipline dependence**, and explicitly list the cheap,
low-load layers you are keeping, so axis 2 does not invert into flagging
everything.

## The five verdicts

| Verdict | Criterion | Action |
|---|---|---|
| **keep** | unique, or cheap with low maintenance load | leave as is |
| **strengthen** | fires for real, but a coverage gap is found | add tests / raise threshold |
| **consolidate-candidate** | cheap (axis-1 removal fails) but high axis-2 load | advise consolidate / integrate / automate (not removal) |
| **downgrade-to-advisory** | high cost × low uniqueness but residual value | drop from `required` to non-blocking; do not delete |
| **removal-candidate** | all three removal conditions hold | AI proposes only; a human removes via PR |

Safety constraints (forbidden permissions, secrets) are never auto-removed by a
metric. Both `removal-candidate` and `consolidate-candidate` are **proposals**:
file them mechanically, but a human approves the removal or the consolidation.

## Procedure

```
① Collect fired incidents (detection layers).
② Collect CI cost × frequency.
③ Run synthetic-violation probes (prevention layers): does the gate reject them?
④ Axis 1: score (fires × uniqueness) / (CI time × frequency); apply removal AND.
⑤ Axis 2: for layers where removal fails, measure the 3 maintenance-load signals.
⑥ Apply the 5 verdicts; attach "why → therefore" and a primary-source link to each.
⑦ Record verdicts in a dated report. Proposals are filed; humans approve actions.
```

## Connection to profiles

Profiles answer *which tier to install* for a project's shape (`size`, `lifetime`,
`change_freq`, `state_complexity`, `failure_impact`). This methodology answers
*whether the installed layers still pay off*. Run evaluation periodically (or when
workflow/doc counts cross a threshold) and feed `consolidate-candidate` /
`removal-candidate` findings back into the project's profile choice.

## Reference implementation (dogfooding)

`localmd-reader` is the first consumer to apply both axes to a real harness:

- **Axis 1** (CI cost): 17 layers evaluated, `removal-candidate = 0` — every layer
  was either unique or too cheap to remove. This result is exactly what motivated
  axis 2: cost alone could not surface any pruning.
- **Axis 2** (maintenance load): the *same* harness yielded **4 consolidate
  candidates** — two overlapping doc-currency gates to merge, six manual
  emulator/visual workflows to unify, a script-consumption apparatus heavy
  relative to the 7 scripts it consumes, and 12 scattered "source-of-truth" docs
  to index.

The lesson the kit inherits: a selection ladder plus a one-axis evaluation will
quietly grow a harness without bound. The second axis is what keeps a *reusable*
harness from over-harnessing the projects that adopt it.
