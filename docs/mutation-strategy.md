# Mutation strategy: diff-on-PR + full-on-trunk (A+B), and the branch strategy it needs

## What this doc is for

Mutation testing is the most valuable *and* the most expensive gate a consumer harness ships.
Run in full on every PR it costs minutes; the feedback is slow and the gate becomes the thing
people route around. This doc records the strategy gatecrate's adapters use to keep it fast
**and** trustworthy — and, crucially, the **branch strategy that strategy presupposes**, because
without it the speedup quietly evaporates.

The shape, in one line: **PR mutates only the diff (fast); the trunk is mutated in full on a
schedule (complete).** A consumer reading this should understand why both halves exist, why one
without the other is unsafe, and how to wire it.

---

## 1. Why neither half works alone

- **Full mutation on every PR (the default before this)** is correct but slow: it re-mutates the
  whole codebase to prove a 10-line change. Cost scales with the *codebase*, not the *change*.
- **Diff-only mutation on every PR** is fast but has a **structural blind spot**: it mutates only
  the changed lines. A PR that *weakens a test*, or changes shared code so that an **unchanged**
  production file is now under-tested, leaves a surviving mutant **in code the diff never touches**
  — so diff-mode cannot see it. Relying on diff-mode alone slowly rots coverage of the stable core.

So: **A — diff on PR** (fast feedback that *new* code is mutation-covered) **plus B — full on the
trunk, on a schedule** (the backstop that catches regressions in *unchanged* code). A is the inner
loop; B is the outer loop — the same two-loop shape as the rest of gatecrate's harness.

---

## 2. The branch strategy this requires (the part that's easy to miss)

A+B is not just two CI jobs; it **presupposes a branching model**, and degrades silently without it:

- **Trunk-based, short-lived feature branches off `main`.** Branch, change a little, PR, merge,
  delete — hours to a couple of days, not weeks.
- **The PR diff is measured against the merge base with `main`** (`origin/main` by default; see
  `MUTATION_DIFF_BASE`). That is what makes "the diff" mean "what this PR adds."

Why the branch model is load-bearing, not a preference:

| If you instead… | what breaks |
|---|---|
| Keep long-lived branches | the diff vs `main` grows huge → diff-mutation approaches **full** cost → the A speedup evaporates. Short branches keep the diff (and the cost) small. |
| Let `main` go stale / rarely merge | the base is old → diff-mode mutates already-merged code, or misses interactions → wrong scope. A fresh trunk keeps the scope honest. |
| Skip the scheduled full run (B) | the §1 blind spot is unguarded → coverage of the stable core rots invisibly. B is **non-negotiable**, not optional. |
| Branch off a feature branch (stacked) | the merge base is not `main` → set `MUTATION_DIFF_BASE` to the real parent, or the diff scope is wrong. |

**Recommendation:** trunk-based development, short-lived branches, `main` protected, **diff-mutation
required on PR**, **full-mutation scheduled nightly on `main`** (and as a release gate). This is the
branch strategy that makes A+B both fast and safe.

---

## 3. The contract — `MUTATION_SCOPE` (one engine, every stack)

The scope decision lives once in `core/scripts/mutation-scope.sh`; every adapter's
`run-mutation.sh` calls it and maps the result to its tool's flag. Back-compatible: **default is
`full`**, so existing consumers are unchanged until they opt in.

| Env | Meaning |
|---|---|
| `MUTATION_SCOPE` | `diff` \| `full` (default `full`) |
| `MUTATION_DIFF_BASE` | base ref for `diff` (default: `origin`'s default branch, else `main`) |

`mutation-scope.sh` commands: `mode` (→ `diff`/`full`), `base` (resolved ref), `changed [<glob>…]`
(changed files vs base, filtered), `diff` (unified diff, for tools that take one). Caller contract:
`full` → mutate everything; `diff` → if `changed` is empty, **SKIP** (no source changed); else pass
the diff/files to the tool's incremental flag.

---

## 4. Per-stack diff support (honest — it varies by tool)

B (scheduled full) is uniform and easy everywhere. A (diff) depends on what each mutation tool
supports natively. This table is the honest state; "path-scoped" = we feed the tool the changed
files/dirs rather than a native diff; "schedule-first" = native per-line diff needs an extra plugin,
so lean on B and treat A as best-effort.

| Stack | Tool | Diff mechanism | Support |
|---|---|---|---|
| rust | cargo-mutants | `--in-diff <diff>` | **native** |
| typescript | Stryker | `--since <base>` | **native** |
| python | mutmut | `--paths-to-mutate <changed.py…>` | path-scoped |
| go | gremlins | scope to changed package dirs | path-scoped |
| kotlin / android-jvm | PIT (gradle-pitest) | `targetClasses` from changed classes | best-effort (schedule-first; native per-line diff needs an arcmutate/pitest-git plugin) |
| lean4 / haskell | — | no mutation gate shipped | n/a |

Where A is only best-effort, **B still applies fully** — the stable core is still covered nightly,
so correctness never depends on the weakest A.

---

## 5. How it wires in CI

- **PR job** (existing `pull_request` trigger): run mutation with `MUTATION_SCOPE=diff` and
  `MUTATION_DIFF_BASE=origin/<base>`. Required/blocking. Skips cleanly when the PR changes no source
  the tool mutates.
- **Scheduled job** (`schedule:` cron, nightly, on `main`): run with `MUTATION_SCOPE=full`. Track
  failures (issue / escalation); optionally a release gate. Not on the PR critical path.

Consumers who want the old behavior do nothing — `full` is the default. Opting into A+B is setting
the two envs in the PR job and adding the scheduled full job.

---

## 6. Status

`mutation-scope.sh` (the engine) + its behavior test ship in core. Adapter `run-mutation.sh` scripts
and workflows adopt it per the table in §4. See [`ROADMAP.md`](../ROADMAP.md) and
[`docs/development-workflow.md`](./development-workflow.md) (the inner/outer-loop model this mirrors).
