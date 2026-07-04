# Choosing verification that earns a place in CI (ROI-based selection)

How to decide **which test or model check is worth wiring into a project's CI** — and
which would be ritual. Japanese: [test-selection-roi.ja.md](./test-selection-roi.ja.md).

gatecrate's value is **not** "run tests." Any stack can run tests. Its value is helping
you *select, by ROI, the meaningful tests and model checks that become CI parts* — the
ones that catch a failure mode the code can actually exhibit, at a cost below their
value. This guide is the **build-time selection** procedure (the `evaluate → profile →
consume` front of the proven flow). It complements:

- [profiles](../profiles/) — *which tier* to install for a project's shape;
- [harness-roi-evaluation.md](./harness-roi-evaluation.md) — *re-judge and prune* layers
  after they accrue history (the second-order loop).

Selection adds the right layer; evaluation keeps the set honest. This doc is the former.

## Core principle — a technique earns CI inclusion only if all three hold

1. **It catches a failure mode the code can actually exhibit** — not a hypothetical one.
2. **It is implementation-direct, or its model-code gap is worth paying** (see below).
3. **Its continuous cost < its value** — and the more the stack's native toolchain already
   provides it for free, the cheaper it is to ship (gatecrate's value ∝ toolchain
   fragmentation: a JVM PITest/emulator gate absorbs real pain; `cargo test` already did it).

## The ladder — cheap/direct at the bottom, expensive/indirect at the top

| Technique | Catches | Implementation-direct? | When it earns its place |
|---|---|---|---|
| Example-based tests | specific known cases | yes | always — the floor |
| Property-based testing (PBT) | input-space gaps (unhandled inputs, invariant breaks) | yes | AlwaysValid invariants, pure calc/transform, parsers |
| Stateful / model-based PBT | **order/state** bugs (a specific operation sequence) | yes (runs the real code) | a cluster with order-dependent state |
| Mutation testing | **weak tests** (green that doesn't prove detection) | yes (second-order on tests) | branch/calculation-heavy logic |
| Model checking (TLA+/Alloy) | unimaginable interleavings, exhaustively within bounds | **no — model-code gap** | concurrency / distributed / complex state machine, at *design* time |

**The model-code gap (why model checking is not a CI regression gate).** TLA+/Alloy verify
a *model* written separately from the implementation. A green check proves the model, not
the code, and creates a second thing to keep in sync. So model checking is a **design-phase
harness**, not a per-PR regression gate. AWS used TLA+ for *protocol design* (DynamoDB/S3),
not regression prevention. Its 80%-value, gap-free substitute for most repos is **stateful
PBT**: random operation sequences applied to both a simplified reference model and the real
implementation, asserting they agree every step — exhaustive-ish exploration *while running
the actual code*, with shrinking to a minimal failing sequence.

## Decision procedure

```
Q1. Does the failure mode depend on ORDER / STATE (a sequence of operations)?
      No  → input-space invariant → PBT (or example tests if the space is small).
      Yes → stateful / model-based PBT by default.
Q2. Is the logic branch-heavy or calculation-heavy, where "tests green" does NOT
    prove the tests would catch a fault?
      Yes → add a mutation gate (ratchet the floor up; never lower it to go green).
            Skip on glue/i18n/trivial code — mutation there is noise, not signal.
Q3. Is it concurrency, a distributed protocol, or a safety-critical state machine
    where exhaustive interleaving exploration genuinely pays?
      Yes → model checking at DESIGN time, mirrored into an implementation test
            (1 rule = 2 reflections, below). Pay the model-code sync cost ONLY here.
      No  → do not add model checking; stateful PBT already covers ordering.
Q4. Fragmentation check (gatecrate-specific): does the stack's native toolchain
    give this for free (cargo test/mutants, lake build = proof)?
      Yes → near-free to ship; include it, but know the kit added little.
      No  → the gate absorbs real fragmentation pain — this is where gatecrate earns
            its keep (PITest config, BuildConfig stubs, emulator wiring, SDK).
```

## 1 rule = 2 reflections

When a verification rule is worth keeping, reflect it into **both** layers, so the model
never drifts ahead of the code:

| Reflection | Role |
|---|---|
| Alloy `assert` / model invariant (design layer) | exhaustive state-space check: "can this order break it?" |
| Example test or PBT property (implementation layer) | rejection signal on the real code, fired every PR in CI |

A rule reflected only into the model gives "smart model, unguarded implementation." A rule
reflected only into a test loses the exhaustive ordering check. Keep both, traceable:
`scenario-id → rule-id → assert-name → test-name`.

## The domain-knowledge-deepening loop (how new checks are born)

Selection is not a one-time act; meaningful checks are *discovered*. The loop that turns a
discovery into a CI part — without canonizing bugs:

```
① Explore: stateful PBT (machine) + agent exploration (knowledge) surface a surprise.
② Classify gate: intent or defect? — a PRODUCT judgement. The agent files a
   `proposed-rule` with evidence; a human approves. (Never auto-canonize observed
   behavior: characterization tests can freeze a defect as a spec.)
③ Specify: record the rule in mini-language form (invariant/policy, with an ID).
④ Two reflections: Alloy assert (design) + test/PBT property (implementation).
⑤ Code: fix the implementation only when the verdict was "defect."
→ re-explore the corrected behavior.
```

The one inseparable judgement (intent vs defect) is a human/persona call; everything around
it is mechanical. This is why model-checking and PBT are *tools in the loop*, not the loop.

## The legacy (test-sparse) entry point — a ratchet, not an absolute floor

The ladder and decision procedure above assume tests **already exist** and pick *which* verification
to add. But a **legacy codebase with no (or very few) tests** has a prior problem: an absolute
coverage floor (`coverage>=80`) fails on day one, the consumer's only move is to **rip the gate
out**, and the test lane delivers zero value while the safety net never grows.

Why an absolute floor fails here: it is a **level predicate** ("you are good enough") that legacy
can't satisfy on day one. What works on legacy is a **derivative predicate** ("not getting worse /
what you touched got better") — a ratchet.

So the entry point is `check-diff-coverage.sh` (profile: brownfield):

- **What it demands**: coverage only on the lines **added/changed in this PR**
  (`DIFF_COVERAGE_THRESHOLD`, default 80). The legacy mass is never touched — zero adoption
  friction. This is the mechanical enforcement of the boy-scout rule (leave touched code better).
- **Input**: a coverage report the consumer's tests produce. The decision (git diff's changed
  lines ∩ coverage report) is stack-agnostic; only the report format is parameterized via
  `COVERAGE_FORMAT`:

  | stack | producing the report | COVERAGE_FORMAT |
  |---|---|---|
  | JVM/Kotlin/Android | `./gradlew koverXmlReport` / `jacocoTestReport` | `jacoco` |
  | rust | `cargo llvm-cov --lcov --output-path lcov.info` | `lcov` |
  | typescript | `vitest run --coverage` (add the `lcov` reporter) | `lcov` |
  | python | `coverage lcov` after a pytest-cov run | `lcov` |
  | go | `go test -coverprofile=coverage.out ./...` | `gocover` |
