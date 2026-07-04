# gatecrate

[![CI](https://github.com/Yos-K/gatecrate/actions/workflows/ci.yml/badge.svg)](https://github.com/Yos-K/gatecrate/actions/workflows/ci.yml)

A portable kit of CI / quality-gate scripts — 3-layer design extracted from a production project
([localmd-reader](https://github.com/Yos-K/localmd-reader)).

> **Japanese README**: [README.ja.md](./README.ja.md)
>
> **Gate status at a glance:** the CI badge above is green when every gate passes on `main`. The
> per-gate dashboard (type / liveness / ROI verdict) is committed at
> [`docs/harness-status.md`](./docs/harness-status.md) (visible right here in the repo) and also
> renders on each CI run's **Summary** page. How it works:
> [`docs/harness-dashboard.md`](./docs/harness-dashboard.md).

## What is gatecrate?

gatecrate is a library of CI / quality-gate scripts (hygiene checks, test &
mutation gates, build/release helpers) spanning 8 stacks. The default way to use it is
**fire-and-forget — you vendor the scripts and they become yours**:

- `install.sh` **copies** the scripts you choose into your project's `scripts/`. From that
  moment **they are your files** — commit them, edit them, delete them. No version pinning, no
  manifest, no obligation to track or sync with this repo.
- The per-project wiring a static installer can't do (which scripts to keep, `harness.config.sh`
  values, mutation floors, CI wiring) is handled by the **gatecrate-setup agent skill** — point
  Claude Code / Codex at your project and it does the judgment.

**In Evolutionary Architecture terms** (Ford / Parsons / Kua): gatecrate is a portable kit of
**fitness functions**, plus the second-order loop that keeps the fitness functions themselves fit.
Each gate is an automated, triggered fitness function; the probe is a *fitness function for
fitness functions* (it injects a synthetic violation to prove a silent prevention gate still
measures); ROI verdicts prune the set; and where an absolute floor would get a gate removed on a
legacy codebase, gatecrate ships **ratchet-form functions** (derivative predicates — "no worse
than the baseline") so the functions survive contact with reality. The two-loop model behind this:
[docs/development-workflow.md](./docs/development-workflow.md).

You don't need anything under "Advanced" unless you run several projects off one shared kit.

## Two ways to use it

| | **Fire-and-forget (default)** | **Stay in sync (opt-in, for teams)** |
|---|---|---|
| Who | Anyone who wants good gates on a project | One owner running several projects off one kit |
| After install | The scripts are **yours** — modify freely | Track the kit version; receive updates as PRs |
| Setup | `install.sh` — done | + add `sync-manifest.yaml` and a sync workflow |
| Obligation | **None** — no upstreaming, no version tracking | Opt-in: pull updates, optionally contribute back |

If you just want gates on your repo, **stop after Quick Start**. The sync machinery
(`sync-manifest`, `sync-propose`, version tracking) is **entirely optional** and exists only for
the multi-project case — see the Advanced section at the bottom.

## Quick Start

### Install as a plugin (recommended — Claude Code)

```
/plugin marketplace add Yos-K/gatecrate
/plugin install gatecrate@gatecrate
```

This installs gatecrate's **agent skills** — `gatecrate-setup`, `legacy-domain-extraction`,
`gatecrate-evaluate`, `alloy-spec-model-generator`. Then run **`gatecrate-setup`** on your project:
it analyzes the repo and wires the harness for you — copying the gates (bundled at
`${CLAUDE_PLUGIN_ROOT}`) into your project's `scripts/`, generating `harness.config.sh`, and
configuring CI. The per-project judgment a static installer can't do is handled by the skill.

**Updating**: `/plugin marketplace update gatecrate` pulls the latest. The plugin pins **no `version`**,
so it tracks the repo's commit — refreshing the marketplace always gets `main`'s latest (no version bump
needed). For a guaranteed clean re-pull: `/plugin uninstall gatecrate@gatecrate` then re-install.

> Codex: the same skills are usable — add this repo to Codex's skill/agent directory (or run the
> shell installer below). Native marketplace install is Claude Code's mechanism. See
> [docs/usage.md](./docs/usage.md).

### Shell installer (no agent / CI bootstrap)

```sh
sh install.sh --profile auto --target /path/to/your/project
```

> **Profile names**: `minimal` is stack-neutral (core gates only); `auto` detects your stack
> (pyproject.toml → python, Cargo.toml → rust, …) and is the recommended default. Note **`standard`
> is not stack-neutral — it is `minimal` + the Android-JVM adapter**; pick `python`/`go`/`rust`/
> `typescript`/`kotlin`/… (or `auto`) for other stacks.

The installer selects a profile and copies the chosen scripts into your project's `scripts/`,
then drops a config template. Set your project's values in `harness.config.sh` and wire the
scripts into CI — see [docs/usage.md](./docs/usage.md) for the full walkthrough.

**Three install paths** (pick what you need — the flags are additive):

| Goal | Command |
|------|---------|
| Fire-and-forget gates only | `sh install.sh --profile <p> --target <dir>` |
| **+ agent-driven harness loop** (installs `.claude/skills/` and `.takt/`) | add **`--with-skills`** |
| + cc-sdd (spec-driven) integration | add `--with-cc-sdd` |

`--with-skills` is what unlocks the higher-value agent path (`gatecrate-setup`, `legacy-domain-extraction`,
the TAKT loops). If you use the plugin install above, you already have the skills — `--with-skills` is for
the shell-installer route.

**After this, the scripts under `scripts/` are yours.** There is nothing else you must do — no
version to pin, no sync to run, no PRs to send back. Edit or delete them as your project needs.

## Shell & platform support

Every shipped script is **POSIX `sh`** (`#!/bin/sh`, no bashisms — enforced in CI by
`check-posix-portability.sh`). A script is *executed*, not sourced into your shell, so its shebang
picks `/bin/sh` regardless of your interactive shell:

| Shell | Supported | Notes |
|---|---|---|
| **bash** | ✅ | runs the POSIX scripts directly |
| **zsh** | ✅ | same — the shebang runs them under `/bin/sh` |
| **fish** | ✅ | `./script.sh` execs via the shebang; gatecrate never asks you to *source* a script into fish |
| **PowerShell / cmd** (Windows) | ⚠️ via a POSIX layer | cmd/PowerShell cannot run POSIX `sh` natively — use **Git Bash** (it ships with Git, already a dependency) or **WSL** |

Requirements: `git` and POSIX core utilities (`sed`, `grep`, `awk`, `find`, `mktemp`). Native on
macOS/Linux; on Windows these come with Git Bash or WSL. A few adapter scripts also need their
stack's toolchain (e.g. `cargo`, `gradle`).

## Documentation

| Guide | Contents |
|---|---|
| [docs/development-workflow.md](./docs/development-workflow.md) ([JA](./docs/development-workflow.ja.md)) | **start here** — the lifecycle overview: the two-loop model (fast code↔CI inner loop, slow harness-self-evaluation outer loop) and which asset runs when |
| [docs/usage.md](./docs/usage.md) ([JA](./docs/usage.ja.md)) | install, configure (`harness.config.sh`), CI wiring; (optional) sync & contribute |
| [docs/structure.md](./docs/structure.md) ([JA](./docs/structure.ja.md)) | 3-layer model, directory layout, consumption mechanism, versioning |
| [docs/test-selection-roi.md](./docs/test-selection-roi.md) ([JA](./docs/test-selection-roi.ja.md)) | **which verification** earns CI inclusion — PBT / stateful PBT / mutation / model check, by ROI |
| [docs/spec-rules.md](./docs/spec-rules.md) ([JA](./docs/spec-rules.ja.md)) | **document the rule** (mini-language) that drives a test *and* a model check — 1 rule = 2 reflections, traceability, intent/defect gate |
| [docs/harness-roi-evaluation.md](./docs/harness-roi-evaluation.md) ([JA](./docs/harness-roi-evaluation.ja.md)) | **evaluate / prune** installed layers over time — two axes (CI-cost removal, maintenance-load consolidation), five verdicts |
| [.claude/skills/gatecrate-setup/SKILL.md](./.claude/skills/gatecrate-setup/SKILL.md) | **agent skill** (Claude Code / Codex): set up a full harness on a project — the per-project judgment a static installer can't do |
| [.claude/skills/gatecrate-evaluate/SKILL.md](./.claude/skills/gatecrate-evaluate/SKILL.md) | **agent skill**: run the second-order loop — measure each gate, apply the five ROI verdicts, propose prune/consolidate |
| [templates/es-living-model-sample/](./templates/es-living-model-sample/) | **sample of the finished product** — open `sample-es.html` to see the 6-tab domain-model viewer (domain-neutral example) |
| [ROADMAP.md](./ROADMAP.md) | how the consumption loop is being proven and grown |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | versioning rules and PR guidelines |

## Directory Structure

```
gatecrate/
├── core/                         # Generic core (stack-agnostic — works in any project)
│   ├── scripts/                  # 40+ stack-agnostic scripts: hygiene gates, metrics, ES grammar, harness self-checks
│   ├── workflows/                # generic stack-agnostic CI (ci.yml, dashboard.yml, …)
│   └── docs/                     # core layer notes
├── adapters/
│   ├── android-jvm/              # Android + JVM stack adapter
│   │   ├── scripts/              # build/test/release scripts (mutation, smoke, build-*, …)
│   │   ├── workflows/            # ci.yml, mutation.yml, device-smoke.yml
│   │   └── gradle/               # build.gradle template
│   ├── python/                   # Python adapter (uv): pytest/coverage + mutmut + ci.yml
│   ├── go/                        # Go adapter: go test/coverage + ci.yml
│   ├── typescript/                # TypeScript adapter (vitest): test/coverage + ci.yml
│   ├── rust/                      # Rust adapter (cargo-llvm-cov): test/coverage + ci.yml
│   ├── kotlin/                    # Kotlin adapter (Gradle + kover): test/coverage + ci.yml
│   ├── haskell/                   # Haskell adapter (cabal): test gate + ci.yml
│   └── lean4/                     # Lean4 adapter (lake): build = typecheck + proof check
├── templates/                    # config template copied into the consumer
├── profiles/                     # Installer profile definitions (minimal / standard / full / per-stack)
├── sync-manifests/               # (Advanced) whitelist of kit-managed files for opt-in sync
├── scripts/sync-check.sh         # (Advanced) kit-internal sync tooling
├── .github/workflows/ci.yml      # the kit's OWN CI (sh -n + shellcheck + manifest integrity + tests)
└── install.sh                    # Installer entry point
```

Full layout and the consumption mechanism: [docs/structure.md](./docs/structure.md).

## Layer Structure

| Layer | Directory | Description |
|---|---|---|
| Generic core | `core/` | Stack-agnostic. Copy and go (40+ scripts; the per-gate inventory is [`docs/harness-status.md`](./docs/harness-status.md)) |
| Adapter | `adapters/{android-jvm,python,go,typescript,rust,kotlin,haskell,lean4}/` | Stack-specific. Eight stacks, each green on a real pull_request in a **purpose-built verification consumer** (not yet adopted by an external product), proving the core/adapter boundary is stack-agnostic |
| Project-specific | `harness.config.sh` (in consumer repo) | **Not stored in kit** — each project manages its own values |

## Profiles

Choose a profile at install time:

| Profile | Contents |
|---|---|
| **Minimal** | Core hygiene checks only (conventional commits, no secrets, file size) |
| **Standard** | Minimal + JVM test harness (test-smell detection) |
| **Full** | Standard + mutation testing and smoke tests |

`install.sh --profile auto` detects the stack (pyproject.toml → python, Cargo.toml → rust, …).

---

## Advanced: staying in sync & contributing (opt-in, for teams)

> **Skip this unless you maintain several projects from one shared kit.** A fire-and-forget
> consumer never needs anything below — the installed scripts are already yours.

The sync machinery exists for the **multi-project owner**: when you run many projects off one
kit, you want harness fixes to propagate, and improvements made in one project to flow back.
It is **opt-in** — `install.sh` does not create any of it. You turn it on by adding a
`sync-manifest.yaml` (declaring the kit version + the scripts you consume) and copying the
`sync-propose` workflow into your project.

### Sync mechanism

`sync-manifests/<stack>.yaml` is a whitelist that controls which files may propagate to consumers:

- It lists only files under `core/` and `adapters/` — never `src/**`, `harness.config.sh`, or `profiles/`.
- Updates arrive as PRs (`sync-propose.yml`), gated by the consumer's own CI before merge
  (set a `HARNESS_SYNC_PAT` so the PR triggers that CI).
- `consumed_scripts` you opt into are synced together with their script co-dependencies.
- Version bumps follow SemVer: ratchet tightening (threshold reduction) is always a **MAJOR** bump.

Step-by-step (both directions): [docs/usage.md](./docs/usage.md) §5–6, and [CONTRIBUTING.md](./CONTRIBUTING.md).

### Bidirectional contribution (consumer ⇄ kit)

gatecrate was extracted from localmd-reader (**consumer #1**, currently core-only — adapter adoption is still in progress); the relationship is bidirectional:

- **upstream (consumer → kit)**: improvements are usually made in a consumer first (that is where
  the harness runs), then ported back to the kit's generic, parameterized form. Consumer-specific
  drift (hardcoded IDs, host-specific paths) is **not** returned, so the kit stays portable.
- **downstream (kit → consumers)**: a tagged release propagates as a sync PR, gated by each
  consumer's CI.

This is the owner's workflow, not a requirement placed on third-party users. See [AGENTS.md](./AGENTS.md)
for the agent-facing rules and [ROADMAP.md](./ROADMAP.md) for how the loop is proven.

---

## EN/JA Documentation Sync

| File | Language | Role |
|---|---|---|
| `README.md` | English | **Source of truth** |
| `README.ja.md` | Japanese | Translation — update when `README.md` changes |

When updating `README.md`, reflect the same changes in `README.ja.md` before merging.

## License

Apache License 2.0 — see [LICENSE](./LICENSE).
