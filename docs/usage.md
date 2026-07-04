# Usage

How to install, configure, and wire gatecrate into a project. The default path is
**fire-and-forget**: install, configure, wire into CI — the scripts are then yours, with no
version to track and nothing to sync. Staying in sync and contributing back are **optional**
(see Advanced, for teams running several projects off one kit).

Japanese: [usage.ja.md](./usage.ja.md). For layout/rationale see [structure.md](./structure.md).

## 1. Install

From your project root, run the installer and pick a profile:

```sh
sh /path/to/gatecrate/install.sh --profile auto --target .
```

| Profile | Installs |
|---|---|
| `minimal` | core hygiene only (conventional title, no-secrets, file size) — **stack-neutral** |
| `auto` | detects the stack (pyproject.toml → python, …) — **recommended default** |
| `standard` | minimal + the Android-JVM adapter scripts — **not stack-neutral (Android)** |
| `python` / `go` / `rust` / `typescript` / `kotlin` / … | minimal + that stack's adapter |
| `full` | standard + heavier checks (mutation, smoke) |

The installer copies the selected scripts into `<target>/scripts/`, **creates `harness.config.sh`
from the template** (skipped if one already exists), and appends `build/` to `.gitignore`.

**Additive flags (pick what you need):**
- **`--with-skills`** — also install `.claude/skills/` and `.takt/` so the **agent-driven harness loop**
  (`gatecrate-setup`, `legacy-domain-extraction`, the TAKT workflows) is available. This is the
  higher-value path; the scripts-only install omits it.
- `--with-cc-sdd` — bootstrap cc-sdd via `npx cc-sdd@latest`, overlay gatecrate's steering, and install
  the mutation Stop hook (see the spec-driven loop section below).

**The copied scripts are now yours.** They resolve your repo root via `git rev-parse`, so they
run as-is; edit or delete them freely. You do not need to track a version or run any sync.

## 2. Configure: `harness.config.sh`

`install.sh` already created `harness.config.sh` in your repo root from the template (it is
skipped if one exists). Open it and set the values you need. To set it up by hand instead:

```sh
cp /path/to/gatecrate/templates/harness.config.sh.example harness.config.sh
```

It is plain shell, sourced by the scripts (NOT YAML). Set only the variables you need to override
— each has a default. Example:

```sh
# harness.config.sh
FILE_LINE_LIMIT=300                                    # check-file-line-limit.sh (core; all profiles)
FILE_LINE_NAMES="*.sh *.md"                            # which files the line gate scans
# BUILDCONFIG_PACKAGE=com.example.app.infrastructure   # run-mutation-tests.sh (Android-JVM)
# APP_PACKAGE=com.example.app                          # emulator-smoke.sh (Android-JVM)
# SPEC_LOOP_MODE=autonomous                            # spec-driven loop: autonomous | expert-gated
# SPEC_TEST_MUTATION_CMD="sh scripts/run-mutation-tests.sh"  # the Stop hook's survivor-strict mutation gate
```

Never put secrets here. Commit it — it is project config, not a secret store.

### The agent's spec-driven learning loop

Beyond the hygiene gates, gatecrate ships a loop where the agent explores a cluster, proposes the
domain model the code suggests, documents the spec, tests it with the ROI-chosen technique, and
measures adequacy with mutation — with an `autonomous` / `expert-gated` mode and an optional cc-sdd
integration (+ a Stop hook that mechanically enforces mutation after `validate-impl`). Full guide:
**[`spec-driven-loop.md`](spec-driven-loop.md)**.

To wire up the cc-sdd integration, run the installer with `--with-cc-sdd`. It **bootstraps cc-sdd
itself via `npx cc-sdd@latest`** (Node.js/`npx` required) and then overlays gatecrate's own steering
into `.kiro/steering/`. Override the cc-sdd target with env vars:

