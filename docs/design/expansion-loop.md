# Design — the coverage-expansion loop (the additive half of the outer loop)

The outer loop has two halves in tension. The **pruning** half (`harness-evaluate-cycle` +
`harness-roi-evaluation.md`) keeps the harness lean — it asks *do existing gates earn their keep?*
The **expansion** half, designed here, grows coverage — it asks *what risk is not yet verified?*
Pruning was built first because the diagnosed disease was unbounded bloat; this doc is the additive
counterweight.

> **Shipped status (single source of truth = `templates/takt/workflows/`)**: this doc *designs* both
> sub-modes, but the coverage workflows are **not yet distributed**. The workflows actually shipped under
> `templates/takt/workflows/` are `harness-evaluate-cycle`, `harness-liveness-converge`,
> `harness-rule-reflect`, and `legacy-domain-analysis`. `harness-coverage-deepen` and
> `harness-coverage-expand` (below) are **designed here but not shipped** — a consumer cannot install them
> yet. Sections §3/§4 describe the intended design, not an installable artifact.

## 1. The core difficulty

Pruning measures things that **exist** (firings, cost, the survival probe) — mechanical. Expansion
must detect **absence** (a risk with no gate), which is harder. So the whole design reduces to: *what
is the entry signal for "under-covered risk"?* Two signals, two sub-modes.

## 2. Two sub-modes

| | **Deepen** (strengthen existing) | **Broaden** (add new technique) |
|---|---|---|
| Entry signal | **mutation survivors / NO_COVERAGE** — the mutation gate's "a fault here would not be caught" | **changed code clusters** (git diff) whose **risk shape** (order/state, concurrency, complex branching) has no matching verification |
| What it adds | a focused test that **kills the survivor** (raises detection of the existing suite) | a **new verification technique** chosen via `test-selection-roi.md` (PBT / stateful PBT / mutation / model check) |
| Verdict | **mechanical** — did the survivor die? (exit code) | **judgment** — is the risk real? which technique? |
| Shape | a **converge loop** (run mutation → kill one → repeat until exit 0) | a **judgment sequence** (scan → assess → select → scaffold → human-classify) |
| Reuses | the mutation-config loop pattern (gatecrate-setup Phase 4) | the `harness-evaluate-cycle` sequence shape |
| Autonomy | high (mechanically verifiable) | proposal-level (human approves the addition) |

## 3. Deepen — designed (workflow not yet shipped under `templates/takt/workflows/`)

`harness-coverage-deepen` (TAKT) drives the consumer's **mutation gate** (`run-mutation.sh`) to
exit 0 by adding tests that kill surviving mutants — strengthening the suite's detection power. It
is a converge loop (the command gate is the mutation run); the persona `coverage-deepener` is a
**test author**, not a config deriver (its distinction from the setup-time mutation-config loop).

Rules the persona holds:
- A **killable survivor** → add ONE focused test that kills exactly that mutant. Never exclude it.
- An **equivalent mutant** (genuinely cannot be killed) → record it in the gate's exclusion ledger
  (`Cargo.toml [package.metadata.mutants] exclude`, or PITest `EXCLUDED_CLASSES`) with a reason.
- Where the gate has a **floor** (PITest `MUTATION_THRESHOLD`), ratchet it **up** to the achieved
  green score, never down. cargo-mutants is a clean gate (survivors==0), so there is nothing to lower.
- ABORT (do not "pass") if the only way to green is excluding a killable mutant or lowering a floor.

**The gate must be survivor-strict.** Deepen drives survivors to ZERO, so its command gate must exit
non-zero while ANY survivor remains. cargo-mutants does this natively (proven). Floor-based gates
(mutmut/PITest/go/ts) exit 0 once `score >= floor` — they pass WITH survivors — so for the deepen
pass they must be run strict (floor=100; the exclusion ledger keeps equivalent mutants from making
100% unreachable). Otherwise Deepen would COMPLETE on the first exit 0 without adding a test. The
android-jvm adapter also names its script `run-mutation-tests.sh`, not `run-mutation.sh`.
**Follow-up (not yet built):** a portable `require-zero-survivors` mode across all adapter
`run-mutation.sh` scripts, so the deepen pass is strict without per-adapter floor tweaks.

## 4. Broaden — designed (workflow not yet shipped under `templates/takt/workflows/`)

