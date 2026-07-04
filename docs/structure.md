# Structure

How gatecrate is organized and why. Japanese: [structure.ja.md](./structure.ja.md).

This document is the canonical description of the repository layout and the
consumption mechanism. Read it before adding scripts, a new adapter, or changing
how scripts resolve their config.

## The 3-layer model (and why)

A reusable harness has to separate three things that change for different reasons:

| Layer | Changes when… | Lives in |
|---|---|---|
| **Generic core** | a universally-true hygiene rule changes (e.g. "no secrets") | `core/` |
| **Stack adapter** | a stack's tooling changes (e.g. JVM test runner flags) | `adapters/<stack>/` |
| **Project config** | a single project's values change (package id, thresholds) | `harness.config.sh` **in the consumer**, never in the kit |

Keeping these apart is what makes the kit portable: a consumer pulls core +
the adapter for its stack, and supplies only its own values. Project specifics
never enter the kit, so one kit serves many projects.

## Directory layout

```
gatecrate/
├── core/                       # Generic, stack-agnostic layer
│   ├── scripts/                #   40+ stack-agnostic scripts: hygiene gates, metrics, ES grammar, harness self-checks
│   ├── workflows/              #   generic stack-agnostic CI (ci.yml, dashboard.yml, merge-integrity.yml, …)
│   └── docs/                   #   core layer notes
├── adapters/
│   ├── android-jvm/            # Android + JVM stack adapter
│   │   ├── scripts/            #   30+ build/test/release scripts (mutation, smoke, build-*, …)
│   │   ├── workflows/          #   ci.yml, mutation.yml, device-smoke.yml
│   │   ├── gradle/             #   build.gradle template
│   │   └── README.md           #   adapter notes
│   ├── python/                 # Python adapter (uv): run-tests.sh + run-mutation.sh + ci.yml
│   ├── go/                     # Go adapter: run-tests.sh (go test/coverage) + ci.yml
│   ├── typescript/             # TypeScript adapter (vitest): run-tests.sh + ci.yml
│   ├── rust/                   # Rust adapter (cargo-llvm-cov): run-tests.sh + ci.yml
│   ├── kotlin/                 # Kotlin adapter (Gradle + kover): run-tests.sh + ci.yml
│   ├── haskell/                # Haskell adapter (cabal): run-tests.sh + ci.yml
│   └── lean4/                  # Lean4 adapter (lake build = typecheck + proof check)
├── templates/                  # consumer scaffolds (copied/adapted per project)
│   ├── harness.config.sh.example   # config interface (SHELL — sourced; copied to harness.config.sh by install.sh)
│   ├── hooks/                  # Claude Code Stop hook (spec-test mutation gate) + settings
│   ├── kiro-steering/          # cc-sdd custom steering (spec-test loop)
│   ├── spec/                   # rule-doc skeleton (README + area.md) + models/example.als.example
│   ├── takt/                   # TAKT orchestration: config + workflows (evaluate-cycle / liveness-converge / rule-reflect) + personas
│   └── gate-groups.tsv.example # collect-gate-history logical-gate relabel map
├── .claude/skills/             # kit agent skills: gatecrate-setup, gatecrate-evaluate, alloy-spec-model-generator
├── profiles/                   # installer profile definitions (minimal / standard / full)
├── sync-manifests/             # whitelist of kit-managed files per stack (android-jvm.yaml)
├── scripts/                    # kit-internal tooling (sync-check.sh)
├── install.sh                  # installer entry point (profile selector)
├── .github/workflows/
│   ├── ci.yml                  # the kit's OWN CI (sh -n + shellcheck + manifest integrity)
│   └── sync-propose.yml        # template a consumer copies to receive kit updates as PRs
├── ROADMAP.md  CHANGELOG.md  CONTRIBUTING.md  README.md (+ .ja)
```

Counts are approximate by design — exact numbers rot as the kit grows; the
committed dashboard (`docs/harness-status.md`) is the per-gate inventory.

## Consumption mechanism (how a kit script runs in a consumer)

A kit script must run **unchanged** in two places: here (e.g.
`adapters/android-jvm/scripts/check-file-sizes.sh`) and installed into a
consumer (`scripts/check-file-sizes.sh`). Two rules make that possible:

1. **Repo root via git, not relative depth.** Scripts resolve the root with
   `git rev-parse --show-toplevel` (falling back to a relative path). The path
   depth differs between the kit and a consumer, so a hardcoded `../../..` would
   break on install; git-resolution is depth-independent. This is also what lets
   kit↔consumer sync be **diff-free** (the byte-identical file works in both).

2. **Config via `harness.config.sh`, sourced if present.** Scripts read
   environment variables and source `harness.config.sh` from the repo root when
   it exists. The kit has no such file (so defaults apply); a consumer supplies
   its values there. Config is plain shell (sourced with `.`) because the scripts
   read env vars — YAML could never wire them.

> Status: every core script now uses this consumption model (`check-file-sizes.sh`
> was the pilot; the migration tracked in [ROADMAP.md](../ROADMAP.md) P2 is done for
> `core/`). Scripts with project-specific *logic* (not just values), e.g.
> `run-mutation-tests.sh`, expose it through config seams instead.

## Versioning

SemVer. A **MAJOR** bump is required when a change tightens a ratchet (lowers a
threshold) or otherwise breaks a consumer; additive scripts/config are MINOR;
fixes are PATCH. Every tag needs a `CHANGELOG.md` entry. See
[CONTRIBUTING.md](../CONTRIBUTING.md).
