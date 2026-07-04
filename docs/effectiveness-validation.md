# Effectiveness validation — confirming gatecrate actually works

gatecrate ships gates, tests, and loops. "It runs and its behaviour tests pass" proves *mechanical
correctness*, not *value*. This document defines what evidence confirms gatecrate is **effective**
(delivers ROI), and records the first evidence from a real consumer.

Read this together with [`harness-roi-evaluation.md`](harness-roi-evaluation.md) (per-gate pruning
methodology) and [`test-selection-roi.md`](test-selection-roi.md) (what to build). This doc is the
kit-level "is the whole approach working" lens.

## The honest standard

The strongest claim — *"the harness prevents more escaped defects / rework than it costs"* — is a
**counterfactual** (what would have shipped without the gate) and cannot be proven outright. So do
not chase a single proof. Effectiveness is an **accumulating weight of evidence** across real
consumers: survival proof + firing/cost data + a caught-defect log + the two-axis ROI verdict.

Beware the inverse trap, baked into gatecrate's own methodology: *"a prevention gate never fired,
so it is useless"* deletes your most important gates. A prevention gate firing **zero** is normal —
read it **with the liveness probe**, never alone.

## Levels of evidence

| Level | Confirms | Instrument | localmd status |
|---|---|---|---|
| L0 mechanical | gates run, tests green | behaviour tests, lint | **met** |
| L1 catches by design | prevention gates reject an injected violation | `probe-gate-liveness.sh` (survival proof) | **partial** (probe-kind ceiling) |
| L2 catches real defects | real PRs blocked real problems | `collect-gate-history.sh` fires + caught-defect log | **partial** (real fires seen) |
| L3 outer loop improves the harness | evaluate → prune/strengthen on real history | `gatecrate-evaluate` / `harness-evaluate-cycle` | **partial** (1 cycle) |
| L4 net value vs counterfactual | fewer escaped defects/rework than cost | before/after baseline (approximate) | **unmet** |
| L5 generalisation | works on >1 consumer / stack | adoption + measurement elsewhere | **unmet** (1 consumer) |

## First evidence — localmd-reader (2026-06-15, ~50 CI runs)

Measured with `collect-gate-history.sh --group-map` (real `gh` history) and `probe-gate-liveness.sh`.
No speculation — every number is from the tools.

- **L2 — real detection value (the key evidence).** Detection gates fired on real PRs:
  `docs-currency` **2 / 12** (16.7%), `pr-title` **1 / 13**. One `docs-currency` fire caught an
  *undocumented harness change* in a kit-adoption PR — the gate blocked a real omission, not a
  synthetic one.
- **L1 — survival proof.** `title` and `secrets` probed **ALIVE**. The probe's injectable kinds were
  `title | secrets | filesize`; config-driven gates were **not probeable** until the
  `hard-constraints` kind was added (alongside this evaluation). localmd's remaining prevention gates
  are bespoke, so their liveness is still **UNCONFIRMED** — a coverage ceiling, recorded as an action.
- **Cost vs counterfactual.** Expensive zero-fire gates: `mutation` 927 s total, `gradle-build`
  1603 s. Naive "never fired → delete" is the trap — `mutation` is a *strengthening* gate (ratchet
  floor 82 %), not detection; `gradle-build` fires only on a broken build. Judge via the two axes,
  never firing alone.
- **Axis-2 load.** doc churn 315 commits, 13 workflows, 8 consumed scripts, 14 check scripts —
  manageable, and one consolidation (C1: two doc guards → one) already shipped.

### Per-gate first verdicts (localmd)

| Gate | Type | fires/runs | CI s | Verdict | Why |
|---|---|---|---|---|---|
| docs-currency | detection | 2/12 | ~0 | keep | caught real undocumented changes |
| pr-title | prevention | 1/13 | ~0 | keep | cheap, ALIVE, caught one |
| secrets | prevention | 0/17 | ~0 | keep | ALIVE, ~free (firing 0 is healthy) |
| mutation | strengthen | 0/7 | 927 | keep (watch) | unique detection power; read with the floor |
| gradle-build | build | 0/18 | 1603 | keep | build correctness; fires on break |
| domain-model | detection (advisory) | 0/3 | 15 | keep | new; L2 unproven until a real spec regression |
| merge-integrity / hard-constraints / line-limit | prevention | 0 | cheap | keep | cheap; liveness UNCONFIRMED → probe-coverage action |

## Gaps blocking full confirmation (prioritised)

1. **Probe-coverage ceiling** — partially closed (the `hard-constraints` injectable kind is now
   shipped); localmd's bespoke prevention gates need either adoption of the kit's config-driven gates
   or new injectable kinds before their liveness is confirmed.
2. **One real consumer** (android-jvm). L5 needs a second on a different stack (go/rust/python).
3. **No L4 baseline** — no before/after escaped-defect or rework metric is tracked yet.
4. **New gates unproven at L2** — `domain-model`, `merge-integrity` have caught no real defect yet
   (only synthetic/behaviour-test catches). They need wild instances.

## Recommended next actions

1. Run `harness-evaluate-cycle` on each real consumer on a cadence; keep the dated reports under
   `docs/evaluations/` and **trend** the firing/cost over time (one snapshot is not a trend).
2. Maintain a **caught-defect log** — for each non-trivial fire, one line on what it blocked. This is
   the only durable L2 evidence.
3. Onboard a **second real consumer** on a different stack and measure it the same way (L5).
4. Where a consumer wants survival proof of a config-driven gate, adopt the kit
   `check-hard-constraints.sh` + `hard-constraints.tsv` so the `hard-constraints` probe kind applies.

## Self-validation honesty

gatecrate measures itself with its own tools, so the measurement must be kept honest: the probe must
really detect DEAD (it reports a setup error, never a false ALIVE, when it cannot inject — see the
`hard-constraints` no-forbid-rule case); firing data must not be gamed; and ROI verdicts must avoid
the counterfactual trap. The zero-fire expensive gates above are exactly where that discipline is
tested — and why this doc records *evidence and gaps*, not a verdict of "proven".