`harness-coverage-expand` (TAKT sequence: scan → assess → propose) + persona `coverage-scout`. It
scans the clusters changed since a base ref, assesses each cluster's risk shape (the persona carries
test-selection-roi's Q1–Q4 procedure, so no doc file is needed), and PROPOSES the technique for any
risk-shaped but under-covered cluster. It is proposal-level — a human approves the addition (cheap,
because adding is safe) — and routes behaviour-derived proposals through the **intent-vs-defect
classification gate** (a human decides before a behaviour is canonized, so a bug is never frozen as
spec). It does not auto-add a test.

Proven on a throwaway Rust consumer: a `TabSet` state machine (active-tab invariant across
open/close/activate) added with only one trivial example test. The scout flagged exactly it as an
EXPAND-CANDIDATE (Q1 order/state, no stateful PBT — code-cited), skipped the no-logic module decl as
"pure noise", and proposed a **stateful PBT** (random operation sequences vs a reference model),
correctly rejecting a TLA+ model check as overkill for the small state space. No test was auto-added.

## 5. Two principles that make expansion safe

- **Expansion may be liberal because pruning is the counterweight.** A slightly redundant test added
  by Deepen/Broaden is caught by the next `harness-evaluate-cycle` as a consolidate/remove candidate.
  The two halves balance: one adds, the other trims. Neither needs to be perfect alone.
- **Adding is safer than removing, so expansion is more autonomous than pruning.** The worst case of
  a wrong addition is a redundant test (no loss of safety); the worst case of a wrong removal is a
  lost guard (exp3). So Deepen can be a mostly-autonomous converge loop, while removal stays human-
  approved. The one irreducible human gate in expansion is Broaden's intent-vs-defect classification.

## 6. Specify — the rule as single source (1 rule = 2 reflections) — implemented

Broaden proposes *which technique*; but a test and a model check both verify the same **rule**, and if
the rule lives only in a proposal they drift apart. `harness-rule-reflect` (TAKT sequence
specify → reflect, persona `spec-author`, methodology [spec-rules.md](../spec-rules.md)) closes that:
it writes the rule once in the mini-language (`docs/spec/<area>.md`, an ID) and reflects it into an
implementation **test** and — for an order/state or concurrency rule — an Alloy model **assert**, with
a traceability chain `R-n → test → assert`. Behaviour-derived rules start as DRAFTs needing a human
intent/defect classification (never freeze a bug as spec); reflections are scaffolds, not wired into
CI. This is what lets tests *and* model checks grow together as code is implemented.

Proven on the same Rust consumer (integrated with the Broaden run): the TabSet active-tab invariant
became rule **R-1** `invariant "active, if Some(id), satisfies id ∈ tabs"` (canonized — it is the
code's stated doc-comment intent), reflected into `tests/tabset_pbt.rs::prop_tabset_invariant` (a
stateful PBT that **compiles and passes**) and `spec/tabset.als` (three Alloy preservation asserts),
with R-1 → test → assert recorded. Four adjacent behaviours (B1–B4: duplicate-open, close-absent,
fallback policy, activate-no-op) were left as DRAFT rules with the intent/defect question stated — not
canonized. So one implemented cluster grew a documented rule + a test + a model, together.

A second cluster (an input-space `Percent::clamp` invariant) confirmed accumulation and correct
differentiation: rules accumulated (`docs/spec/` gained `percent.md` beside `tabset.md`), and the
system chose **plain PBT, no model** for the input-space rule (vs stateful PBT + Alloy for the
order/state one) — applying test-selection-roi per shape, not templating. That run also surfaced a
real defect — a `#[ignore]`d scaffold that did not compile breaks the build, since ignored tests are
still built — so the `reflect` step now ENFORCES compilation with a `scaffold-compiles` command gate. That gate
runs the shipped core script **`check-test-compiles.sh`** (auto-detects rust/go/ts/python and runs a
build-no-run — `cargo test --no-run` / `go test -run=__nomatch__` / `tsc --noEmit` / `compileall` —
or honours `TEST_COMPILE_CMD`), so it is one tested, installed command, not an inline stack-detector.

## 7. Where it sits in the development workflow

In [development-workflow.md](../development-workflow.md), the outer loop's step 6 "execute" gains an
additive direction: `strengthen` is a runnable converge loop (Deepen), "add new verification" is
Broaden, and "document the rule that drives the test + the model" is `harness-rule-reflect`. The outer
loop is therefore **expand (Deepen / Broaden / rule-reflect) ⇄ prune (`harness-evaluate-cycle`)** at
the same periodic cadence — the additive and subtractive forces of the second-order loop.
