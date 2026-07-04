# Development workflow with gatecrate — the two-loop model

How gatecrate's pieces compose into an end-to-end development lifecycle. Read this first to see
*what runs when, which asset does what, and where a human decides*. Japanese:
[development-workflow.ja.md](./development-workflow.ja.md).

This is the lifecycle **overview** (the top of the pyramid). The detailed methodology docs hang off
it: [harness-roi-evaluation.md](./harness-roi-evaluation.md) (how to evaluate/prune),
[test-selection-roi.md](./test-selection-roi.md) (which verification to build), and the skills
[gatecrate-setup](../.claude/skills/gatecrate-setup/SKILL.md) /
[gatecrate-evaluate](../.claude/skills/gatecrate-evaluate/SKILL.md).

## The core idea: two nested loops at two cadences

A harness has a **first-order loop** (it constrains the *code*) and a **second-order loop** (it
constrains *itself*). They run at different speeds, and conflating them is the usual mistake.

In Evolutionary Architecture terms (Ford / Parsons / Kua), the first-order loop is the set of
**fitness functions** guiding incremental change, and the second-order loop is what the book
leaves as a manual practice ("review your fitness functions periodically") turned into machinery:
the probe tests that each preventive fitness function still measures, classification decides how a
function's value is even read (a prevention gate's zero firings are healthy; a detection gate's
are a removal signal), and ROI verdicts propose pruning — a human approves. Two operational
consequences follow: prefer **ratchet-form** functions (derivative predicates, "no worse than the
baseline") over absolute floors, because a floor that fails on day one gets the function removed
and its fitness with it; and split what is machine-decidable (exit codes) from what is judgment
(semantic classification) — the agent sits between the two, never above the human.

```
┌─ INNER loop — fast, every PR ─────────────────────────────┐
│   2. agent implements  →  3. CI runs gates  →  read result │  ← fix the CODE
│        ▲────────────────────────────────────────┘         │
└───────────────────────────────────────────────────────────┘
            │  (periodically, once history has accrued)
            ▼
┌─ OUTER loop — slow, periodic, NON-BLOCKING ───────────────┐
│   4. evaluate the harness → 5. decide → 6. execute         │  ← fix the HARNESS
│        └───────────────► feed back into config / profile ──┘
└───────────────────────────────────────────────────────────┘
```

**Why two cadences (why → therefore):** the outer loop's ROI evaluation needs *accrued evidence*
— fired incidents, CI-cost history, probe results. Running it every PR would be noise. **Therefore**
the outer loop runs occasionally, and **must not block** the inner loop — otherwise the meta-harness
becomes a second product that starves feature work (a real failure mode the methodology warns about).
This is why **step 6 runs in parallel with the next cycle's step 2**: the slow loop never gates the
fast one.

## The six steps, mapped to assets

| # | Step | Asset | Cadence |
|---|---|---|---|
| 1 | Build the CI harness | `gatecrate-setup` skill + `install.sh` + profiles; **`test-selection-roi.md` picks which verification** (PBT / stateful PBT / mutation / model check) | once (re-profile occasionally) |
| 2 | Agent implements code | Claude Code / any agent | every change |
| 3 | CI runs | prevention + detection gates, **survival probe** (`probe-gate-liveness.sh`), doc-currency, … | every PR |
| 4 | **Evaluate the harness** | `collect-gate-history.sh` (fires/cost) + probe + git churn → **`gatecrate-evaluate`** → ROI report (5 verdicts) | periodic |
| 5 | Decide add / modify / remove | the 5 verdicts; `test-selection-roi.md` for *which technique to add* | periodic |
| 6 | Execute the decision | strengthen=add tests · consolidate=automate · remove=human-approved PR · repair DEAD gates=`harness-liveness-converge` (TAKT) | periodic, parallel to next #2 |

Steps 4→6 (the outer loop) are packaged as runnable artifacts. The loop has two halves in tension:
**prune** (keep it lean) and **expand** (grow coverage).

- **Prune** — `harness-evaluate-cycle` (measure → evaluate → route): one invocation writes a dated
  report with the five verdicts and routes the actions (repairs to `harness-liveness-converge`,
  removals as human-approved proposals).
- **Expand** — three artifacts: `harness-coverage-deepen` (Deepen) is a converge loop that adds tests
  to KILL surviving mutants until the mutation gate is clean (grows the suite from a mechanical
  signal); `harness-coverage-expand` (Broaden) is a scan→assess→propose sequence that proposes a
  *new* technique for a changed cluster whose risk shape has no verification; and
  `harness-rule-reflect` documents the **rule** that technique verifies (mini-language, an ID) and
  reflects it into a test *and* — for an order/state rule — an Alloy model assert (1 rule = 2
  reflections, so tests and models grow from one source). Proposal/scaffold-level, with a human
  intent-vs-defect gate. Design: [design/expansion-loop.md](./design/expansion-loop.md),
  [spec-rules.md](./spec-rules.md).

TAKT orders and audits each pass; the judgment stays the persona's. Expansion can be more autonomous
than pruning (adding a test is safe; removing a gate is not) — and the two halves balance: expand
adds, prune trims.

## Two kinds of "evaluation" — do not conflate

Step 4 is **not** "read the CI result to fix the code." That — *test failed → fix code* — is the
**inner** loop (part of 2→3). Step 4 is **evaluating the harness itself**: *is this gate earning its
keep? is it silently broken? is it redundant?* Pin step 4 to `gatecrate-evaluate` and the ambiguity
disappears.

## Human gates live in the outer loop

The outer loop is **not fully autonomous** — by design:

- **removal / consolidate are proposals**; a human approves them. Safety gates (secrets, forbidden
  permissions) are never auto-removed by a metric.
- **Escalation-only gates are excluded from auto-repair.** A gate whose fix is reserved for a human
  (security-owned policy, or a vanished-premise removal) carries `# gatecrate-scope: escalation-only`
  and is skipped by the converge loop (`--repairable-only`). This is the structural fix from the exp3
  finding: a converge-to-green loop cannot be trusted to *not* edit a human-owned gate, so it never
  sees one. Step 6 therefore has two branches: **auto-repairable** vs **escalate to a human**.

## The feedback edge: 6 → 1

The outer loop is a ring, not a line. A `consolidate` / `removal` finding feeds back into the
project's **profile choice** (which tier of harness to run) — see harness-roi-evaluation.md
"Connection to profiles". So executing step 6 reshapes the harness the next cycle's step 1/2 runs on.

## Worked example (this repo, 2026-06-14)

One complete trip around the **outer** loop, on gatecrate itself:

- **4 measure**: 40 CI runs — all gates `fires=0`, ShellCheck ≈60% of gate-seconds (cost outlier);
  survival probe: all prevention gates ALIVE.
- **5 decide**: Axis 1 → `removal = 0` (every layer cheap or unique). Axis 2 → one
  `consolidate-candidate`: **EN/JA docs kept in sync by manual discipline**, no machine enforcement.
- **6 execute**: shipped `check-doc-currency.sh` (fails a PR that edits one side of a `*.md`/`*.ja.md`
  pair) and wired it into CI — replacing a manual discipline with an automated gate.

Full report: [evaluations/2026-06-14.md](./evaluations/2026-06-14.md). This is the second-order loop
working: the harness measured its own maintenance load and closed the gap.

## Where each doc fits (the pyramid)

| Altitude | Doc | Answers |
|---|---|---|
| Overview (here) | development-workflow.md | the lifecycle: what runs when |
| Why the kit exists | [ROADMAP.md](../ROADMAP.md) | why portable, in what order |
| Build-time selection | [test-selection-roi.md](./test-selection-roi.md) | which verification earns CI inclusion |
| Evaluate & prune | [harness-roi-evaluation.md](./harness-roi-evaluation.md) | keep / strengthen / consolidate / remove |
| Do it (agents) | gatecrate-setup / gatecrate-evaluate skills | step 1 / steps 4–6 |