- **Known limit**: a changed line absent from the report (e.g. a brand-new file never loaded by any
  test) is treated as un-instrumented and drops out of the denominator — no coverage is demanded of
  it. This is inherent to diff-coverage; pair it with a test-presence gate if new-file gaps hurt.
- **Promotion path**: as PRs land, the baseline grows. Once it has, raise to standard (absolute
  floor) then full (mutation).

The selection questions (Q1-Q4) start to bite *after* brownfield has grown a safety net. Until
then, "get the diff green first" comes before "which technique."

## Anti-patterns (NEVER)

- **Model checking as a CI regression gate** — model-code gap means a green model with an
  unverified implementation, plus a sync cost paid every change.
- **Using PBT for mutation's job (detection power) or vice versa** — they measure different
  things (implementation correctness vs test strength).
- **Canonizing observed-but-wrong behavior** as a spec — route every discovery through the
  intent-vs-defect classification gate first.
- **Adding a heavy technique the native toolchain already provides** — ritual, not value.
  Spend the effort where the toolchain is fragmented.

## Connection to the rest of gatecrate

- [gatecrate-setup](../.claude/skills/gatecrate-setup/SKILL.md) uses this at `evaluate /
  profile / consume` to choose **which** verification to wire into a new consumer.
- [gatecrate-evaluate](../.claude/skills/gatecrate-evaluate/SKILL.md) re-judges those layers
  later (keep / strengthen / consolidate / remove) once CI history exists.
- [harness-roi-evaluation.md](./harness-roi-evaluation.md) is the methodology the evaluate
  skill executes. Selection (this doc) and pruning (that doc) are the two halves of keeping
  a *reusable* harness from over-harnessing the projects that adopt it.