```sh
sh /path/to/gatecrate/install.sh --profile standard --target . --with-cc-sdd
# CC_SDD_AGENT (default --claude-skills; e.g. --codex-skills / --cursor-skills)
# CC_SDD_LANG  (default ja; e.g. en / zh / ko ...)
# CC_SDD_FLAGS (extra cc-sdd args, e.g. --kiro-dir docs)
```

`--with-cc-sdd` also installs the **mutation Stop hook** (`.claude/hooks/spec-test-mutation-gate.sh`
+ `.claude/settings.json`) so "green tests" can't end `validate-impl` while a mutant survives — the
mechanical half of the loop. If `.claude/settings.json` already exists, it is left untouched and you
merge `hooks.Stop` from `templates/hooks/settings-stop-hook.json` by hand.

If `npx` is absent, the installer warns and skips the cc-sdd bootstrap but still places the steering
file and Stop hook. To do it by hand: `npx cc-sdd@latest --claude-skills --lang ja`, then copy
`templates/kiro-steering/gatecrate-spec-test-loop.md` into `.kiro/steering/`. Note: steering is
placed under `.kiro/steering/` (the default `--kiro-dir`); if you pass `--kiro-dir`, move it to match.

After install, **run the mutation script once to confirm the mutation gate actually runs**
(prints a score, not a tooling crash) — a gate that exists but never executes gives false
assurance. The script name is per-adapter: `sh scripts/run-mutation-tests.sh` on Android-JVM
(the standard/full profiles), `sh scripts/run-mutation.sh` on the other adapters.

## 3. Run a script and wire it into CI

A kit script resolves your repo root and sources `harness.config.sh`, so you just run it:

```sh
sh scripts/check-file-line-limit.sh
```

Wire it into your CI like any script:

```yaml
- name: file line limit
  run: sh scripts/check-file-line-limit.sh
```

**That's the whole fire-and-forget flow.** The scripts are committed in your repo as your own
files. Nothing below is required — skip to "The kit's own CI" only if you're curious.

---

## Advanced: stay in sync & contribute (opt-in, for teams)

> **Skip this unless you run several projects off one shared kit and want harness fixes to
> propagate.** A fire-and-forget consumer never creates any of the files below — the installed
> scripts are already yours. This is the multi-project owner's workflow.

### Track the kit version: `sync-manifest.yaml`

Opt in by pinning which kit release you consume, so updates are detectable:

```yaml
# sync-manifest.yaml (repo root)
harness_kit_version: "v0.8.0"
adapter: android-jvm
consumed_scripts:
  - scripts/check-file-sizes.sh
```

`consumed_scripts` you opt into are synced together with their script co-dependencies.

### Receive updates (downstream: kit → you)

Copy `sync-propose.yml` from the kit into your `.github/workflows/`. Weekly (and on demand) it
compares your pinned version to the latest kit release and opens a **sync PR** with the changed
kit-managed scripts. Your own CI gates the PR; `harness.config.sh` is never touched. Set a
`HARNESS_SYNC_PAT` so the PR triggers that CI (otherwise it is created un-gated — see the warning
the workflow injects). Merge after green.

### Contribute improvements (upstream: you → kit)

Harness improvements usually start in a consumer. To return one:

1. Port it onto the kit's **generic** form — keep parameterization (`$VAR` defaults, `#!/bin/sh`,
   git-resolved root). Do **not** copy consumer-specific drift (hardcoded ids, host paths). Skip
   anything the kit already generalizes.
2. Open a PR against the kit, add a `CHANGELOG.md` entry, bump the version.

See [CONTRIBUTING.md](../CONTRIBUTING.md) and [AGENTS.md](../AGENTS.md) for the full rules.

## The kit's own CI

The kit gates its own PRs (`.github/workflows/ci.yml`): `sh -n` syntax, ShellCheck (`-S error`),
sync-manifest integrity, and a sync-check behavior test. `main` is protected (CI required,
conversation resolution required). Consumers do not need this — it protects the kit itself.
