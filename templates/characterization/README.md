# Characterization (golden-master) bootstrap — refactor legacy safely

Copy this directory's files into your repo when you want to **refactor a legacy cluster that has no
tests**. It supplies the missing safety net: pin the cluster's *current* behavior first, then change
the code under a green guard. It closes the gap that `check-diff-coverage.sh` alone cannot —
diff-coverage ensures your *new* lines are tested (forward ratchet), but only a characterization
test protects the *existing behavior* you are trying to preserve.

## Why you need this before refactoring

- **Refactoring** = change structure, keep behavior. To prove behavior is unchanged you need a test
  of the **current** behavior, captured **before** you touch the code.
- **diff-coverage** fires on lines you **already changed** — too late to tell you that you broke
  behavior. It and characterization point in opposite directions in time; you need both.
- Practical consequence: write characterization tests **in a separate, behavior-preserving PR
  first**. They cover the lines a later refactor will move, so the refactor's diff stays green —
  and, more importantly, breakage shows up as a failing snapshot.

## Files

Pick the helper that matches your stack — **Java** (`Approvals.java`) for pure-Java legacy projects
(Maven/Gradle + javac), **Kotlin** (`Approvals.kt`) for Kotlin/Android. Both are dependency-free
(java.nio only) and behave identically; ship only the one you use.

| File | Copy to | Role |
|---|---|---|
| `Approvals.java.example` | `src/test/java/characterization/Approvals.java` | dependency-free golden-master helper (Java) |
| `ExampleCharacterizationTest.java.example` | `src/test/java/characterization/<Cluster>CharacterizationTest.java` | example: pin a cluster's behavior (Java) |
| `Approvals.kt.example` | `src/test/kotlin/characterization/Approvals.kt` | golden-master helper (Kotlin/Android variant) |
| `ExampleCharacterizationTest.kt.example` | `src/test/kotlin/characterization/<Cluster>CharacterizationTest.kt` | example (Kotlin variant) |
| `approve-characterization.sh.example` | `scripts/approve-characterization.sh` | promote reviewed `received` → `approved` |

Also add `*.received.*` to `.gitignore`, and adopt the `check-no-received-approvals.sh` gate
(core) — it rejects any committed `*.received.*` so an **un-reviewed** snapshot can never enter the
repo as the spec.

## The loop

```
0. ANALYZE   — understand before touching. Build a domain map of the cluster.
               gatecrate tools: es-lint / es-render (event-storming grammar gate),
               bounded-context-analyzer. Decide concept model FIRST (entity vs rule).
1. PIN       — write a characterization test (ExampleCharacterizationTest) over a WIDE input
               spread. Run it -> it writes <name>.received.txt and fails.
2. REVIEW    — read the received snapshot. Intent vs defect: is this behavior CORRECT, or a bug?
               (The characterization trap: approving blindly freezes a bug as the spec.)
                 - correct -> approve (approve-characterization.sh <name>); commit ONLY .approved.txt
                 - bug     -> do NOT approve. Record it; fix later as a separate, intended change.
3. REFACTOR  — now change structure in small steps, keeping the snapshot green. The green snapshot
               is your safety net. gatecrate tools: refactoring-specialist agent, extract-* skills.
4. RATCHET   — diff-coverage requires the new structure's changed lines to be covered (your
               characterization + any unit tests satisfy it). Baseline grows PR by PR.
5. PROMOTE   — once coverage has grown, raise the gate: brownfield (diff-coverage) -> standard
               (absolute floor) -> full (mutation). See ../../docs/test-selection-roi.md.
```

Step 2 is the one irreducibly human judgement (intent vs defect); everything around it is
mechanical. That is the same principle the rest of gatecrate follows — see
[`docs/spec-rules.md`](https://github.com/Yos-K/gatecrate/blob/main/docs/spec-rules.md) on not
canonizing observed-but-wrong behavior.

## Limits

- A golden master pins **observed output**, not intent — it is only as good as your input spread
  and your step-2 review. Widen inputs to cover the branches you don't understand yet.
- It is a **safety net for refactoring**, not a substitute for real unit tests of intended
  behavior. Once a cluster is understood, replace broad snapshots with focused example/PBT tests.
